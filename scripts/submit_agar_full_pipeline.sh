#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/submit_agar_full_pipeline.sh RAW_FASTQ_DIR METADATA_DIR RESULTS_ROOT [BATCH_SIZE]
  ./scripts/submit_agar_full_pipeline.sh --config scripts/gadi_pipeline.env RAW_FASTQ_DIR METADATA_DIR RESULTS_ROOT [BATCH_SIZE]
  ./scripts/submit_agar_full_pipeline.sh --dry-run RAW_FASTQ_DIR METADATA_DIR RESULTS_ROOT [BATCH_SIZE]

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
  6. When enabled, collect flattened assemblies and run ST131Typer after the
     main post-processing chain finishes

Inputs:
  RAW_FASTQ_DIR  Raw FASTQ directory, for example /scratch/rg42/AGAR/rawdata/2025/B05
  METADATA_DIR   Metadata directory containing *_samplesheet.txt and/or samplesheet.fofn
                 The mapper prefers 'Sample name' and 'Comments' headers.
                 If they are missing, the first metadata column is treated as
                 'Sample name' and the second as 'Comments'.
                 Other metadata columns are ignored by downstream metadata mapping.
  RESULTS_ROOT   Intermediate results directory, for example /scratch/rg42/AGAR/intermediates/2025/B05
  BATCH_SIZE     Default: 50. The split keeps each PBS batch job manageable on
                 Gadi and makes reruns smaller if a single batch fails.

Environment variables:
  PIPELINE_CONFIG        Optional shell env file to source before resolving defaults
  DRY_RUN               Optional validation mode. Use --dry-run or DRY_RUN=1 to
                        check inputs, config, and dependencies without
                        submitting jobs
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
  AGAR_SAMPLE_REGEX      Default in AGAR mode: ^[0-9]{2}GNB-[0-9]+R?$
                         Built-in FOFN creation keeps only sample prefixes
                         matching this regex and skips other FASTQs
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
  RUN_COLLECT_ASSEMBLIES Default: 1. When enabled, the top-level AGAR launcher
                         now waits until the core workflow, consolidation,
                         mapping, and MLST review chain finish before collecting
                         flattened assemblies
  RUN_ST131_TYPER        Default: 0. Set to 1 to run ST131Typer after the
                         post-processing chain finishes and the assemblies
                         folder is ready
  ST131_APPEND_AFTER_WORKBOOK Default: 0. Set to 1 to export the main workbook
                         first, then run ST131Typer, then append the
                         `st131typer_summary` sheet into that existing workbook
  USE_EXISTING_ST131_TYPER Default: 0. Set to 1 to reuse an existing
                         ST131_TYPER_OUTPUT_DIR during workbook export
  RUN_EXPORT_RESULTS_WORKBOOK Default: 1. Set to 0 to skip final Excel workbook export
  CHECK_INODE_QUOTA      Default: 1. Set to 0 to skip the inode preflight check
  INODE_FS_WARN_FREE_PCT Default: 15. Warn if df reports less free inode percent
  INODE_FS_MIN_FREE_COUNT Default: 50000. Fail early if df reports fewer free inodes
  INODE_FS_MIN_FREE_PCT  Default: 5. Fail early if df reports less free inode percent
  PROJECT_INODE_WARN_USE_PCT Default: 85. Warn if lquota/nci_account reports
                         scratch inode usage at or above this percent
  PROJECT_INODE_MAX_USE_PCT Default: 95. Fail early if lquota/nci_account reports
                         scratch inode usage at or above this percent
  MAP_OUTPUT             Default: <RESULTS_ROOT>/<metadata-prefix>_samplesheet_with_results.tsv
  REVIEW_OUTPUT_DIR      Default: <RESULTS_ROOT>/mlst_review_standalone
  POST_REVIEW_MAP_OUTPUT Default: <RESULTS_ROOT>/<metadata-prefix>_samplesheet_with_results_post_review.tsv
  ST131_TYPER_DIR        Optional directory containing ST131Typer.sh
  ST131_TYPER_INPUT_DIR  Optional existing assemblies directory to use instead
                         of collecting a fresh flattened assemblies folder
  ST131_TYPER_OUTPUT_DIR Default: <RESULTS_ROOT>/<basename(RESULTS_ROOT)>_st131typer
  RESULTS_WORKBOOK_OUTPUT Default: <RESULTS_ROOT>/<basename(RESULTS_ROOT)>_results.xlsx
  LOG_DIR                Default: dirname(LOG_FILE) or <RESULTS_ROOT>
  LOG_FILE               Default: <RESULTS_ROOT>/submit_agar_full_pipeline_<timestamp>.log
  PBS_LOG_DIR            Optional directory for scheduler stdout/stderr files
  PBS_MAIL_OPTIONS       Optional PBS-style mail flags, for example ae or abe
  PBS_MAIL_USER          Optional email address for scheduler notifications
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
# shellcheck disable=SC1091
source "$script_dir/lib_scheduler.sh"

pipeline_config=${PIPELINE_CONFIG:-}
dry_run=${DRY_RUN:-0}

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
    --dry-run)
      dry_run=1
      shift
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
run_collect_assemblies=${RUN_COLLECT_ASSEMBLIES:-1}
run_st131typer=${RUN_ST131_TYPER:-0}
st131_append_after_workbook=${ST131_APPEND_AFTER_WORKBOOK:-0}
use_existing_st131typer=${USE_EXISTING_ST131_TYPER:-0}
run_export_results_workbook=${RUN_EXPORT_RESULTS_WORKBOOK:-1}
map_output=${MAP_OUTPUT:-}
review_output_dir=${REVIEW_OUTPUT_DIR:-$results_root_arg/mlst_review_standalone}
post_review_map_output=${POST_REVIEW_MAP_OUTPUT:-}
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
split_script=${SPLIT_SAMPLESHEET_SCRIPT:-$script_dir/split_bactopia_samplesheet.sh}
normalize_script=${NORMALIZE_SCRIPT:-$script_dir/normalize_agar_fastq_sample_names.sh}
validate_script=${VALIDATE_FOFN_SCRIPT:-$script_dir/validate_bactopia_fofn.sh}
consolidate_pbs_script=${CONSOLIDATE_PBS_SCRIPT:-$script_dir/run_consolidate_batches.pbs}
consolidate_r_script=${CONSOLIDATE_SCRIPT:-$script_dir/consolidate_bactopia_batches.R}
map_pbs_script=${MAP_PBS_SCRIPT:-$script_dir/run_map_agrf_samplesheet_results.pbs}
map_r_script=${MAP_R_SCRIPT:-$script_dir/map_agrf_samplesheet_results.R}
review_mlst_pbs_script=${REVIEW_MLST_PBS_SCRIPT:-$script_dir/run_review_mlst_from_tsv.pbs}
fetch_assemblies_pbs_script=${FETCH_ASSEMBLIES_PBS_SCRIPT:-$script_dir/run_fetch_batch_assemblies.pbs}
st131typer_pbs_script=${ST131_TYPER_PBS_SCRIPT:-$script_dir/run_st131typer_from_assemblies.pbs}
st131typer_dir=${ST131_TYPER_DIR:-}
if [[ -n $st131typer_dir ]]; then
  st131typer_script=${ST131_TYPER_SCRIPT:-$st131typer_dir/ST131Typer.sh}
else
  st131typer_script=${ST131_TYPER_SCRIPT:-$run_agar_dir/ST131Typer.sh}
fi
st131typer_input_dir=${ST131_TYPER_INPUT_DIR:-}
assemblies_outdir=${ASSEMBLIES_OUTDIR:-$results_root_arg/$(basename "$results_root_arg")_assemblies}
st131typer_output_dir=${ST131_TYPER_OUTPUT_DIR:-$results_root_arg/$(basename "$results_root_arg")_st131typer}
export_results_workbook_pbs_script=${EXPORT_RESULTS_WORKBOOK_PBS_SCRIPT:-$script_dir/run_export_bactopia_results_workbook.pbs}
export_results_workbook_python_bin=${EXPORT_RESULTS_WORKBOOK_PYTHON_BIN:-python3}
export_results_workbook_script=${EXPORT_RESULTS_WORKBOOK_SCRIPT:-$script_dir/export_bactopia_results_workbook.py}
is_agar_project=${IS_AGAR_PROJECT:-auto}
default_agar_sample_regex='^[0-9]{2}GNB-[0-9]+R?$'
agar_sample_regex=${AGAR_SAMPLE_REGEX:-$default_agar_sample_regex}
check_inode_quota=${CHECK_INODE_QUOTA:-1}
inode_fs_warn_free_pct=${INODE_FS_WARN_FREE_PCT:-15}
inode_fs_min_free_count=${INODE_FS_MIN_FREE_COUNT:-50000}
inode_fs_min_free_pct=${INODE_FS_MIN_FREE_PCT:-5}
project_inode_warn_use_pct=${PROJECT_INODE_WARN_USE_PCT:-85}
project_inode_max_use_pct=${PROJECT_INODE_MAX_USE_PCT:-95}
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

metadata_output_stem() {
  local metadata_path=$1
  local metadata_name prefix

  metadata_name=$(basename "$metadata_path")
  prefix=${metadata_name%_samplesheet.txt}
  if [[ $prefix == "$metadata_name" ]]; then
    prefix=${metadata_name%.*}
  fi
  if [[ -z $prefix || $prefix == "$metadata_name" ]]; then
    prefix="metadata"
  fi

  printf '%s_samplesheet\n' "$prefix"
}

find_existing_parent() {
  local path=$1

  while [[ ! -e $path && $path != "/" ]]; do
    path=$(dirname "$path")
  done

  printf '%s\n' "$path"
}

extract_scratch_project() {
  local path=$1

  if [[ $path =~ ^/scratch/([^/]+)/ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi
}

dry_run_failures=0
dry_run_warnings=0

dry_run_pass() {
  log "INFO" "DRY RUN PASS: $1"
}

dry_run_warn() {
  dry_run_warnings=$((dry_run_warnings + 1))
  log "WARN" "DRY RUN WARN: $1"
}

dry_run_fail() {
  dry_run_failures=$((dry_run_failures + 1))
  log "ERROR" "DRY RUN FAIL: $1"
}

dry_run_check_file() {
  local label=$1
  local path=$2

  if [[ -f $path ]]; then
    dry_run_pass "$label found: $path"
  else
    dry_run_fail "$label not found: $path"
  fi
}

dry_run_check_dir() {
  local label=$1
  local path=$2

  if [[ -d $path ]]; then
    dry_run_pass "$label found: $path"
  else
    dry_run_fail "$label not found: $path"
  fi
}

dry_run_check_path() {
  local label=$1
  local path=$2

  if [[ -e $path ]]; then
    dry_run_pass "$label found: $path"
  else
    dry_run_fail "$label not found: $path"
  fi
}

dry_run_check_command() {
  local command_name=$1
  local label=${2:-$1}

  if command -v "$command_name" >/dev/null 2>&1; then
    dry_run_pass "$label available: $(command -v "$command_name")"
  else
    dry_run_fail "$label is not available on PATH"
  fi
}

dry_run_check_parent_writable() {
  local label=$1
  local path=$2
  local parent

  parent=$(find_existing_parent "$path")
  if [[ -z $parent || ! -e $parent ]]; then
    dry_run_fail "No existing parent path found for $label: $path"
    return
  fi

  if [[ -w $parent ]]; then
    dry_run_pass "$label parent is writable: $parent"
  else
    dry_run_fail "$label parent is not writable: $parent"
  fi
}

dry_run_check_python_module() {
  local python_bin=$1
  local module_name=$2
  local label=${3:-$module_name}

  if ! command -v "$python_bin" >/dev/null 2>&1; then
    dry_run_fail "Python interpreter not found for $label check: $python_bin"
    return
  fi

  if "$python_bin" -c "import ${module_name}" >/dev/null 2>&1; then
    dry_run_pass "$label import succeeded in $python_bin"
  else
    dry_run_fail "$label import failed in $python_bin"
  fi
}

run_dry_run_validation() {
  local run_tools=${RUN_TOOLS:-1}
  local run_kleborate=${RUN_KLEBORATE:-1}
  local run_fimtyper=${RUN_FIMTYPER:-0}
  local default_tools_string=${DEFAULT_TOOLS_STRING:-abritamr amrfinderplus bracken checkm mlst plasmidfinder}
  local additional_tools_string=${ADDITIONAL_TOOLS_STRING:-defensefinder ectyper ismapper mashdist mobsuite mykrobe phispy shigapass shigatyper shigeifinder}
  local tools_string=${TOOLS_STRING:-}
  local tmp_root=""
  local tmp_samplesheet=""
  local tmp_batch_dir=""
  local active_samplesheet=""
  local batch_count=0

  if [[ -z $tools_string ]]; then
    tools_string=$default_tools_string
    if [[ ${RUN_ADDITIONAL_TOOLS:-0} != 0 ]]; then
      tools_string="${tools_string} ${additional_tools_string}"
    fi
  fi

  # shellcheck disable=SC2206
  local tools_list=($tools_string)

  log "INFO" "DRY_RUN=1. Validating configuration and dependencies without submitting jobs."
  log "INFO" "Scheduler backend: $scheduler_backend"

  scheduler_require_backend || fail "Unsupported scheduler backend for dry run: $scheduler_backend"

  case "$scheduler_backend" in
    pbs) dry_run_check_command qsub "PBS qsub" ;;
    slurm) dry_run_check_command sbatch "Slurm sbatch" ;;
  esac

  if type module >/dev/null 2>&1; then
    dry_run_pass "module command is available in the current shell"
  else
    dry_run_warn "module command is not available in the current shell. Job-time module loads are not being checked from this dry run."
  fi

  dry_run_check_dir "RUN_AGAR_DIR" "$run_agar_dir"
  dry_run_check_file "submit_bactopia_batch_pipeline.sh" "$submit_script"
  dry_run_check_file "split_bactopia_samplesheet.sh" "$split_script"
  dry_run_check_file "validate_bactopia_fofn.sh" "$validate_script"
  dry_run_check_file "run_consolidate_batches.pbs/slurm wrapper" "$(scheduler_resolve_script "$consolidate_pbs_script")"
  dry_run_check_file "consolidate_bactopia_batches.R" "$consolidate_r_script"
  dry_run_check_file "run_map_agrf_samplesheet_results.pbs/slurm wrapper" "$(scheduler_resolve_script "$map_pbs_script")"
  dry_run_check_file "map_agrf_samplesheet_results.R" "$map_r_script"

  if [[ $postprocess_only != 1 ]]; then
    dry_run_check_path "BACTOPIA_PIPELINE" "$BACTOPIA_PIPELINE"
    dry_run_check_path "DATASETS_CACHE" "$DATASETS_CACHE"
    dry_run_check_file "NEXTFLOW_CONFIG" "$NEXTFLOW_CONFIG"
    dry_run_check_parent_writable "SING_CACHE" "$SING_CACHE"
  fi

  if [[ $run_tools != 0 ]] && ( tools_string_contains "kraken2" "${tools_list[@]}" || tools_string_contains "bracken" "${tools_list[@]}" ); then
    if [[ -n ${KRAKEN2_DB:-} ]]; then
      dry_run_check_path "KRAKEN2_DB" "$KRAKEN2_DB"
    else
      dry_run_fail "KRAKEN2_DB is required because TOOLS_STRING includes kraken2 or bracken"
    fi
  fi

  if [[ $run_tools != 0 ]] && tools_string_contains "mykrobe" "${tools_list[@]}"; then
    if [[ -n ${MYKROBE_SPECIES:-} ]]; then
      dry_run_pass "MYKROBE_SPECIES is set: ${MYKROBE_SPECIES}"
    else
      dry_run_fail "MYKROBE_SPECIES is required because TOOLS_STRING includes mykrobe"
    fi
  fi

  if [[ $run_tools != 0 ]] && tools_string_contains "defensefinder" "${tools_list[@]}" && [[ -n ${DEFENSEFINDER_DB:-} ]]; then
    dry_run_check_path "DEFENSEFINDER_DB" "$DEFENSEFINDER_DB"
  fi

  if [[ $run_kleborate != 0 ]]; then
    dry_run_check_file "KLEBORATE_COMPAT_SCRIPT" "$KLEBORATE_COMPAT_SCRIPT"
  fi

  if [[ $run_fimtyper != 0 ]]; then
    dry_run_check_file "FIMTYPER_PIPELINE" "$FIMTYPER_PIPELINE"
    dry_run_check_file "FIMTYPER_CONFIG" "$FIMTYPER_CONFIG"
    if [[ -n ${MERGE_FIMTYPER_SCRIPT:-} ]]; then
      dry_run_check_file "MERGE_FIMTYPER_SCRIPT" "$MERGE_FIMTYPER_SCRIPT"
    fi
  fi

  if [[ $run_mlst_review == 1 ]]; then
    dry_run_check_file "run_review_mlst_from_tsv.pbs/slurm wrapper" "$(scheduler_resolve_script "$review_mlst_pbs_script")"
    dry_run_check_file "run_review_mlst_from_tsv.sh" "$script_dir/run_review_mlst_from_tsv.sh"
    dry_run_check_dir "MINIFORGE_ROOT" "$MINIFORGE_ROOT"
    dry_run_check_dir "MLST_ENV" "$MLST_ENV"
    if [[ -x $MLST_ENV/bin/mlst ]]; then
      dry_run_pass "mlst executable found in MLST_ENV: $MLST_ENV/bin/mlst"
    else
      dry_run_fail "mlst executable not found in MLST_ENV: $MLST_ENV/bin/mlst"
    fi
    if [[ -x $MLST_ENV/bin/seqkit ]]; then
      dry_run_pass "seqkit executable found in MLST_ENV: $MLST_ENV/bin/seqkit"
    else
      dry_run_fail "seqkit executable not found in MLST_ENV: $MLST_ENV/bin/seqkit"
    fi
  fi

  if [[ $run_export_results_workbook == 1 ]]; then
    dry_run_check_file "run_export_bactopia_results_workbook.pbs/slurm wrapper" "$(scheduler_resolve_script "$export_results_workbook_pbs_script")"
    dry_run_check_file "export_bactopia_results_workbook.py" "$export_results_workbook_script"
    dry_run_check_command "$export_results_workbook_python_bin" "Workbook export Python interpreter"
    dry_run_check_python_module "$export_results_workbook_python_bin" "openpyxl" "openpyxl"
  fi

  if [[ $run_collect_assemblies == 1 || $run_st131typer == 1 ]]; then
    dry_run_check_file "run_fetch_batch_assemblies.pbs/slurm wrapper" "$(scheduler_resolve_script "$fetch_assemblies_pbs_script")"
  fi

  if [[ $run_st131typer == 1 ]]; then
    dry_run_check_file "run_st131typer_from_assemblies.pbs/slurm wrapper" "$(scheduler_resolve_script "$st131typer_pbs_script")"
    dry_run_check_file "ST131Typer.sh" "$st131typer_script"
  fi

  if [[ $postprocess_only != 1 && $skip_normalize != 1 && $is_agar_project == 1 ]]; then
    if bash "$normalize_script" --dry-run "$raw_fastq_dir" >/dev/null 2>&1; then
      dry_run_pass "AGAR filename normalization dry run completed successfully"
    else
      dry_run_fail "AGAR filename normalization dry run failed for: $raw_fastq_dir"
    fi
  fi

  if [[ $postprocess_only == 1 ]]; then
    dry_run_pass "POSTPROCESS_ONLY=1, so FOFN creation and batch submission checks were skipped"
  else
    if [[ -f $samplesheet_path ]]; then
      active_samplesheet=$samplesheet_path
      if bash "$validate_script" "$active_samplesheet" >/dev/null 2>&1; then
        dry_run_pass "Existing samplesheet/FOFN validated: $active_samplesheet"
      else
        dry_run_fail "Existing samplesheet/FOFN failed validation: $active_samplesheet"
      fi
    elif [[ -n $create_fofn_command ]]; then
      dry_run_warn "CREATE_FOFN_COMMAND is set. Dry run did not execute this custom command automatically."
    elif [[ -f $create_fofn_script ]]; then
      tmp_root=$(mktemp -d)
      tmp_samplesheet=$tmp_root/samplesheet.fofn
      if [[ $is_agar_project == 1 ]]; then
        if INCLUDE_SAMPLE_REGEX="$agar_sample_regex" bash "$create_fofn_script" "$raw_fastq_dir" "$tmp_samplesheet" >/dev/null 2>&1; then
          dry_run_pass "FOFN creation dry run succeeded with AGAR sample filtering"
          active_samplesheet=$tmp_samplesheet
        else
          dry_run_fail "FOFN creation dry run failed using CREATE_FOFN_SCRIPT"
        fi
      else
        if bash "$create_fofn_script" "$raw_fastq_dir" "$tmp_samplesheet" >/dev/null 2>&1; then
          dry_run_pass "FOFN creation dry run succeeded"
          active_samplesheet=$tmp_samplesheet
        else
          dry_run_fail "FOFN creation dry run failed using CREATE_FOFN_SCRIPT"
        fi
      fi

      if [[ -n $active_samplesheet && -f $active_samplesheet ]]; then
        if bash "$validate_script" "$active_samplesheet" >/dev/null 2>&1; then
          dry_run_pass "Generated dry-run FOFN validated successfully"
        else
          dry_run_fail "Generated dry-run FOFN failed validation"
        fi
      fi
    else
      dry_run_fail "No existing samplesheet/FOFN was found and no FOFN creation helper is available"
    fi

    if [[ -n $active_samplesheet && -f $active_samplesheet && -f $split_script ]]; then
      [[ -z $tmp_root ]] && tmp_root=$(mktemp -d)
      tmp_batch_dir=$tmp_root/batches
      if bash "$split_script" "$active_samplesheet" "$batch_size" "$tmp_batch_dir" "$batch_prefix" >/dev/null 2>&1; then
        batch_count=$(find "$tmp_batch_dir" -maxdepth 1 -type f -name "${batch_prefix}_*.fofn" | wc -l | tr -d ' ')
        dry_run_pass "Batch split dry run succeeded and would create ${batch_count} batch file(s)"
      else
        dry_run_fail "Batch split dry run failed for samplesheet: $active_samplesheet"
      fi
    fi
  fi

  if [[ -n $tmp_root && -d $tmp_root ]]; then
    rm -rf "$tmp_root"
  fi

  if (( dry_run_failures > 0 )); then
    fail "Dry run failed with ${dry_run_failures} issue(s) and ${dry_run_warnings} warning(s). Review the log output above."
  fi

  log "INFO" "Dry run completed successfully with ${dry_run_warnings} warning(s). No jobs were submitted."
  exit 0
}

check_filesystem_inode_headroom() {
  local target_path=$1
  local existing_path df_line df_ifree df_use_pct free_pct
  local _df_filesystem _df_inodes _df_iused _df_mount

  existing_path=$(find_existing_parent "$target_path")
  if [[ ! -e $existing_path ]]; then
    log "WARN" "Skipping filesystem inode preflight because no existing parent was found for: $target_path"
    return 0
  fi

  df_line=$(df -Pi "$existing_path" 2>/dev/null | awk 'NR == 2 {print}')
  if [[ -z $df_line ]]; then
    log "WARN" "Skipping filesystem inode preflight because df -Pi returned no output for: $existing_path"
    return 0
  fi

  read -r _df_filesystem _df_inodes _df_iused df_ifree df_use_pct _df_mount <<<"$df_line"
  if [[ -z ${_df_mount:-} ]]; then
    log "WARN" "Skipping filesystem inode preflight because df -Pi output could not be parsed for: $existing_path"
    return 0
  fi

  df_use_pct=${df_use_pct%\%}
  if ! [[ $df_ifree =~ ^[0-9]+$ && $df_use_pct =~ ^[0-9]+$ ]]; then
    log "WARN" "Skipping filesystem inode preflight because inode values were not numeric for: $existing_path"
    return 0
  fi

  free_pct=$((100 - df_use_pct))
  log "INFO" "Filesystem inode preflight for $existing_path: ${df_ifree} free inodes (${free_pct}% free)"

  if (( free_pct < inode_fs_warn_free_pct )); then
    log "WARN" "Low filesystem inode headroom under $existing_path: ${df_ifree} free inodes (${free_pct}% free). Consider freeing scratch space before continuing."
  fi

  if (( df_ifree < inode_fs_min_free_count || free_pct < inode_fs_min_free_pct )); then
    fail "Not enough filesystem inode headroom under $existing_path: ${df_ifree} free inodes (${free_pct}% free). Adjust RESULTS_ROOT, clean scratch, or override INODE_FS_MIN_FREE_COUNT / INODE_FS_MIN_FREE_PCT."
  fi
}

parse_scaled_count() {
  local value=$1
  local unit=${2:-}

  unit=${unit//\*/}
  awk -v value="$value" -v unit="$unit" '
    BEGIN {
      mult = 1
      if (unit == "K") {
        mult = 1000
      } else if (unit == "M") {
        mult = 1000000
      } else if (unit == "G") {
        mult = 1000000000
      } else if (unit == "T") {
        mult = 1000000000000
      }
      printf "%.0f\n", value * mult
    }
  '
}

check_quota_text_report() {
  local source=$1
  local report=$2
  local project=$3
  local relevant max_pct pct scratch_row iusage iquota iuse_pct
  local nci_scratch_row nci_iused_value nci_iused_unit nci_ialloc_value nci_ialloc_unit

  if grep -Eqi "Project[[:space:]]+${project}[[:space:]]+is over storage allocation on gadi-scratch1" <<<"$report"; then
    fail "Scratch quota preflight failed for project ${project}: ${source} reports the project is over storage allocation on gadi-scratch1. Clean scratch inodes before rerunning."
  fi

  scratch_row=$(printf '%s\n' "$report" | awk -v proj="$project" '$1 == proj && $2 == "scratch" {print; exit}')
  if [[ -n $scratch_row ]]; then
    if grep -Eqi 'Over[[:space:]]+inode[[:space:]]+limit' <<<"$scratch_row"; then
      fail "Scratch quota preflight failed for project ${project}: ${source} reports the scratch allocation is over inode limit."
    fi

    read -r iusage iquota < <(printf '%s\n' "$scratch_row" | awk '{print $9, $10}')
    if [[ $iusage =~ ^[0-9]+$ && $iquota =~ ^[0-9]+$ && $iquota -gt 0 ]]; then
      iuse_pct=$(( (iusage * 100) / iquota ))
      log "INFO" "${source} inode preflight for project ${project}: scratch inode usage ${iusage}/${iquota} (${iuse_pct}%)"
      if (( iuse_pct >= project_inode_warn_use_pct )); then
        log "WARN" "Scratch inode usage for project ${project} is ${iuse_pct}% according to ${source} (${iusage}/${iquota}). Consider cleaning scratch before continuing."
      fi
      if (( iuse_pct >= project_inode_max_use_pct )); then
        fail "Scratch inode usage for project ${project} is ${iuse_pct}% according to ${source} (${iusage}/${iquota}). Clean scratch or raise PROJECT_INODE_MAX_USE_PCT if this threshold is intentionally higher."
      fi
      return 0
    fi
  fi

  nci_scratch_row=$(printf '%s\n' "$report" | awk '$1 ~ /^scratch[0-9]*$/ {print; exit}')
  if [[ -n $nci_scratch_row ]]; then
    if grep -Eqi 'Over[[:space:]]+inode[[:space:]]+quota|Over[[:space:]]+inode[[:space:]]+limit' <<<"$nci_scratch_row"; then
      fail "Scratch quota preflight failed for project ${project}: ${source} reports the scratch allocation is over inode quota."
    fi

    read -r nci_iused_value nci_iused_unit nci_ialloc_value nci_ialloc_unit < <(printf '%s\n' "$nci_scratch_row" | awk '{print $4, $5, $8, $9}')
    if [[ -n ${nci_iused_value:-} && -n ${nci_iused_unit:-} && -n ${nci_ialloc_value:-} && -n ${nci_ialloc_unit:-} ]]; then
      iusage=$(parse_scaled_count "$nci_iused_value" "$nci_iused_unit")
      iquota=$(parse_scaled_count "$nci_ialloc_value" "$nci_ialloc_unit")
      if [[ $iusage =~ ^[0-9]+$ && $iquota =~ ^[0-9]+$ && $iquota -gt 0 ]]; then
        iuse_pct=$(( (iusage * 100) / iquota ))
        log "INFO" "${source} inode preflight for project ${project}: scratch inode usage ${iusage}/${iquota} (${iuse_pct}%)"
        if (( iuse_pct >= project_inode_warn_use_pct )); then
          log "WARN" "Scratch inode usage for project ${project} is ${iuse_pct}% according to ${source} (${iusage}/${iquota}). Consider cleaning scratch before continuing."
        fi
        if (( iuse_pct >= project_inode_max_use_pct )); then
          fail "Scratch inode usage for project ${project} is ${iuse_pct}% according to ${source} (${iusage}/${iquota}). Clean scratch or raise PROJECT_INODE_MAX_USE_PCT if this threshold is intentionally higher."
        fi
        return 0
      fi
    fi
  fi

  relevant=$(printf '%s\n' "$report" | grep -Ei "scratch.*inode|inode.*scratch|/scratch/${project}|${project}[[:space:]]+scratch" || true)
  [[ -z $relevant ]] && return 1

  max_pct=""
  while IFS= read -r pct; do
    pct=${pct%\%}
    [[ -z $pct ]] && continue
    if [[ -z $max_pct || $pct -gt $max_pct ]]; then
      max_pct=$pct
    fi
  done < <(printf '%s\n' "$relevant" | grep -Eo '[0-9]{1,3}%' || true)

  if [[ -n $max_pct ]]; then
    log "INFO" "${source} inode preflight for project ${project}: parsed scratch inode usage up to ${max_pct}%"
    if (( max_pct >= project_inode_warn_use_pct )); then
      log "WARN" "Scratch inode usage for project ${project} is ${max_pct}% according to ${source}. Consider cleaning scratch before continuing."
    fi
    if (( max_pct >= project_inode_max_use_pct )); then
      fail "Scratch inode usage for project ${project} is ${max_pct}% according to ${source}. Clean scratch or raise PROJECT_INODE_MAX_USE_PCT if this threshold is intentionally higher."
    fi
    return 0
  fi

  return 1
}

check_project_inode_quota() {
  local target_path=$1
  local project=$2
  local quota_output quota_status

  if [[ $check_inode_quota != 1 ]]; then
    log "INFO" "Skipping project inode quota preflight because CHECK_INODE_QUOTA=0"
    return 0
  fi

  if [[ -z $project ]]; then
    log "INFO" "Skipping project inode quota preflight because RESULTS_ROOT is not under /scratch: $target_path"
    return 0
  fi

  if command -v lquota >/dev/null 2>&1; then
    quota_status=0
    quota_output=$(lquota 2>&1) || quota_status=$?
    if check_quota_text_report "lquota" "$quota_output" "$project"; then
      return 0
    fi
    if (( quota_status != 0 )); then
      log "WARN" "lquota exited with status ${quota_status}. Falling back to nci_account if available."
    else
      log "WARN" "Could not parse scratch inode usage for project ${project} from lquota output."
    fi
  fi

  if command -v nci_account >/dev/null 2>&1; then
    quota_status=0
    quota_output=$(nci_account -P "$project" 2>&1) || quota_status=$?
    if check_quota_text_report "nci_account -P ${project}" "$quota_output" "$project"; then
      return 0
    fi
    if (( quota_status != 0 )); then
      log "WARN" "nci_account -P ${project} exited with status ${quota_status}. Continuing without a parsed project inode quota result."
    else
      log "WARN" "Could not parse scratch inode usage for project ${project} from nci_account -P ${project} output."
    fi
    return 0
  fi

  log "WARN" "Neither lquota nor nci_account is available, so scratch project inode quota could not be checked."
}

run_inode_preflight() {
  local scratch_project=""

  case "${check_inode_quota}" in
    0)
      log "INFO" "Skipping inode preflight because CHECK_INODE_QUOTA=0"
      return 0
      ;;
    1) ;;
    *)
      fail "CHECK_INODE_QUOTA must be 0 or 1: $check_inode_quota"
      ;;
  esac

  if ! [[ $inode_fs_min_free_count =~ ^[0-9]+$ ]]; then
    fail "INODE_FS_MIN_FREE_COUNT must be a non-negative integer: $inode_fs_min_free_count"
  fi
  if ! [[ $inode_fs_warn_free_pct =~ ^[0-9]+$ ]] || (( inode_fs_warn_free_pct > 100 )); then
    fail "INODE_FS_WARN_FREE_PCT must be an integer between 0 and 100: $inode_fs_warn_free_pct"
  fi
  if ! [[ $inode_fs_min_free_pct =~ ^[0-9]+$ ]] || (( inode_fs_min_free_pct > 100 )); then
    fail "INODE_FS_MIN_FREE_PCT must be an integer between 0 and 100: $inode_fs_min_free_pct"
  fi
  if ! [[ $project_inode_warn_use_pct =~ ^[0-9]+$ ]] || (( project_inode_warn_use_pct < 0 || project_inode_warn_use_pct > 100 )); then
    fail "PROJECT_INODE_WARN_USE_PCT must be an integer between 0 and 100: $project_inode_warn_use_pct"
  fi
  if ! [[ $project_inode_max_use_pct =~ ^[0-9]+$ ]] || (( project_inode_max_use_pct < 1 || project_inode_max_use_pct > 100 )); then
    fail "PROJECT_INODE_MAX_USE_PCT must be an integer between 1 and 100: $project_inode_max_use_pct"
  fi

  log "INFO" "Running inode preflight for RESULTS_ROOT: $results_root_arg"
  check_filesystem_inode_headroom "$results_root_arg"
  scratch_project=$(extract_scratch_project "$results_root_arg" || true)
  check_project_inode_quota "$results_root_arg" "$scratch_project"
}

if [[ -z $agrf_sheet_path ]]; then
  if ! agrf_sheet_path=$(find_metadata_sheet "$metadata_dir"); then
    agrf_sheet_path=$metadata_dir/metadata_samplesheet.txt
  fi
fi

metadata_output_prefix=$(metadata_output_stem "$agrf_sheet_path")
if [[ -z $map_output ]]; then
  map_output=$results_root_arg/${metadata_output_prefix}_with_results.tsv
fi
if [[ -z $post_review_map_output ]]; then
  post_review_map_output=$results_root_arg/${metadata_output_prefix}_with_results_post_review.tsv
fi

log "INFO" "Pipeline log file: $log_file"
log "INFO" "RAW_FASTQ_DIR=$raw_fastq_dir"
log "INFO" "METADATA_DIR=$metadata_dir"
log "INFO" "RESULTS_ROOT=$results_root_arg"
log "INFO" "SAMPLESHEET_PATH=$samplesheet_path"
log "INFO" "METADATA_SHEET_PATH=$agrf_sheet_path"
log "INFO" "RESULTS_PREFIX=$metadata_output_prefix"

if [[ ! -d $raw_fastq_dir ]]; then
  fail "RAW_FASTQ_DIR not found: $raw_fastq_dir"
fi

if [[ ! -d $metadata_dir ]]; then
  fail "METADATA_DIR not found: $metadata_dir"
fi

if ! [[ $batch_size =~ ^[1-9][0-9]*$ ]]; then
  fail "BATCH_SIZE must be a positive integer: $batch_size"
fi

for path in "$submit_script" "$split_script" "$normalize_script" "$validate_script" "$consolidate_pbs_script" "$consolidate_r_script" "$map_pbs_script" "$map_r_script" "$review_mlst_pbs_script"; do
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

if [[ $run_collect_assemblies != 0 && $run_collect_assemblies != 1 ]]; then
  fail "RUN_COLLECT_ASSEMBLIES must be 0 or 1: $run_collect_assemblies"
fi

if [[ $dry_run != 0 && $dry_run != 1 ]]; then
  fail "DRY_RUN must be 0 or 1: $dry_run"
fi

if [[ $st131_append_after_workbook != 0 && $st131_append_after_workbook != 1 ]]; then
  fail "ST131_APPEND_AFTER_WORKBOOK must be 0 or 1: $st131_append_after_workbook"
fi

if [[ $st131_append_after_workbook == 1 && $run_export_results_workbook != 1 ]]; then
  fail "ST131_APPEND_AFTER_WORKBOOK=1 requires RUN_EXPORT_RESULTS_WORKBOOK=1."
fi

if [[ $st131_append_after_workbook == 1 && $run_st131typer != 1 ]]; then
  fail "ST131_APPEND_AFTER_WORKBOOK=1 requires RUN_ST131_TYPER=1."
fi

if [[ $st131_append_after_workbook == 1 && $use_existing_st131typer == 1 ]]; then
  fail "ST131_APPEND_AFTER_WORKBOOK=1 cannot be combined with USE_EXISTING_ST131_TYPER=1."
fi

if [[ $run_st131typer == 1 ]]; then
  if [[ ! -f $fetch_assemblies_pbs_script ]]; then
    fail "Required assemblies collection script not found: $fetch_assemblies_pbs_script"
  fi
  if [[ ! -f $st131typer_pbs_script ]]; then
    fail "Required ST131Typer PBS wrapper not found: $st131typer_pbs_script"
  fi
  if [[ ! -f $st131typer_script ]]; then
    fail "Required ST131Typer script not found: $st131typer_script. Define ST131_TYPER_DIR=/path/to/ST131Typer or ST131_TYPER_SCRIPT=/path/to/ST131Typer.sh"
  fi
  log "INFO" "Found ST131Typer.sh at: $st131typer_script"
elif [[ $run_collect_assemblies == 1 ]]; then
  if [[ ! -f $fetch_assemblies_pbs_script ]]; then
    fail "Required assemblies collection script not found: $fetch_assemblies_pbs_script"
  fi
fi

if [[ $use_existing_st131typer == 1 && $run_st131typer != 1 ]]; then
  if [[ ! -d $st131typer_output_dir ]]; then
    fail "USE_EXISTING_ST131_TYPER=1 requires an existing ST131_TYPER_OUTPUT_DIR: $st131typer_output_dir"
  fi
  log "INFO" "Using existing ST131Typer output directory for workbook export: $st131typer_output_dir"
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

current_step="checking inode headroom"
run_inode_preflight

if [[ $dry_run == 1 ]]; then
  current_step="running dry-run validation"
  run_dry_run_validation
fi

if [[ $postprocess_only == 1 ]]; then
  log "INFO" "Skipping FASTQ sample name normalization in POSTPROCESS_ONLY mode"
elif [[ $skip_normalize != 1 && $is_agar_project == 1 ]]; then
  current_step="normalizing FASTQ sample names"
  log "INFO" "Normalizing FASTQ sample names in: $raw_fastq_dir"
  bash "$normalize_script" "$raw_fastq_dir"
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
  if [[ $is_agar_project == 1 ]]; then
    log "INFO" "AGAR mode with CREATE_FOFN_COMMAND. Custom FOFN creation is responsible for filtering mixed sample folders."
  fi
  log "INFO" "Creating Bactopia samplesheet/FOFN: $samplesheet_path"
  eval "$fofn_cmd"
elif [[ ! -f $samplesheet_path && -f $create_fofn_script ]]; then
  current_step="creating Bactopia FOFN with CREATE_FOFN_SCRIPT"
  mkdir -p "$(dirname "$samplesheet_path")"
  log "INFO" "Creating Bactopia samplesheet/FOFN with: $create_fofn_script"
  if [[ $is_agar_project == 1 ]]; then
    log "INFO" "AGAR mode FOFN filter: keeping sample prefixes matching AGAR_SAMPLE_REGEX=$agar_sample_regex"
    INCLUDE_SAMPLE_REGEX="$agar_sample_regex" bash "$create_fofn_script" "$raw_fastq_dir" "$samplesheet_path"
  else
    bash "$create_fofn_script" "$raw_fastq_dir" "$samplesheet_path"
  fi
fi

if [[ $postprocess_only != 1 && ! -f $samplesheet_path ]]; then
  fail "Samplesheet/FOFN not found: $samplesheet_path. Either create it first or provide CREATE_FOFN_COMMAND / CREATE_FOFN_SCRIPT."
fi

if [[ $postprocess_only != 1 && $skip_validate != 1 ]]; then
  current_step="validating FOFN"
  log "INFO" "Validating FOFN: $samplesheet_path"
  bash "$validate_script" "$samplesheet_path"
fi

current_step="preparing batch submission"
mkdir -p "$batch_dir"

export RESULTS_ROOT=${RESULTS_ROOT:-$results_root_arg}
export BATCH_DIR="$batch_dir"
export BATCH_PREFIX="$batch_prefix"
export PBS_LOG_DIR=${PBS_LOG_DIR:-}
export PBS_MAIL_OPTIONS=${PBS_MAIL_OPTIONS:-}
export PBS_MAIL_USER=${PBS_MAIL_USER:-}
export RUN_COLLECT_ASSEMBLIES=0
export RUN_ST131_TYPER=0
export ST131_TYPER_PBS_SCRIPT="$st131typer_pbs_script"
export ST131_TYPER_SCRIPT="$st131typer_script"
export ST131_TYPER_DIR=${st131typer_dir:-}
export ASSEMBLIES_OUTDIR="$assemblies_outdir"
export ST131_TYPER_OUTPUT_DIR="$st131typer_output_dir"
if [[ -n $st131typer_input_dir ]]; then
  export ST131_TYPER_INPUT_DIR="$st131typer_input_dir"
fi

consolidated_outdir=${CONSOLIDATED_OUTDIR:-${RESULTS_ROOT}/${BATCH_PREFIX}_consolidated}
consolidate_job_id=
st131typer_job_id=
assemblies_job_id=
workbook_job_id=
st131_append_workbook_job_id=

if [[ $postprocess_only == 1 ]]; then
  if [[ $run_consolidate == 1 ]]; then
    current_step="submitting consolidation-only workflow"
    log "INFO" "Submitting consolidation-only job for existing batches under: $results_root_arg"
    consolidate_job_id=$(scheduler_submit \
      "" \
      "" \
      "RESULTS_ROOT=${RESULTS_ROOT},BATCH_PREFIX=${BATCH_PREFIX},CONSOLIDATED_OUTDIR=${consolidated_outdir},CONSOLIDATE_SCRIPT=${consolidate_r_script}" \
      "$consolidate_pbs_script" \
      "${PBS_LOG_DIR:-}" \
      "${PBS_MAIL_OPTIONS:-}" \
      "${PBS_MAIL_USER:-}")
    log "INFO" "Consolidation job ${consolidate_job_id}: ${consolidated_outdir}"
  else
    if [[ ! -d $consolidated_outdir ]]; then
      fail "POSTPROCESS_ONLY mode with RUN_CONSOLIDATE=0 requires an existing consolidated directory: $consolidated_outdir"
    fi
    log "INFO" "Using existing consolidated directory: $consolidated_outdir"
  fi
else
  current_step="submitting batch workflow"
  log "INFO" "Submitting batch workflow from launch directory: $(pwd)"
  submit_output=$("$submit_script" "$samplesheet_path" "$batch_size")
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
  map_job_id=$(scheduler_submit \
    "agrf_map_job" \
    "$final_dependency_job" \
    "AGRF_SHEET=${agrf_sheet_path},CONSOLIDATED_DIR=${consolidated_outdir},MAP_OUTPUT=${map_output},MAP_SCRIPT=${map_r_script}" \
    "$map_pbs_script" \
    "${PBS_LOG_DIR:-}" \
    "${PBS_MAIL_OPTIONS:-}" \
    "${PBS_MAIL_USER:-}")
  log "INFO" "AGRF mapping job ${map_job_id}: ${map_output}"
  final_dependency_job=$map_job_id
elif [[ $run_mlst_review == 1 ]]; then
  if [[ ! -f $map_output || ! -f $review_tsv ]]; then
    fail "RUN_MLST_REVIEW=1 with MAP_AGRF_RESULTS=0 requires existing files: $map_output and $review_tsv"
  fi
fi

if [[ $run_mlst_review == 1 ]]; then
  current_step="submitting MLST review job"
  review_job_id=$(scheduler_submit \
    "mlst_review_job" \
    "$final_dependency_job" \
    "REVIEW_TSV=${review_tsv},RESULTS_ROOT=${RESULTS_ROOT},MAPPED_TSV=${map_output},OUTPUT_DIR=${review_output_dir},RUN_AGAR_ROOT=${run_agar_dir},MINIFORGE_ROOT=${MINIFORGE_ROOT:-},MLST_ENV=${MLST_ENV:-}" \
    "$review_mlst_pbs_script" \
    "${PBS_LOG_DIR:-}" \
    "${PBS_MAIL_OPTIONS:-}" \
    "${PBS_MAIL_USER:-}")
  log "INFO" "MLST review job ${review_job_id}: ${review_tsv}"
  final_dependency_job=$review_job_id

  if [[ $run_post_review_map == 1 ]]; then
    current_step="submitting post-review AGRF mapping job"
    post_review_map_job_id=$(scheduler_submit \
      "agrf_post_review_map_job" \
      "$review_job_id" \
      "AGRF_SHEET=${agrf_sheet_path},CONSOLIDATED_DIR=${consolidated_outdir},MAP_OUTPUT=${post_review_map_output},MAP_SCRIPT=${map_r_script},MLST_FILE=${review_mlst_file}" \
      "$map_pbs_script" \
      "${PBS_LOG_DIR:-}" \
      "${PBS_MAIL_OPTIONS:-}" \
      "${PBS_MAIL_USER:-}")
    log "INFO" "Post-review AGRF mapping job ${post_review_map_job_id}: ${post_review_map_output}"
    final_dependency_job=$post_review_map_job_id
  fi
elif [[ $run_post_review_map == 1 ]]; then
  if [[ ! -f $review_mlst_file ]]; then
    fail "RUN_POST_REVIEW_MAP=1 without RUN_MLST_REVIEW requires an existing review file: $review_mlst_file"
  fi

  current_step="submitting post-review AGRF mapping job"
  post_review_map_job_id=$(scheduler_submit \
    "agrf_post_review_map_job" \
    "$final_dependency_job" \
    "AGRF_SHEET=${agrf_sheet_path},CONSOLIDATED_DIR=${consolidated_outdir},MAP_OUTPUT=${post_review_map_output},MAP_SCRIPT=${map_r_script},MLST_FILE=${review_mlst_file}" \
    "$map_pbs_script" \
    "${PBS_LOG_DIR:-}" \
    "${PBS_MAIL_OPTIONS:-}" \
    "${PBS_MAIL_USER:-}")
  log "INFO" "Post-review AGRF mapping job ${post_review_map_job_id}: ${post_review_map_output}"
  final_dependency_job=$post_review_map_job_id
fi

if [[ $run_collect_assemblies == 1 && $st131_append_after_workbook != 1 ]]; then
  current_step="submitting flattened assemblies collection job"
  assemblies_job_id=$(scheduler_submit \
    "fetch_assemblies_job" \
    "$final_dependency_job" \
    "INPUT_PATH=${RESULTS_ROOT},OUTPUT_DIR=${assemblies_outdir}" \
    "$fetch_assemblies_pbs_script" \
    "${PBS_LOG_DIR:-}" \
    "${PBS_MAIL_OPTIONS:-}" \
    "${PBS_MAIL_USER:-}")
  log "INFO" "Assemblies job ${assemblies_job_id}: ${assemblies_outdir}"
fi

if [[ $run_st131typer == 1 && $st131_append_after_workbook != 1 ]]; then
  current_step="submitting ST131Typer job"
  st131_input_dir=${st131typer_input_dir:-$assemblies_outdir}
  if [[ -z $assemblies_job_id && -z $st131typer_input_dir ]]; then
    fail "RUN_ST131_TYPER=1 requires RUN_COLLECT_ASSEMBLIES=1 or ST131_TYPER_INPUT_DIR=/path/to/existing_assemblies"
  fi

  st131_dependency_job=${assemblies_job_id:-$final_dependency_job}
  st131typer_job_id=$(scheduler_submit \
    "st131typer_job" \
    "$st131_dependency_job" \
    "ASSEMBLIES_DIR=${st131_input_dir},RESULTS_ROOT=${RESULTS_ROOT},ST131_TYPER_SCRIPT=${st131typer_script},ST131_TYPER_OUTPUT_DIR=${st131typer_output_dir}" \
    "$st131typer_pbs_script" \
    "${PBS_LOG_DIR:-}" \
    "${PBS_MAIL_OPTIONS:-}" \
    "${PBS_MAIL_USER:-}")
  log "INFO" "ST131Typer job ${st131typer_job_id}: ${st131typer_output_dir}"
fi

if [[ $run_export_results_workbook == 1 ]]; then
  current_step="submitting results workbook export job"
  workbook_dependency_job=$final_dependency_job
  workbook_st131_env=
  if [[ -n $st131typer_job_id && $st131_append_after_workbook != 1 ]]; then
    if [[ -n $workbook_dependency_job ]]; then
      workbook_dependency_job="${workbook_dependency_job}:${st131typer_job_id}"
    else
      workbook_dependency_job=$st131typer_job_id
    fi
  fi
  if [[ $st131_append_after_workbook != 1 && ( $run_st131typer == 1 || $use_existing_st131typer == 1 ) ]]; then
    workbook_st131_env=",ST131_TYPER_DIR=${st131typer_output_dir}"
  fi
  workbook_job_id=$(scheduler_submit \
    "results_xlsx_job" \
    "$workbook_dependency_job" \
    "RESULTS_ROOT=${RESULTS_ROOT},CONSOLIDATED_DIR=${consolidated_outdir},WORKBOOK_OUTPUT=${results_workbook_output},EXPORT_SCRIPT=${export_results_workbook_script},PYTHON_BIN=${export_results_workbook_python_bin}${workbook_st131_env}" \
    "$export_results_workbook_pbs_script" \
    "${PBS_LOG_DIR:-}" \
    "${PBS_MAIL_OPTIONS:-}" \
    "${PBS_MAIL_USER:-}")
  log "INFO" "Results workbook job ${workbook_job_id}: ${results_workbook_output}"
fi

if [[ $st131_append_after_workbook == 1 ]]; then
  st131_input_dir=${st131typer_input_dir:-$assemblies_outdir}

  if [[ $run_collect_assemblies == 1 ]]; then
    current_step="submitting delayed flattened assemblies collection job"
    assemblies_dependency_job=${workbook_job_id:-$final_dependency_job}
    assemblies_job_id=$(scheduler_submit \
      "fetch_assemblies_job" \
      "$assemblies_dependency_job" \
      "INPUT_PATH=${RESULTS_ROOT},OUTPUT_DIR=${assemblies_outdir}" \
      "$fetch_assemblies_pbs_script" \
      "${PBS_LOG_DIR:-}" \
      "${PBS_MAIL_OPTIONS:-}" \
      "${PBS_MAIL_USER:-}")
    log "INFO" "Delayed assemblies job ${assemblies_job_id}: ${assemblies_outdir}"
  elif [[ -z $st131typer_input_dir ]]; then
    fail "ST131_APPEND_AFTER_WORKBOOK=1 requires RUN_COLLECT_ASSEMBLIES=1 or ST131_TYPER_INPUT_DIR=/path/to/existing_assemblies"
  fi

  current_step="submitting delayed ST131Typer job"
  st131_dependency_job=${assemblies_job_id:-${workbook_job_id:-$final_dependency_job}}
  st131typer_job_id=$(scheduler_submit \
    "st131typer_job" \
    "$st131_dependency_job" \
    "ASSEMBLIES_DIR=${st131_input_dir},RESULTS_ROOT=${RESULTS_ROOT},ST131_TYPER_SCRIPT=${st131typer_script},ST131_TYPER_OUTPUT_DIR=${st131typer_output_dir}" \
    "$st131typer_pbs_script" \
    "${PBS_LOG_DIR:-}" \
    "${PBS_MAIL_OPTIONS:-}" \
    "${PBS_MAIL_USER:-}")
  log "INFO" "Delayed ST131Typer job ${st131typer_job_id}: ${st131typer_output_dir}"

  current_step="submitting ST131 workbook append job"
  st131_append_workbook_job_id=$(scheduler_submit \
    "results_xlsx_st131_append_job" \
    "$st131typer_job_id" \
    "WORKBOOK_OUTPUT=${results_workbook_output},EXPORT_SCRIPT=${export_results_workbook_script},PYTHON_BIN=${export_results_workbook_python_bin},ST131_TYPER_DIR=${st131typer_output_dir},EXPORT_APPEND=1" \
    "$export_results_workbook_pbs_script" \
    "${PBS_LOG_DIR:-}" \
    "${PBS_MAIL_OPTIONS:-}" \
    "${PBS_MAIL_USER:-}")
  log "INFO" "ST131 workbook append job ${st131_append_workbook_job_id}: ${results_workbook_output}"
fi

log "INFO" "Pipeline submission completed successfully."
