#!/usr/bin/env bash

set -euo pipefail

scheduler_backend=${SCHEDULER_BACKEND:-pbs}

scheduler_require_backend() {
  case "$scheduler_backend" in
    pbs|slurm|local) ;;
    *)
      printf 'Unsupported scheduler backend: %s\n' "$scheduler_backend" >&2
      return 1
      ;;
  esac
}

# Monotonic counter for synthetic job ids in the local (scheduler-free) backend.
scheduler_local_job_counter=0

scheduler_resolve_script() {
  local script_path=$1

  # PBS and the local backend both run the .pbs body directly (its #PBS lines
  # are inert comments when the file is executed with bash).
  if [[ $scheduler_backend == "pbs" || $scheduler_backend == "local" ]]; then
    printf '%s\n' "$script_path"
    return 0
  fi

  case "$script_path" in
    *.pbs)
      local slurm_path=${script_path%.pbs}.slurm
      if [[ -f $slurm_path ]]; then
        printf '%s\n' "$slurm_path"
        return 0
      fi
      ;;
  esac

  printf '%s\n' "$script_path"
}

scheduler_mail_type_from_pbs() {
  local pbs_mail=${1:-}
  local -a types=()

  [[ $pbs_mail == *b* || $pbs_mail == *B* ]] && types+=("BEGIN")
  [[ $pbs_mail == *e* || $pbs_mail == *E* ]] && types+=("END")
  [[ $pbs_mail == *a* || $pbs_mail == *A* ]] && types+=("FAIL")

  if [[ ${#types[@]} -eq 0 ]]; then
    return 0
  fi

  local joined
  joined=$(IFS=,; printf '%s' "${types[*]}")
  printf '%s\n' "$joined"
}

scheduler_submit() {
  local job_name=$1
  local dependency_ids=$2
  local env_csv=$3
  local script_path=$4
  local log_dir=${5:-}
  local mail_options=${6:-}
  local mail_user=${7:-}

  scheduler_require_backend
  script_path=$(scheduler_resolve_script "$script_path")

  if [[ ! -f $script_path ]]; then
    printf 'Scheduler script not found: %s\n' "$script_path" >&2
    return 1
  fi

  if [[ -n $log_dir ]]; then
    mkdir -p "$log_dir"
  fi

  local output

  if [[ $scheduler_backend == "local" ]]; then
    # Scheduler-free execution: run the stage synchronously, in submission order.
    # Dependencies and mail options are irrelevant here because each stage
    # completes before the next scheduler_submit call returns, and a non-zero
    # exit propagates so the caller (set -e) aborts downstream stages just like
    # an afterok failure would.
    scheduler_local_job_counter=$((scheduler_local_job_counter + 1))
    local job_id="local-${scheduler_local_job_counter}"
    local log_target
    if [[ -n $log_dir ]]; then
      log_target="${log_dir}/${job_name:-$job_id}.log"
    else
      log_target="/dev/null"
    fi

    printf 'Running stage %s (%s) -> %s\n' \
      "$job_id" "${job_name:-unnamed}" "$log_target" >&2

    # Isolate env changes in a subshell: export the KEY=VAL pairs from env_csv,
    # provide the PBS_* variables the .pbs bodies expect, then run the stage.
    if (
      set +u
      IFS=','
      for kv in $env_csv; do
        [[ -n $kv ]] && export "${kv?}"
      done
      export PBS_O_WORKDIR="$PWD"
      export PBS_JOBID="$job_id"
      export PBS_JOBNAME="${job_name:-$job_id}"
      exec bash "$script_path"
    ) >"$log_target" 2>&1; then
      printf '%s\n' "$job_id"
      return 0
    else
      local rc=$?
      printf 'Local stage failed (%s), see log: %s\n' "$job_id" "$log_target" >&2
      return "$rc"
    fi
  fi

  if [[ $scheduler_backend == "pbs" ]]; then
    local -a cmd=(qsub)
    [[ -n $log_dir ]] && cmd+=(-o "$log_dir" -e "$log_dir")
    [[ -n $mail_options ]] && cmd+=(-m "$mail_options")
    [[ -n $mail_user ]] && cmd+=(-M "$mail_user")
    [[ -n $job_name ]] && cmd+=(-N "$job_name")
    [[ -n $dependency_ids ]] && cmd+=(-W "depend=afterok:${dependency_ids}")
    cmd+=(-v "$env_csv" "$script_path")
    output=$("${cmd[@]}")
    printf '%s\n' "${output%%.*}"
    return 0
  fi

  local -a cmd=(sbatch --parsable)
  if [[ -n $log_dir ]]; then
    cmd+=(-o "$log_dir/%x.%j.out" -e "$log_dir/%x.%j.err")
  fi

  if [[ -n $mail_options && -n $mail_user ]]; then
    local mail_type
    mail_type=$(scheduler_mail_type_from_pbs "$mail_options" || true)
    [[ -n $mail_type ]] && cmd+=(--mail-type "$mail_type" --mail-user "$mail_user")
  fi

  [[ -n $job_name ]] && cmd+=(--job-name "$job_name")
  [[ -n $dependency_ids ]] && cmd+=(--dependency "afterok:${dependency_ids}")
  cmd+=(--export "ALL,${env_csv}" "$script_path")

  output=$("${cmd[@]}")
  printf '%s\n' "${output%%;*}"
}
