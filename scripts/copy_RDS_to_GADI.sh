#!/usr/bin/env bash
# Run this script on Gadi. When launched from a login shell it always submits a
# PBS job and exits after printing the submitted job id. The same file then runs
# as the PBS payload on the compute side.
#
# Example:
#   RDS_SFTP_USER=<your_rds_username> \
#   ./scripts/copy_RDS_to_GADI.sh \
#     /rds/PRJ-AGAR/PRJ-AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
#     /scratch/rg42/AGAR/raw_data/2025/B07
#
#PBS -P rg42
#PBS -q copyq
#PBS -l walltime=08:00:00
#PBS -l mem=4GB
#PBS -l ncpus=1
#PBS -l jobfs=1GB
#PBS -l storage=gdata/rg42+scratch/rg42
#PBS -l wd
#PBS -N transfer_rds_to_gadi_job

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script_path="${script_dir}/$(basename "${BASH_SOURCE[0]}")"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/copy_RDS_to_GADI.sh RDS_SRC GADI_DEST

  ./scripts/copy_RDS_to_GADI.sh \
    /rds/PRJ-AGAR/PRJ-AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
    /scratch/rg42/AGAR/raw_data/2025/B07

This script always submits a PBS job on Gadi. It does not run the transfer
interactively in the login shell.

Optional environment variables:
  RDS_SFTP_USER             Required if USER is not the RDS username
  GADI_LOCAL_NAME           Rename the downloaded file or directory on Gadi
  RDS_SFTP_HOST             Default: research-data-ext.sydney.edu.au
  RDS_SFTP_OPTS             Extra options passed to sftp, for example: -v
  RDS_RESUME_DOWNLOAD       If set to 1, attempt resumable download mode, default: 1
  RDS_SKIP_IF_DEST_EXISTS   If set to 1, skip the download when the final local target already exists
  DEBUG_LOG_DIR             Directory for the detailed transfer run log
  PBS_LOG_DIR               Optional directory for scheduler stdout/stderr files
EOF
}

if [[ $# -gt 2 ]]; then
  usage >&2
  exit 1
fi

RDS_SRC=${1:-${RDS_SRC:-}}
GADI_DEST=${2:-${GADI_DEST:-}}
RDS_SFTP_USER=${RDS_SFTP_USER:-${USER:-}}
GADI_LOCAL_NAME=${GADI_LOCAL_NAME:-}
RDS_SFTP_HOST=${RDS_SFTP_HOST:-research-data-ext.sydney.edu.au}
RDS_SFTP_OPTS=${RDS_SFTP_OPTS:-}
RDS_RESUME_DOWNLOAD=${RDS_RESUME_DOWNLOAD:-1}
RDS_SKIP_IF_DEST_EXISTS=${RDS_SKIP_IF_DEST_EXISTS:-0}
DEBUG_LOG_DIR=${DEBUG_LOG_DIR:-${PBS_O_WORKDIR:-$PWD}/logs}
PBS_LOG_DIR=${PBS_LOG_DIR:-}

require_settings() {
  if [[ -z $RDS_SRC || -z $GADI_DEST ]]; then
    usage >&2
    exit 1
  fi

  if [[ -z $RDS_SFTP_USER ]]; then
    echo "RDS_SFTP_USER is required." >&2
    exit 1
  fi

  if ! [[ $RDS_RESUME_DOWNLOAD =~ ^[01]$ ]]; then
    echo "RDS_RESUME_DOWNLOAD must be 0 or 1." >&2
    exit 1
  fi

  if ! [[ $RDS_SKIP_IF_DEST_EXISTS =~ ^[01]$ ]]; then
    echo "RDS_SKIP_IF_DEST_EXISTS must be 0 or 1." >&2
    exit 1
  fi
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

submit_job() {
  local job_output
  local -a qsub_args

  require_settings

  mkdir -p "$DEBUG_LOG_DIR"
  if [[ -n $PBS_LOG_DIR ]]; then
    mkdir -p "$PBS_LOG_DIR"
    qsub_args=(-o "$PBS_LOG_DIR" -e "$PBS_LOG_DIR")
  else
    qsub_args=()
  fi

  export RDS_SRC
  export GADI_DEST
  export RDS_SFTP_USER
  export GADI_LOCAL_NAME
  export RDS_SFTP_HOST
  export RDS_SFTP_OPTS
  export RDS_RESUME_DOWNLOAD
  export RDS_SKIP_IF_DEST_EXISTS
  export DEBUG_LOG_DIR
  export PBS_LOG_DIR

  job_output=$(qsub -V "${qsub_args[@]}" "$script_path")
  printf 'Submitted PBS job %s for RDS restore\n' "${job_output%%.*}"
  printf 'RDS source: %s\n' "$RDS_SRC"
  printf 'Gadi destination parent: %s\n' "$GADI_DEST"
  printf 'Detailed transfer log dir: %s\n' "$DEBUG_LOG_DIR"
  if [[ -n $PBS_LOG_DIR ]]; then
    printf 'Scheduler stdout/stderr dir: %s\n' "$PBS_LOG_DIR"
  fi
}

sftp_quote() {
  printf '%s' "$1" | sed 's#\\#\\\\#g; s#"#\\"#g'
}

run_sftp() {
  local commands_file="$1"
  local output_file="$2"
  local error_file="$3"
  local -a sftp_opts_array

  if [[ -n $RDS_SFTP_OPTS ]]; then
    # shellcheck disable=SC2206
    sftp_opts_array=($RDS_SFTP_OPTS)
  else
    sftp_opts_array=()
  fi

  sftp "${sftp_opts_array[@]}" "${RDS_SFTP_USER}@${RDS_SFTP_HOST}" < "$commands_file" > "$output_file" 2> "$error_file"
}

extract_remote_listing() {
  awk '
    /^[dl-][rwxStTs-]{9}[[:space:]]+/ {
      print
      exit
    }
  ' "$1"
}

has_sftp_path_error() {
  grep -Eqi 'no such file|not found|couldn.t|can.t|failure|permission denied|not a directory' "$1"
}

remote_path_is_directory() {
  local remote_path="$1"
  local commands_file="$tmpdir/check_remote_dir.sftp"
  local output_file="$tmpdir/check_remote_dir.out"
  local error_file="$tmpdir/check_remote_dir.err"

  printf 'cd "%s"\npwd\nbye\n' "$(sftp_quote "$remote_path")" > "$commands_file"

  if ! run_sftp "$commands_file" "$output_file" "$error_file"; then
    return 1
  fi

  if has_sftp_path_error "$error_file"; then
    return 1
  fi

  if grep -Eq '^Remote working directory: |^sftp> pwd$' "$output_file"; then
    return 0
  fi

  return 1
}

remote_path_is_file() {
  local remote_path="$1"
  local commands_file="$tmpdir/check_remote_file.sftp"
  local output_file="$tmpdir/check_remote_file.out"
  local error_file="$tmpdir/check_remote_file.err"
  local remote_listing=""

  printf 'ls -l "%s"\nbye\n' "$(sftp_quote "$remote_path")" > "$commands_file"

  if ! run_sftp "$commands_file" "$output_file" "$error_file"; then
    return 1
  fi

  if has_sftp_path_error "$error_file"; then
    return 1
  fi

  remote_listing="$(extract_remote_listing "$output_file")"
  [[ -n $remote_listing ]]
}

run_transfer() {
  local debug_stamp debug_run_log
  local rds_src_trimmed default_local_name local_name local_target
  local remote_type download_commands download_output download_error info_file

  require_settings

  for cmd in sftp basename dirname mkdir mktemp awk sed grep date; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Required command not found: $cmd" >&2
      exit 1
    fi
  done

  mkdir -p "$DEBUG_LOG_DIR"
  debug_stamp=${PBS_JOBID:-manual}.$(date '+%Y%m%d_%H%M%S')
  debug_run_log="${DEBUG_RUN_LOG:-$DEBUG_LOG_DIR/transfer_rds_to_gadi.${debug_stamp}.run.log}"
  exec > >(tee -a "$debug_run_log") 2>&1

  log "Transfer job settings:"
  log "  PBS_JOBID=${PBS_JOBID:-<unset>}"
  log "  PBS_O_WORKDIR=${PBS_O_WORKDIR:-<unset>}"
  log "  DEBUG_RUN_LOG=$debug_run_log"
  log "  RDS_SRC=$RDS_SRC"
  log "  GADI_DEST=$GADI_DEST"
  log "  RDS_SFTP_USER=$RDS_SFTP_USER"
  log "  GADI_LOCAL_NAME=${GADI_LOCAL_NAME:-<source basename>}"
  log "  RDS_RESUME_DOWNLOAD=$RDS_RESUME_DOWNLOAD"
  log "  RDS_SKIP_IF_DEST_EXISTS=$RDS_SKIP_IF_DEST_EXISTS"

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  rds_src_trimmed="${RDS_SRC%/}"
  if [[ -z $rds_src_trimmed ]]; then
    echo "RDS source path must not be the filesystem root." >&2
    exit 1
  fi

  default_local_name="$(basename "$rds_src_trimmed")"
  local_name="${GADI_LOCAL_NAME:-$default_local_name}"
  local_target="${GADI_DEST%/}/$local_name"

  if [[ $local_name == */* ]]; then
    echo "GADI_LOCAL_NAME must be a single file or directory name, not a path: $local_name" >&2
    exit 1
  fi

  mkdir -p "$GADI_DEST"

  if [[ -e $local_target && $RDS_SKIP_IF_DEST_EXISTS == 1 ]]; then
    log "Destination already exists, skipping download: $local_target"
    exit 0
  fi

  if remote_path_is_directory "$rds_src_trimmed"; then
    remote_type=directory
  elif remote_path_is_file "$rds_src_trimmed"; then
    remote_type=file
  else
    echo "Failed to determine whether the RDS source is a file or directory: $rds_src_trimmed" >&2
    for debug_file in \
      "$tmpdir/check_remote_dir.out" \
      "$tmpdir/check_remote_dir.err" \
      "$tmpdir/check_remote_file.out" \
      "$tmpdir/check_remote_file.err"; do
      if [[ -s $debug_file ]]; then
        cat "$debug_file" >&2
      fi
    done
    exit 1
  fi

  if [[ $remote_type == directory && -e $local_target && ! -d $local_target ]]; then
    echo "Local destination exists but is not a directory: $local_target" >&2
    exit 1
  fi

  if [[ $remote_type == directory && -d $local_target ]]; then
    echo "Local destination already exists for a directory restore: $local_target" >&2
    echo "Use a fresh GADI_DEST or GADI_LOCAL_NAME, or set RDS_SKIP_IF_DEST_EXISTS=1 to leave it untouched." >&2
    exit 1
  fi

  if [[ $remote_type == file && -d $local_target ]]; then
    echo "Local destination exists as a directory but the RDS source is a file: $local_target" >&2
    exit 1
  fi

  download_commands="$tmpdir/download_rds_to_gadi.sftp"
  download_output="$tmpdir/download_rds_to_gadi.out"
  download_error="$tmpdir/download_rds_to_gadi.err"

  printf 'lcd "%s"\n' "$(sftp_quote "$GADI_DEST")" > "$download_commands"
  if [[ $remote_type == directory ]]; then
    if [[ $RDS_RESUME_DOWNLOAD == 1 ]]; then
      printf 'get -aR "%s" "%s"\n' "$(sftp_quote "$rds_src_trimmed")" "$(sftp_quote "$local_name")" >> "$download_commands"
    else
      printf 'get -R "%s" "%s"\n' "$(sftp_quote "$rds_src_trimmed")" "$(sftp_quote "$local_name")" >> "$download_commands"
    fi
  else
    if [[ $RDS_RESUME_DOWNLOAD == 1 ]]; then
      printf 'get -a "%s" "%s"\n' "$(sftp_quote "$rds_src_trimmed")" "$(sftp_quote "$local_name")" >> "$download_commands"
    else
      printf 'get "%s" "%s"\n' "$(sftp_quote "$rds_src_trimmed")" "$(sftp_quote "$local_name")" >> "$download_commands"
    fi
  fi
  printf 'bye\n' >> "$download_commands"

  log "RDS source: $rds_src_trimmed"
  log "Gadi destination parent: $GADI_DEST"
  log "Local target: $local_target"
  log "Remote path type: $remote_type"
  log "Resume download: $RDS_RESUME_DOWNLOAD"
  log "SFTP host: $RDS_SFTP_HOST"
  log "RDS SFTP user: $RDS_SFTP_USER"

  if ! run_sftp "$download_commands" "$download_output" "$download_error"; then
    cat "$download_error" >&2
    exit 1
  fi

  if [[ $remote_type == directory && ! -d $local_target ]]; then
    echo "Expected downloaded directory was not created: $local_target" >&2
    exit 1
  fi

  if [[ $remote_type == file && ! -f $local_target ]]; then
    echo "Expected downloaded file was not created: $local_target" >&2
    exit 1
  fi

  info_file="${GADI_DEST%/}/${local_name}_download_info.txt"
  cat > "$info_file" <<EOF
Data copied from: $rds_src_trimmed
Source type: $remote_type
Saved under: $local_target
Resume download: $RDS_RESUME_DOWNLOAD
Downloaded on: $(date '+%Y-%m-%d %H:%M:%S %Z')
EOF

  log "Download info file: $info_file"
  log "Download complete"
}

if [[ -z ${PBS_JOBID:-} ]]; then
  submit_job
else
  run_transfer
fi
