#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/submit_bactopia_batch_pipeline.sh INPUT_FILE BATCH_SIZE

Environment variables:
  BATCH_PREFIX            Default: agar_batch
  BATCH_DIR               Default: <input_dir>/batches
  BATCH_SKIP              Default: 0
  BATCH_LIMIT             Default: 2
  BATCH_CHAIN             Default: 0
  RUN_TOOLS               Default: 1
  RUN_ADDITIONAL_TOOLS    Default: 0
  DEFAULT_TOOLS_STRING    Default non-Kleborate tool list:
                          abritamr amrfinderplus bracken checkm mlst plasmidfinder
                          Kleborate is enabled separately through RUN_KLEBORATE
  ADDITIONAL_TOOLS_STRING Default additional non-Kleborate tool list:
                          defensefinder ectyper ismapper mashdist mobsuite mykrobe
                          phispy shigapass shigatyper shigeifinder
  TOOLS_STRING            Optional explicit non-Kleborate tool list for
                          run_extra_bactopia_tools.pbs. Overrides the default
                          and additional bundles when set.
  KRAKEN2_DB              Required if TOOLS_STRING includes kraken2 or bracken
  MYKROBE_SPECIES         Required if TOOLS_STRING includes mykrobe
  DEFENSEFINDER_DB        Optional database path for defensefinder
  RUN_KLEBORATE           Default: 1
  RUN_FIMTYPER            Default: 0
  FIMTYPER_PIPELINE       Required when RUN_FIMTYPER=1
  FIMTYPER_CONFIG         Required when RUN_FIMTYPER=1
  MERGE_FIMTYPER_SCRIPT   Optional merge helper run after FimTyper
  FIMTYPER_PROFILE        Optional Nextflow profile for FimTyper
  FIMTYPER_AFTER          assembly|tools|kleborate|all_tools, default: all_tools
  RUN_COLLECT_ASSEMBLIES  Default: 1
  ASSEMBLIES_OUTDIR       Default: <results_root>/<basename(results_root)>_assemblies
  RESULTS_ROOT            Default: /scratch/<project>/<user>/bactopia_results
  RUN_CONSOLIDATE         Default: 1
  CONSOLIDATED_OUTDIR     Default: <results_root>/<batch_prefix>_consolidated
  BASE_DIR                Default: repo root above this script
  SAMPLESHEET_DIR         Override batch sheet directory used by run_bactopia_batch.pbs
  PBS_LOG_DIR             Optional directory for qsub .o/.e files

Example:
  BATCH_SKIP=0 \
  BATCH_LIMIT=2 \
  BATCH_CHAIN=1 \
  RUN_TOOLS=1 \
  RUN_KLEBORATE=1 \
  RUN_FIMTYPER=1 \
  FIMTYPER_PIPELINE=/g/data/<project>/custom_bactopia_refs/fimtyper/fimtyper.nf \
  FIMTYPER_CONFIG=/g/data/<project>/custom_bactopia_refs/fimtyper/fimtyper.gadi.config \
  ./scripts/submit_bactopia_batch_pipeline.sh metadata/samplesheet.fofn 50
EOF
}

tools_string_contains() {
  local tool_name=$1
  shift
  local tool

  for tool in "$@"; do
    if [[ $tool == "$tool_name" ]]; then
      return 0
    fi
  done

  return 1
}

if [[ $# -ne 2 ]]; then
  usage >&2
  exit 1
fi

input_file=$1
batch_size=$2

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

BATCH_PREFIX=${BATCH_PREFIX:-agar_batch}
BATCH_DIR=${BATCH_DIR:-$(dirname "$input_file")/batches}
BATCH_SKIP=${BATCH_SKIP:-0}
BATCH_LIMIT=${BATCH_LIMIT:-2}
BATCH_CHAIN=${BATCH_CHAIN:-0}
RUN_TOOLS=${RUN_TOOLS:-1}
RUN_ADDITIONAL_TOOLS=${RUN_ADDITIONAL_TOOLS:-0}
DEFAULT_TOOLS_STRING=${DEFAULT_TOOLS_STRING:-abritamr amrfinderplus bracken checkm mlst plasmidfinder}
ADDITIONAL_TOOLS_STRING=${ADDITIONAL_TOOLS_STRING:-defensefinder ectyper ismapper mashdist mobsuite mykrobe phispy shigapass shigatyper shigeifinder}
TOOLS_STRING=${TOOLS_STRING:-}
KRAKEN2_DB=${KRAKEN2_DB:-}
MYKROBE_SPECIES=${MYKROBE_SPECIES:-}
DEFENSEFINDER_DB=${DEFENSEFINDER_DB:-}
RUN_KLEBORATE=${RUN_KLEBORATE:-1}
RUN_FIMTYPER=${RUN_FIMTYPER:-0}
FIMTYPER_PIPELINE=${FIMTYPER_PIPELINE:-}
FIMTYPER_CONFIG=${FIMTYPER_CONFIG:-}
MERGE_FIMTYPER_SCRIPT=${MERGE_FIMTYPER_SCRIPT:-}
FIMTYPER_PROFILE=${FIMTYPER_PROFILE:-}
FIMTYPER_AFTER=${FIMTYPER_AFTER:-all_tools}
RUN_COLLECT_ASSEMBLIES=${RUN_COLLECT_ASSEMBLIES:-1}
RUN_CONSOLIDATE=${RUN_CONSOLIDATE:-1}
BASE_DIR=${BASE_DIR:-$(cd "$script_dir/.." && pwd)}
SAMPLESHEET_DIR=${SAMPLESHEET_DIR:-$BATCH_DIR}
run_user=${USER_NAME:-${USER:-unknown}}
RESULTS_ROOT=${RESULTS_ROOT:-/scratch/${PROJECT:-rg42}/${run_user}/bactopia_results}
results_root_base=$(basename "$RESULTS_ROOT")
ASSEMBLIES_OUTDIR=${ASSEMBLIES_OUTDIR:-${RESULTS_ROOT}/${results_root_base}_assemblies}
CONSOLIDATED_OUTDIR=${CONSOLIDATED_OUTDIR:-${RESULTS_ROOT}/${BATCH_PREFIX}_consolidated}
NEXTFLOW_CONFIG=${NEXTFLOW_CONFIG:-}
BACTOPIA_PIPELINE=${BACTOPIA_PIPELINE:-}
DATASETS_CACHE=${DATASETS_CACHE:-}
SING_CACHE=${SING_CACHE:-}
KLEBORATE_COMPAT_SCRIPT=${KLEBORATE_COMPAT_SCRIPT:-$script_dir/kleborate_232_compat.sh}
PBS_LOG_DIR=${PBS_LOG_DIR:-}

qsub_log_args=()
if [[ -n $PBS_LOG_DIR ]]; then
  mkdir -p "$PBS_LOG_DIR"
  qsub_log_args=(-o "$PBS_LOG_DIR" -e "$PBS_LOG_DIR")
fi

if [[ ! -f $input_file ]]; then
  echo "Input file not found: $input_file" >&2
  exit 1
fi

if ! [[ $batch_size =~ ^[1-9][0-9]*$ ]]; then
  echo "BATCH_SIZE must be a positive integer: $batch_size" >&2
  exit 1
fi

if ! [[ $BATCH_SKIP =~ ^[0-9]+$ ]]; then
  echo "BATCH_SKIP must be a non-negative integer: $BATCH_SKIP" >&2
  exit 1
fi

if ! [[ $BATCH_LIMIT =~ ^[1-9][0-9]*$ ]]; then
  echo "BATCH_LIMIT must be a positive integer: $BATCH_LIMIT" >&2
  exit 1
fi

if [[ ${BATCH_CHAIN:-0} != 0 && ${BATCH_CHAIN:-0} != 1 ]]; then
  echo "BATCH_CHAIN must be 0 or 1: ${BATCH_CHAIN}" >&2
  exit 1
fi

if [[ ${RUN_ADDITIONAL_TOOLS:-0} != 0 && ${RUN_ADDITIONAL_TOOLS:-0} != 1 ]]; then
  echo "RUN_ADDITIONAL_TOOLS must be 0 or 1: ${RUN_ADDITIONAL_TOOLS}" >&2
  exit 1
fi

if [[ ${RUN_COLLECT_ASSEMBLIES:-0} != 0 && ${RUN_COLLECT_ASSEMBLIES:-0} != 1 ]]; then
  echo "RUN_COLLECT_ASSEMBLIES must be 0 or 1: ${RUN_COLLECT_ASSEMBLIES}" >&2
  exit 1
fi

if [[ $RUN_FIMTYPER != 0 && $FIMTYPER_AFTER != "assembly" && $FIMTYPER_AFTER != "tools" && $FIMTYPER_AFTER != "kleborate" && $FIMTYPER_AFTER != "all_tools" ]]; then
  echo "FIMTYPER_AFTER must be 'assembly', 'tools', 'kleborate', or 'all_tools'." >&2
  exit 1
fi

if [[ $RUN_FIMTYPER != 0 && ( -z $FIMTYPER_PIPELINE || -z $FIMTYPER_CONFIG ) ]]; then
  echo "FIMTYPER_PIPELINE and FIMTYPER_CONFIG are required when RUN_FIMTYPER is enabled." >&2
  exit 1
fi

if [[ -z $TOOLS_STRING ]]; then
  TOOLS_STRING=$DEFAULT_TOOLS_STRING
  if [[ $RUN_ADDITIONAL_TOOLS != 0 ]]; then
    TOOLS_STRING="${TOOLS_STRING} ${ADDITIONAL_TOOLS_STRING}"
  fi
fi

# shellcheck disable=SC2206
TOOLS_LIST=($TOOLS_STRING)

if [[ $RUN_TOOLS != 0 ]]; then
  if [[ -z $KRAKEN2_DB ]] && ( tools_string_contains "kraken2" "${TOOLS_LIST[@]}" || tools_string_contains "bracken" "${TOOLS_LIST[@]}" ); then
    echo "KRAKEN2_DB is required when TOOLS_STRING includes kraken2 or bracken." >&2
    exit 1
  fi

  if [[ -z $MYKROBE_SPECIES ]] && tools_string_contains "mykrobe" "${TOOLS_LIST[@]}"; then
    echo "MYKROBE_SPECIES is required when TOOLS_STRING includes mykrobe." >&2
    exit 1
  fi
fi

"$script_dir/split_bactopia_samplesheet.sh" "$input_file" "$batch_size" "$BATCH_DIR" "$BATCH_PREFIX" >/tmp/bactopia_batch_split.$$ 

mapfile -t batch_files < <(tail -n +2 /tmp/bactopia_batch_split.$$)
rm -f /tmp/bactopia_batch_split.$$

if [[ ${#batch_files[@]} -eq 0 ]]; then
  echo "No batch files were created." >&2
  exit 1
fi

selected_batch_files=("${batch_files[@]:$BATCH_SKIP:$BATCH_LIMIT}")

if [[ ${#selected_batch_files[@]} -eq 0 ]]; then
  echo "No batch files selected after applying BATCH_SKIP=${BATCH_SKIP} and BATCH_LIMIT=${BATCH_LIMIT}." >&2
  exit 1
fi

echo "Submitting ${#selected_batch_files[@]} batch pipeline(s) from ${#batch_files[@]} total batch file(s)"

terminal_jobs=()
assembly_jobs=()
previous_batch_terminal_job=

for batch_file in "${selected_batch_files[@]}"; do
  batch_base=$(basename "$batch_file" .csv)
  batch_base=${batch_base%.fofn}
  batch_base=${batch_base%.tsv}
  batch_id=${batch_base##*_}
  run_label=${BATCH_PREFIX}_${batch_id}
  results_main=${RESULTS_ROOT}/${run_label}/results_main
  tools_outdir=${RESULTS_ROOT}/${run_label}_tools
  kleborate_outdir=${RESULTS_ROOT}/${run_label}_kleborate
  fimtyper_outdir=${RESULTS_ROOT}/${run_label}_fimtyper
  assembly_job_name=$(printf 'b%s_bactopia' "$batch_id")
  tools_job_name=$(printf 'tools_b%s' "$batch_id")
  kleborate_job_name=$(printf 'klebo_b%s' "$batch_id")
  fimtyper_job_name=$(printf 'fimtyper_b%s' "$batch_id")

  assembly_qsub_args=(
    -N "$assembly_job_name"
  )

  if [[ ${#qsub_log_args[@]} -gt 0 ]]; then
    assembly_qsub_args+=("${qsub_log_args[@]}")
  fi

  if [[ $BATCH_CHAIN == 1 && -n "$previous_batch_terminal_job" ]]; then
    assembly_qsub_args+=(-W "depend=afterok:${previous_batch_terminal_job}")
  fi

  assembly_qsub_args+=(
    -v "BASE_DIR=${BASE_DIR},SAMPLESHEET_DIR=${SAMPLESHEET_DIR},SAMPLESHEET_PREFIX=${BATCH_PREFIX},BATCH_ID=${batch_id},BATCH_INPUT_FILE=${batch_file},RESULTS_ROOT=${RESULTS_ROOT},NEXTFLOW_CONFIG=${NEXTFLOW_CONFIG},BACTOPIA_PIPELINE=${BACTOPIA_PIPELINE},DATASETS_CACHE=${DATASETS_CACHE},SING_CACHE=${SING_CACHE}"
    "$script_dir/run_bactopia_batch.pbs"
  )

  assembly_job=$(qsub "${assembly_qsub_args[@]}")
  assembly_job=${assembly_job%%.*}
  echo "${run_label}: assembly job ${assembly_job}"
  assembly_jobs+=("${assembly_job}")

  dependency_job=$assembly_job
  tools_job=
  kleborate_job=

  if [[ $RUN_TOOLS != 0 ]]; then
    tools_job=$(qsub "${qsub_log_args[@]}" -N "$tools_job_name" \
      -W "depend=afterok:${assembly_job}" \
      -v "BASE_DIR=${BASE_DIR},RESULTS_MAIN=${results_main},RUN_LABEL=${run_label}_tools,RESULTS_OUT=${tools_outdir},RESULTS_ROOT=${RESULTS_ROOT},TOOLS_STRING=${TOOLS_STRING},KRAKEN2_DB=${KRAKEN2_DB},MYKROBE_SPECIES=${MYKROBE_SPECIES},DEFENSEFINDER_DB=${DEFENSEFINDER_DB},NEXTFLOW_CONFIG=${NEXTFLOW_CONFIG},BACTOPIA_PIPELINE=${BACTOPIA_PIPELINE},DATASETS_CACHE=${DATASETS_CACHE},SING_CACHE=${SING_CACHE}" \
      "$script_dir/run_extra_bactopia_tools.pbs")
    tools_job=${tools_job%%.*}
    echo "${run_label}: non-kleborate tools job ${tools_job}"
  fi

  if [[ $RUN_KLEBORATE != 0 ]]; then
    kleborate_job=$(qsub "${qsub_log_args[@]}" -N "$kleborate_job_name" \
      -W "depend=afterok:${assembly_job}" \
      -v "BASE_DIR=${BASE_DIR},RESULTS_MAIN=${results_main},RUN_LABEL=${run_label}_kleborate,RESULTS_OUT=${kleborate_outdir},RESULTS_ROOT=${RESULTS_ROOT},NEXTFLOW_CONFIG=${NEXTFLOW_CONFIG},BACTOPIA_PIPELINE=${BACTOPIA_PIPELINE},DATASETS_CACHE=${DATASETS_CACHE},SING_CACHE=${SING_CACHE},KLEBORATE_COMPAT_SCRIPT=${KLEBORATE_COMPAT_SCRIPT}" \
      "$script_dir/run_kleborate_batch.pbs")
    kleborate_job=${kleborate_job%%.*}
    echo "${run_label}: kleborate job ${kleborate_job}"
  fi

  case "$FIMTYPER_AFTER" in
    assembly)
      dependency_job=$assembly_job
      ;;
    tools)
      if [[ -n "$tools_job" ]]; then
        dependency_job=$tools_job
      fi
      ;;
    kleborate)
      if [[ -n "$kleborate_job" ]]; then
        dependency_job=$kleborate_job
      fi
      ;;
    all_tools)
      if [[ -n "$tools_job" && -n "$kleborate_job" ]]; then
        dependency_job="${tools_job}:${kleborate_job}"
      elif [[ -n "$tools_job" ]]; then
        dependency_job=$tools_job
      elif [[ -n "$kleborate_job" ]]; then
        dependency_job=$kleborate_job
      fi
      ;;
  esac

  if [[ $RUN_FIMTYPER != 0 ]]; then
    if [[ -z "$dependency_job" ]]; then
      echo "${run_label}: could not determine FimTyper dependency." >&2
      exit 1
    fi
  fi

  if [[ $RUN_FIMTYPER != 0 ]]; then
    fimtyper_job=$(qsub "${qsub_log_args[@]}" -N "$fimtyper_job_name" \
      -W "depend=afterok:${dependency_job}" \
      -v "BASE_DIR=${BASE_DIR},RESULTS_MAIN=${results_main},RUN_LABEL=${run_label}_fimtyper,RESULTS_OUT=${fimtyper_outdir},RESULTS_ROOT=${RESULTS_ROOT},FIMTYPER_PIPELINE=${FIMTYPER_PIPELINE},FIMTYPER_CONFIG=${FIMTYPER_CONFIG},MERGE_FIMTYPER_SCRIPT=${MERGE_FIMTYPER_SCRIPT},FIMTYPER_PROFILE=${FIMTYPER_PROFILE},SING_CACHE=${SING_CACHE}" \
      "$script_dir/run_fimtyper_batch.pbs")
    fimtyper_job=${fimtyper_job%%.*}
    echo "${run_label}: fimtyper job ${fimtyper_job}"
    dependency_job=$fimtyper_job
  fi

  terminal_jobs+=("${dependency_job}")
  previous_batch_terminal_job=$dependency_job
done

if [[ $RUN_COLLECT_ASSEMBLIES != 0 && ${#assembly_jobs[@]} -gt 0 ]]; then
  dependency_string=$(IFS=:; echo "${assembly_jobs[*]}")
  assemblies_job=$(qsub "${qsub_log_args[@]}" -W "depend=afterok:${dependency_string}" \
    -v "INPUT_PATH=${RESULTS_ROOT},OUTPUT_DIR=${ASSEMBLIES_OUTDIR}" \
    "$script_dir/run_fetch_batch_assemblies.pbs")
  assemblies_job=${assemblies_job%%.*}
  echo "assemblies job ${assemblies_job}: ${ASSEMBLIES_OUTDIR}"
fi

if [[ $RUN_CONSOLIDATE != 0 && ${#terminal_jobs[@]} -gt 0 ]]; then
  dependency_string=$(IFS=:; echo "${terminal_jobs[*]}")
  consolidate_job=$(qsub "${qsub_log_args[@]}" -W "depend=afterok:${dependency_string}" \
    -v "BASE_DIR=${BASE_DIR},RESULTS_ROOT=${RESULTS_ROOT},BATCH_PREFIX=${BATCH_PREFIX},CONSOLIDATED_OUTDIR=${CONSOLIDATED_OUTDIR},CONSOLIDATE_SCRIPT=${script_dir}/consolidate_bactopia_batches.R" \
    "$script_dir/run_consolidate_batches.pbs")
  consolidate_job=${consolidate_job%%.*}
  echo "consolidation job ${consolidate_job}: ${CONSOLIDATED_OUTDIR}"
fi
