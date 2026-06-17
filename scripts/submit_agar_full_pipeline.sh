#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/submit_agar_full_pipeline.sh RAW_FASTQ_DIR METADATA_DIR RESULTS_ROOT [BATCH_SIZE]
  ./scripts/submit_agar_full_pipeline.sh --config scripts/gadi_pipeline.env RAW_FASTQ_DIR METADATA_DIR RESULTS_ROOT [BATCH_SIZE]

Example:
  ./scripts/submit_agar_full_pipeline.sh \
    /scratch/rg42/AGAR/rawdata/2025/B05 \
    /scratch/rg42/AGAR/metadata/2025/B05 \
    /scratch/rg42/AGAR/intermediates/2025/B05 \
    50

What this script does:
  1. Normalize FASTQ sample names
  2. Create the Bactopia FOFN/samplesheet if requested
  3. Validate the FOFN
  4. Submit the batch workflow
  5. Submit metadata-sheet result mapping after consolidation completes

Inputs:
  RAW_FASTQ_DIR  Raw FASTQ directory, for example /scratch/rg42/AGAR/rawdata/2025/B05
  METADATA_DIR   Metadata directory containing *_samplesheet.txt and/or samplesheet.fofn
                 The metadata sheet must contain 'Sample name' and 'Comments'.
                 Other metadata columns are ignored by downstream metadata mapping.
  RESULTS_ROOT   Intermediate results directory, for example /scratch/rg42/AGAR/intermediates/2025/B05
  BATCH_SIZE     Default: 50

Environment variables:
  PIPELINE_CONFIG        Optional shell env file to source before resolving defaults
  RUN_AGAR_DIR           Default: directory above this script
  SAMPLESHEET_PATH       Default: <METADATA_DIR>/samplesheet.fofn
  AGRF_SHEET_PATH        Optional explicit metadata sheet path. Default: first <METADATA_DIR>/*_samplesheet.txt match
  BATCH_PREFIX           Default: batch_bactopia
  BATCH_DIR              Default: <METADATA_DIR>/batches
  CREATE_FOFN_SCRIPT     Default: <script_dir>/2_create_fofn_bactopia.sh
  CREATE_FOFN_COMMAND    Optional shell command template to create the FOFN
                         Supported placeholders: {RAWDATA_DIR} {METADATA_DIR} {SAMPLESHEET_OUT}
  IS_AGAR_PROJECT        Default: auto. Set to 1 to force AGAR filename normalization,
                         0 to skip it for non-AGAR projects
  POSTPROCESS_ONLY       Default: 0. Set to 1 to skip FASTQ and batch submission
                         and only run consolidation, mapping, review, and workbook export
  SKIP_NORMALIZE         Set to 1 to skip FASTQ name normalization
  SKIP_VALIDATE          Set to 1 to skip FOFN validation
  RUN_CONSOLIDATE        Default: 1. Set to 0 in POSTPROCESS_ONLY mode to reuse
                         an existing consolidated directory
  MAP_AGRF_RESULTS       Default: 1. Set to 0 to skip post-consolidation AGRF mapping
  RUN_MLST_REVIEW        Default: 1. Set to 0 to skip the standalone MLST review follow-up
  RUN_POST_REVIEW_MAP    Default: 0. Set to 1 only if you explicitly want a
                         second AGRF remap driven by mlst_review.tsv
  RUN_EXPORT_RESULTS_WORKBOOK Default: 1. Set to 0 to skip final Excel workbook export
  MAP_OUTPUT             Default: <RESULTS_ROOT>/AGRF_samplesheet_with_results.tsv
  REVIEW_OUTPUT_DIR      Default: <RESULTS_ROOT>/mlst_review_standalone
  POST_REVIEW_MAP_OUTPUT Default: <RESULTS_ROOT>/AGRF_samplesheet_with_results_post_review.tsv
  RESULTS_WORKBOOK_OUTPUT Default: <RESULTS_ROOT>/<basename(RESULTS_ROOT)>_results.xlsx
  LOG_DIR                Default: dirname(LOG_FILE) or <RESULTS_ROOT>
  LOG_FILE               Default: <RESULTS_ROOT>/submit_agar_full_pipeline_<timestamp>.log
  PBS_LOG_DIR            Optional directory for all qsub .o/.e files
  CONSOLIDATE_PBS_SCRIPT Default: <script_dir>/run_consolidate_batches.pbs
  CONSOLIDATE_SCRIPT     Default: <script_dir>/consolidate_bactopia_batches.R

All environment variables used by submit_bactopia_batch_pipeline.sh are also honored,
for example RESULTS_ROOT, NEXTFLOW_CONFIG, DATASETS_CACHE, RUN_TOOLS, RUN_KLEBORATE,
RUN_ADDITIONAL_TOOLS, TOOLS_STRING, RUN_FIMTYPER, FIMTYPER_PIPELINE,
FIMTYPER_CONFIG, RUN_COLLECT_ASSEMBLIES, ASSEMBLIES_OUTDIR, BATCH_SKIP,
BATCH_START, BATCH_LIMIT, BATCH_CHAIN, BATCH_IDS.
EOF
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

pipeline_config=${PIPELINE_CONFIG:-}

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --config)
      if [[ $# -lt 2 ]]; then
        echo "--config requires a path" >&2
        usage >&2
        exit 1
      fi
      pipeline_config=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ -z $pipeline_config && -f $script_dir/gadi_pipeline.env ]]; then
  pipeline_config=$script_dir/gadi_pipeline.env
fi

if [[ -n $pipeline_config ]]; then
  if [[ ! -f $pipeline_config ]]; then
    echo "PIPELINE_CONFIG not found: $pipeline_config" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$pipeline_config"
fi

if [[ $# -lt 3 || $# -gt 4 ]]; then
  usage >&2
  exit 1
fi

raw_fastq_dir=$1
metadata_dir=$2
results_root_arg=$3
batch_size=${4:-50}

run_agar_dir=${RUN_AGAR_DIR:-$(cd "$script_dir/.." && pwd)}

samplesheet_path=${SAMPLESHEET_PATH:-$metadata_dir/samplesheet.fofn}
agrf_sheet_path=${AGRF_SHEET_PATH:-}
batch_prefix=${BATCH_PREFIX:-batch_bactopia}
batch_dir=${BATCH_DIR:-$metadata_dir/batches}
create_fofn_command=${CREATE_FOFN_COMMAND:-}
create_fofn_script=${CREATE_FOFN_SCRIPT:-$script_dir/2_create_fofn_bactopia.sh}
postprocess_only=${POSTPROCESS_ONLY:-0}
skip_normalize=${SKIP_NORMALIZE:-0}
skip_validate=${SKIP_VALIDATE:-0}
run_consolidate=${RUN_CONSOLIDATE:-1}
map_agrf_results=${MAP_AGRF_RESULTS:-1}
run_mlst_review=${RUN_MLST_REVIEW:-1}
run_post_review_map=${RUN_POST_REVIEW_MAP:-0}
run_export_results_workbook=${RUN_EXPORT_RESULTS_WORKBOOK:-1}
map_output=${MAP_OUTPUT:-$results_root_arg/AGRF_samplesheet_with_results.tsv}
review_output_dir=${REVIEW_OUTPUT_DIR:-$results_root_arg/mlst_review_standalone}
post_review_map_output=${POST_REVIEW_MAP_OUTPUT:-$results_root_arg/AGRF_samplesheet_with_results_post_review.tsv}
results_workbook_output=${RESULTS_WORKBOOK_OUTPUT:-$results_root_arg/$(basename "$results_root_arg")_results.xlsx}
log_dir=${LOG_DIR:-}
if [[ -n ${LOG_FILE:-} ]]; then
  log_file=$LOG_FILE
elif [[ -n $log_dir ]]; then
  log_file=${log_dir%/}/submit_agar_full_pipeline_$(date '+%Y%m%d_%H%M%S').log
else
  log_file=$results_root_arg/submit_agar_full_pipeline_$(date '+%Y%m%d_%H%M%S').log
fi

submit_script=${SUBMIT_PIPELINE_SCRIPT:-$script_dir/submit_bactopia_batch_pipeline.sh}
normalize_script=${NORMALIZE_SCRIPT:-$script_dir/normalize_agar_fastq_sample_names.sh}
validate_script=${VALIDATE_FOFN_SCRIPT:-$script_dir/validate_bactopia_fofn.sh}
consolidate_pbs_script=${CONSOLIDATE_PBS_SCRIPT:-$script_dir/run_consolidate_batches.pbs}
consolidate_r_script=${CONSOLIDATE_SCRIPT:-$script_dir/consolidate_bactopia_batches.R}
map_pbs_script=${MAP_PBS_SCRIPT:-$script_dir/run_map_agrf_samplesheet_results.pbs}
map_r_script=${MAP_R_SCRIPT:-$script_dir/map_agrf_samplesheet_results.R}
review_mlst_pbs_script=${REVIEW_MLST_PBS_SCRIPT:-$script_dir/run_review_mlst_from_tsv.pbs}
export_results_workbook_pbs_script=${EXPORT_RESULTS_WORKBOOK_PBS_SCRIPT:-$script_dir/run_export_bactopia_results_workbook.pbs}
export_results_workbook_python_bin=${EXPORT_RESULTS_WORKBOOK_PYTHON_BIN:-python3}
export_results_workbook_script=${EXPORT_RESULTS_WORKBOOK_SCRIPT:-$script_dir/export_bactopia_results_workbook.py}
is_agar_project=${IS_AGAR_PROJECT:-auto}
current_step="initialization"

mkdir -p "$(dirname "$log_file")"
exec > >(tee -a "$log_file") 2>&1

log() {
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2"
}

fail() {
  log "ERROR" "$1"
  exit 1
}

on_error() {
  local exit_code=$?
  log "ERROR" "Step failed: ${current_step} (exit code ${exit_code}, line ${BASH_LINENO[0]})"
  exit "$exit_code"
}

trap on_error ERR

resolve_is_agar_project() {
  local setting="${1:-auto}"

  case "${setting,,}" in
    1|true|yes|y|agar)
      return 0
      ;;
    0|false|no|n|other|non-agar|non_agar)
      return 1
      ;;
    auto|"")
      ;;
    *)
      fail "IS_AGAR_PROJECT must be one of: auto, 1, 0, true, false, agar, other"
      ;;
  esac

  local candidate=""
  for candidate in "$raw_fastq_dir" "$metadata_dir" "$results_root_arg" "${agrf_sheet_path:-}"; do
    [[ -z $candidate ]] && continue
    case "/$candidate/" in
      */AGAR/*|*/PRJ-AGAR/*|*/AGRF_*/*|*/agar_samplesheet.txt/*)
        return 0
        ;;
    esac
  done

  return 1
}

find_metadata_sheet() {
  local dir=$1
  local matches=()
  local candidate=""

  shopt -s nullglob
  for candidate in "$dir"/*_samplesheet.txt; do
    [[ -f $candidate ]] || continue
    matches+=("$candidate")
  done
  shopt -u nullglob

  if [[ ${#matches[@]} -eq 1 ]]; then
    printf '%s\n' "${matches[0]}"
    return 0
  fi

  if [[ ${#matches[@]} -gt 1 ]]; then
    fail "Multiple metadata samplesheets found in $dir: ${matches[*]}. Keep exactly one *_samplesheet.txt or set AGRF_SHEET_PATH explicitly."
  fi

  return 1
}

if [[ -z $agrf_sheet_path ]]; then
  if ! agrf_sheet_path=$(find_metadata_sheet "$metadata_dir"); then
    agrf_sheet_path=$metadata_dir/metadata_samplesheet.txt
  fi
fi

log "INFO" "Pipeline log file: $log_file"
log "INFO" "RAW_FASTQ_DIR=$raw_fastq_dir"
log "INFO" "METADATA_DIR=$metadata_dir"
log "INFO" "RESULTS_ROOT=$results_root_arg"
log "INFO" "SAMPLESHEET_PATH=$samplesheet_path"
log "INFO" "METADATA_SHEET_PATH=$agrf_sheet_path"

if [[ ! -d $raw_fastq_dir ]]; then
  fail "RAW_FASTQ_DIR not found: $raw_fastq_dir"
fi

if [[ ! -d $metadata_dir ]]; then
  fail "METADATA_DIR not found: $metadata_dir"
fi

if ! [[ $batch_size =~ ^[1-9][0-9]*$ ]]; then
  fail "BATCH_SIZE must be a positive integer: $batch_size"
fi

for path in "$submit_script" "$normalize_script" "$validate_script" "$consolidate_pbs_script" "$consolidate_r_script" "$map_pbs_script" "$map_r_script" "$review_mlst_pbs_script"; do
  if [[ ! -f $path ]]; then
    fail "Required script not found: $path"
  fi
done

if [[ $run_export_results_workbook == 1 ]]; then
  for path in "$export_results_workbook_pbs_script" "$export_results_workbook_script"; do
    if [[ ! -f $path ]]; then
      fail "Required workbook export script not found: $path"
    fi
  done
fi

if [[ $postprocess_only != 1 ]]; then
  current_step="checking raw FASTQ inputs"
  fastq_count=$(find "$raw_fastq_dir" -maxdepth 1 -type f \( -name "*.fastq.gz" -o -name "*.fq.gz" \) | wc -l | tr -d ' ')
  if [[ $fastq_count -eq 0 ]]; then
    fail "No FASTQ files were found in RAW_FASTQ_DIR: $raw_fastq_dir"
  fi
  log "INFO" "Detected $fastq_count FASTQ files in raw data directory"
else
  log "INFO" "POSTPROCESS_ONLY=1. FASTQ checks, FOFN creation, validation, and batch submission will be skipped."
fi

current_step="checking metadata inputs"
if [[ ! -f $agrf_sheet_path ]]; then
  fail "Metadata samplesheet not found in metadata directory. Expected exactly one $metadata_dir/*_samplesheet.txt file or set AGRF_SHEET_PATH explicitly."
fi
log "INFO" "Detected metadata samplesheet: $agrf_sheet_path"

if resolve_is_agar_project "$is_agar_project"; then
  is_agar_project=1
  log "INFO" "Project detection: AGAR. FASTQ filename normalization is enabled."
else
  is_agar_project=0
  log "INFO" "Project detection: non-AGAR. FASTQ filename normalization will be skipped."
fi

if [[ $postprocess_only == 1 ]]; then
  log "INFO" "Skipping FASTQ sample name normalization in POSTPROCESS_ONLY mode"
elif [[ $skip_normalize != 1 && $is_agar_project == 1 ]]; then
  current_step="normalizing FASTQ sample names"
  log "INFO" "Normalizing FASTQ sample names in: $raw_fastq_dir"
  "$normalize_script" "$raw_fastq_dir"
elif [[ $skip_normalize == 1 ]]; then
  log "INFO" "Skipping FASTQ sample name normalization because SKIP_NORMALIZE=1"
else
  log "INFO" "Skipping FASTQ sample name normalization for non-AGAR project input"
fi

if [[ $postprocess_only == 1 ]]; then
  log "INFO" "Skipping FOFN creation and validation in POSTPROCESS_ONLY mode"
elif [[ -n $create_fofn_command ]]; then
  current_step="creating Bactopia FOFN with CREATE_FOFN_COMMAND"
  mkdir -p "$(dirname "$samplesheet_path")"
  fofn_cmd=${create_fofn_command//\{RAWDATA_DIR\}/$raw_fastq_dir}
  fofn_cmd=${fofn_cmd//\{METADATA_DIR\}/$metadata_dir}
  fofn_cmd=${fofn_cmd//\{SAMPLESHEET_OUT\}/$samplesheet_path}
  log "INFO" "Creating Bactopia samplesheet/FOFN: $samplesheet_path"
  eval "$fofn_cmd"
elif [[ ! -f $samplesheet_path && -f $create_fofn_script ]]; then
  current_step="creating Bactopia FOFN with CREATE_FOFN_SCRIPT"
  mkdir -p "$(dirname "$samplesheet_path")"
  log "INFO" "Creating Bactopia samplesheet/FOFN with: $create_fofn_script"
  "$create_fofn_script" "$raw_fastq_dir" "$samplesheet_path"
fi

if [[ $postprocess_only != 1 && ! -f $samplesheet_path ]]; then
  fail "Samplesheet/FOFN not found: $samplesheet_path. Either create it first or provide CREATE_FOFN_COMMAND / CREATE_FOFN_SCRIPT."
fi

if [[ $postprocess_only != 1 && $skip_validate != 1 ]]; then
  current_step="validating FOFN"
  log "INFO" "Validating FOFN: $samplesheet_path"
  "$validate_script" "$samplesheet_path"
fi

current_step="preparing batch submission"
mkdir -p "$batch_dir"

export RESULTS_ROOT=${RESULTS_ROOT:-$results_root_arg}
export BATCH_DIR="$batch_dir"
export BATCH_PREFIX="$batch_prefix"
export PBS_LOG_DIR=${PBS_LOG_DIR:-}

top_level_qsub_log_args=()
if [[ -n ${PBS_LOG_DIR:-} ]]; then
  mkdir -p "$PBS_LOG_DIR"
  top_level_qsub_log_args=(-o "$PBS_LOG_DIR" -e "$PBS_LOG_DIR")
fi

consolidated_outdir=${CONSOLIDATED_OUTDIR:-${RESULTS_ROOT}/${BATCH_PREFIX}_consolidated}
consolidate_job_id=

if [[ $postprocess_only == 1 ]]; then
  if [[ $run_consolidate == 1 ]]; then
    current_step="submitting consolidation-only workflow"
    log "INFO" "Submitting consolidation-only job for existing batches under: $results_root_arg"
    consolidate_qsub_output=$(
      qsub "${top_level_qsub_log_args[@]}" \
        -v "RESULTS_ROOT=${RESULTS_ROOT},BATCH_PREFIX=${BATCH_PREFIX},CONSOLIDATED_OUTDIR=${consolidated_outdir},CONSOLIDATE_SCRIPT=${consolidate_r_script}" \
        "$consolidate_pbs_script"
    )
    consolidate_job_id=${consolidate_qsub_output%%.*}
    log "INFO" "Consolidation job ${consolidate_job_id}: ${consolidated_outdir}"
  else
    if [[ ! -d $consolidated_outdir ]]; then
      fail "POSTPROCESS_ONLY mode with RUN_CONSOLIDATE=0 requires an existing consolidated directory: $consolidated_outdir"
    fi
    log "INFO" "Using existing consolidated directory: $consolidated_outdir"
  fi
else
  current_step="submitting batch workflow"
  log "INFO" "Submitting batch workflow from: $run_agar_dir"
  submit_output=$(
    cd "$run_agar_dir"
    "$submit_script" "$samplesheet_path" "$batch_size"
  )
  printf '%s\n' "$submit_output"

  consolidate_job_id=$(
    printf '%s\n' "$submit_output" |
      awk '/^consolidation job / {gsub(":", "", $3); print $3}'
  )
fi

final_dependency_job=${consolidate_job_id:-}
review_tsv=${map_output%.tsv}_review_required.tsv
review_mlst_file=${review_output_dir}/mlst_review.tsv

if [[ $map_agrf_results == 1 && -z $consolidate_job_id && $postprocess_only != 1 && $run_consolidate == 1 ]]; then
  log "WARN" "No consolidation job was detected, so AGRF mapping was not submitted."
  exit 0
elif [[ $map_agrf_results == 1 ]]; then
  current_step="submitting AGRF mapping job"
  map_qsub_args=("${top_level_qsub_log_args[@]}" -N agrf_map_job)
  if [[ -n $final_dependency_job ]]; then
    map_qsub_args+=(-W "depend=afterok:${final_dependency_job}")
  fi
  map_qsub_args+=(
    -v "AGRF_SHEET=${agrf_sheet_path},CONSOLIDATED_DIR=${consolidated_outdir},MAP_OUTPUT=${map_output},MAP_SCRIPT=${map_r_script}"
    "$map_pbs_script"
  )
  map_qsub_output=$(qsub "${map_qsub_args[@]}")
  map_job_id=${map_qsub_output%%.*}
  log "INFO" "AGRF mapping job ${map_job_id}: ${map_output}"
  final_dependency_job=$map_job_id
elif [[ $run_mlst_review == 1 ]]; then
  if [[ ! -f $map_output || ! -f $review_tsv ]]; then
    fail "RUN_MLST_REVIEW=1 with MAP_AGRF_RESULTS=0 requires existing files: $map_output and $review_tsv"
  fi
fi

if [[ $run_mlst_review == 1 ]]; then
  current_step="submitting MLST review job"
  review_qsub_args=("${top_level_qsub_log_args[@]}" -N mlst_review_job)
  if [[ -n $final_dependency_job ]]; then
    review_qsub_args+=(-W "depend=afterok:${final_dependency_job}")
  fi
  review_qsub_args+=(
    -v "REVIEW_TSV=${review_tsv},RESULTS_ROOT=${RESULTS_ROOT},MAPPED_TSV=${map_output},OUTPUT_DIR=${review_output_dir},RUN_AGAR_ROOT=${run_agar_dir}"
    "$review_mlst_pbs_script"
  )
  review_qsub_output=$(qsub "${review_qsub_args[@]}")
  review_job_id=${review_qsub_output%%.*}
  log "INFO" "MLST review job ${review_job_id}: ${review_tsv}"
  final_dependency_job=$review_job_id

  if [[ $run_post_review_map == 1 ]]; then
    current_step="submitting post-review AGRF mapping job"
    post_review_map_qsub_output=$(
      qsub "${top_level_qsub_log_args[@]}" -N agrf_post_review_map_job \
        -W "depend=afterok:${review_job_id}" \
        -v "AGRF_SHEET=${agrf_sheet_path},CONSOLIDATED_DIR=${consolidated_outdir},MAP_OUTPUT=${post_review_map_output},MAP_SCRIPT=${map_r_script},MLST_FILE=${review_mlst_file}" \
        "$map_pbs_script"
    )
    post_review_map_job_id=${post_review_map_qsub_output%%.*}
    log "INFO" "Post-review AGRF mapping job ${post_review_map_job_id}: ${post_review_map_output}"
    final_dependency_job=$post_review_map_job_id
  fi
elif [[ $run_post_review_map == 1 ]]; then
  if [[ ! -f $review_mlst_file ]]; then
    fail "RUN_POST_REVIEW_MAP=1 without RUN_MLST_REVIEW requires an existing review file: $review_mlst_file"
  fi

  current_step="submitting post-review AGRF mapping job"
  post_review_map_qsub_args=("${top_level_qsub_log_args[@]}" -N agrf_post_review_map_job)
  if [[ -n $final_dependency_job ]]; then
    post_review_map_qsub_args+=(-W "depend=afterok:${final_dependency_job}")
  fi
  post_review_map_qsub_args+=(
    -v "AGRF_SHEET=${agrf_sheet_path},CONSOLIDATED_DIR=${consolidated_outdir},MAP_OUTPUT=${post_review_map_output},MAP_SCRIPT=${map_r_script},MLST_FILE=${review_mlst_file}"
    "$map_pbs_script"
  )
  post_review_map_qsub_output=$(qsub "${post_review_map_qsub_args[@]}")
  post_review_map_job_id=${post_review_map_qsub_output%%.*}
  log "INFO" "Post-review AGRF mapping job ${post_review_map_job_id}: ${post_review_map_output}"
  final_dependency_job=$post_review_map_job_id
fi

if [[ $run_export_results_workbook == 1 ]]; then
  current_step="submitting results workbook export job"
  workbook_qsub_args=("${top_level_qsub_log_args[@]}" -N results_xlsx_job)
  if [[ -n $final_dependency_job ]]; then
    workbook_qsub_args+=(-W "depend=afterok:${final_dependency_job}")
  fi
  workbook_qsub_args+=(
    -v "RESULTS_ROOT=${RESULTS_ROOT},CONSOLIDATED_DIR=${consolidated_outdir},WORKBOOK_OUTPUT=${results_workbook_output},EXPORT_SCRIPT=${export_results_workbook_script},PYTHON_BIN=${export_results_workbook_python_bin}"
    "$export_results_workbook_pbs_script"
  )
  workbook_qsub_output=$(qsub "${workbook_qsub_args[@]}")
  workbook_job_id=${workbook_qsub_output%%.*}
  log "INFO" "Results workbook job ${workbook_job_id}: ${results_workbook_output}"
fi

log "INFO" "Pipeline submission completed successfully."
