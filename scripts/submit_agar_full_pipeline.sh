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
  5. Submit AGRF result mapping after consolidation completes

Inputs:
  RAW_FASTQ_DIR  Raw FASTQ directory, for example /scratch/rg42/AGAR/rawdata/2025/B05
  METADATA_DIR   Metadata directory containing AGRF_samplesheet.txt and/or samplesheet.fofn
  RESULTS_ROOT   Intermediate results directory, for example /scratch/rg42/AGAR/intermediates/2025/B05
  BATCH_SIZE     Default: 50

Environment variables:
  PIPELINE_CONFIG        Optional shell env file to source before resolving defaults
  RUN_AGAR_DIR           Default: directory above this script
  SAMPLESHEET_PATH       Default: <METADATA_DIR>/samplesheet.fofn
  AGRF_SHEET_PATH        Default: <METADATA_DIR>/AGRF_samplesheet.txt, fallback: <METADATA_DIR>/agar_samplesheet.txt
  BATCH_PREFIX           Default: agar_batch
  BATCH_DIR              Default: <METADATA_DIR>/batches
  CREATE_FOFN_SCRIPT     Default: <script_dir>/2_create_fofn_bactopia.sh
  CREATE_FOFN_COMMAND    Optional shell command template to create the FOFN
                         Supported placeholders: {RAWDATA_DIR} {METADATA_DIR} {SAMPLESHEET_OUT}
  SKIP_NORMALIZE         Set to 1 to skip FASTQ name normalization
  SKIP_VALIDATE          Set to 1 to skip FOFN validation
  MAP_AGRF_RESULTS       Default: 1. Set to 0 to skip post-consolidation AGRF mapping
  RUN_MLST_REVIEW        Default: 1. Set to 0 to skip the standalone MLST review follow-up
  RUN_POST_REVIEW_MAP    Default: 1 when RUN_MLST_REVIEW=1. Set to 0 to skip final AGRF remapping with reviewed MLST calls
  MAP_OUTPUT             Default: <RESULTS_ROOT>/AGRF_samplesheet_with_results.tsv
  REVIEW_OUTPUT_DIR      Default: <RESULTS_ROOT>/mlst_review_standalone
  POST_REVIEW_MAP_OUTPUT Default: <RESULTS_ROOT>/AGRF_samplesheet_with_results_post_review.tsv
  LOG_FILE               Default: <RESULTS_ROOT>/submit_agar_full_pipeline_<timestamp>.log

All environment variables used by submit_bactopia_batch_pipeline.sh are also honored,
for example RESULTS_ROOT, NEXTFLOW_CONFIG, DATASETS_CACHE, RUN_TOOLS, RUN_KLEBORATE,
RUN_ADDITIONAL_TOOLS, TOOLS_STRING, RUN_FIMTYPER, FIMTYPER_PIPELINE,
FIMTYPER_CONFIG, RUN_COLLECT_ASSEMBLIES, ASSEMBLIES_OUTDIR, BATCH_SKIP,
BATCH_LIMIT, BATCH_CHAIN.
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
batch_prefix=${BATCH_PREFIX:-agar_batch}
batch_dir=${BATCH_DIR:-$metadata_dir/batches}
create_fofn_command=${CREATE_FOFN_COMMAND:-}
create_fofn_script=${CREATE_FOFN_SCRIPT:-$script_dir/2_create_fofn_bactopia.sh}
skip_normalize=${SKIP_NORMALIZE:-0}
skip_validate=${SKIP_VALIDATE:-0}
map_agrf_results=${MAP_AGRF_RESULTS:-1}
run_mlst_review=${RUN_MLST_REVIEW:-1}
run_post_review_map=${RUN_POST_REVIEW_MAP:-1}
map_output=${MAP_OUTPUT:-$results_root_arg/AGRF_samplesheet_with_results.tsv}
review_output_dir=${REVIEW_OUTPUT_DIR:-$results_root_arg/mlst_review_standalone}
post_review_map_output=${POST_REVIEW_MAP_OUTPUT:-$results_root_arg/AGRF_samplesheet_with_results_post_review.tsv}
log_file=${LOG_FILE:-$results_root_arg/submit_agar_full_pipeline_$(date '+%Y%m%d_%H%M%S').log}

submit_script=${SUBMIT_PIPELINE_SCRIPT:-$script_dir/submit_bactopia_batch_pipeline.sh}
normalize_script=${NORMALIZE_SCRIPT:-$script_dir/normalize_agar_fastq_sample_names.sh}
validate_script=${VALIDATE_FOFN_SCRIPT:-$script_dir/validate_bactopia_fofn.sh}
map_pbs_script=${MAP_PBS_SCRIPT:-$script_dir/run_map_agrf_samplesheet_results.pbs}
map_r_script=${MAP_R_SCRIPT:-$script_dir/map_agrf_samplesheet_results.R}
review_mlst_pbs_script=${REVIEW_MLST_PBS_SCRIPT:-$script_dir/run_review_mlst_from_tsv.pbs}
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

if [[ -z $agrf_sheet_path ]]; then
  if [[ -f $metadata_dir/AGRF_samplesheet.txt ]]; then
    agrf_sheet_path=$metadata_dir/AGRF_samplesheet.txt
  elif [[ -f $metadata_dir/agar_samplesheet.txt ]]; then
    agrf_sheet_path=$metadata_dir/agar_samplesheet.txt
  else
    agrf_sheet_path=$metadata_dir/AGRF_samplesheet.txt
  fi
fi

log "INFO" "Pipeline log file: $log_file"
log "INFO" "RAW_FASTQ_DIR=$raw_fastq_dir"
log "INFO" "METADATA_DIR=$metadata_dir"
log "INFO" "RESULTS_ROOT=$results_root_arg"
log "INFO" "SAMPLESHEET_PATH=$samplesheet_path"
log "INFO" "AGRF_SHEET_PATH=$agrf_sheet_path"

if [[ ! -d $raw_fastq_dir ]]; then
  fail "RAW_FASTQ_DIR not found: $raw_fastq_dir"
fi

if [[ ! -d $metadata_dir ]]; then
  fail "METADATA_DIR not found: $metadata_dir"
fi

if ! [[ $batch_size =~ ^[1-9][0-9]*$ ]]; then
  fail "BATCH_SIZE must be a positive integer: $batch_size"
fi

for path in "$submit_script" "$normalize_script" "$validate_script" "$map_pbs_script" "$map_r_script" "$review_mlst_pbs_script"; do
  if [[ ! -f $path ]]; then
    fail "Required script not found: $path"
  fi
done

current_step="checking raw FASTQ inputs"
fastq_count=$(find "$raw_fastq_dir" -maxdepth 1 -type f \( -name "*.fastq.gz" -o -name "*.fq.gz" \) | wc -l | tr -d ' ')
if [[ $fastq_count -eq 0 ]]; then
  fail "No FASTQ files were found in RAW_FASTQ_DIR: $raw_fastq_dir"
fi
log "INFO" "Detected $fastq_count FASTQ files in raw data directory"

current_step="checking metadata inputs"
if [[ ! -f $agrf_sheet_path ]]; then
  fail "AGRF samplesheet not found in metadata directory. Expected $metadata_dir/AGRF_samplesheet.txt or $metadata_dir/agar_samplesheet.txt"
fi
log "INFO" "Detected AGRF samplesheet: $agrf_sheet_path"

if [[ $skip_normalize != 1 ]]; then
  current_step="normalizing FASTQ sample names"
  log "INFO" "Normalizing FASTQ sample names in: $raw_fastq_dir"
  "$normalize_script" "$raw_fastq_dir"
fi

if [[ -n $create_fofn_command ]]; then
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

if [[ ! -f $samplesheet_path ]]; then
  fail "Samplesheet/FOFN not found: $samplesheet_path. Either create it first or provide CREATE_FOFN_COMMAND / CREATE_FOFN_SCRIPT."
fi

if [[ $skip_validate != 1 ]]; then
  current_step="validating FOFN"
  log "INFO" "Validating FOFN: $samplesheet_path"
  "$validate_script" "$samplesheet_path"
fi

current_step="preparing batch submission"
mkdir -p "$batch_dir"

export RESULTS_ROOT=${RESULTS_ROOT:-$results_root_arg}
export BATCH_DIR="$batch_dir"
export BATCH_PREFIX="$batch_prefix"

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

if [[ $map_agrf_results != 1 ]]; then
  log "INFO" "AGRF mapping disabled. Pipeline submission completed."
  exit 0
fi

if [[ -z $consolidate_job_id ]]; then
  log "WARN" "No consolidation job was detected, so AGRF mapping was not submitted."
  exit 0
fi

consolidated_outdir=${CONSOLIDATED_OUTDIR:-${RESULTS_ROOT}/${BATCH_PREFIX}_consolidated}
current_step="submitting AGRF mapping job"
map_qsub_output=$(
  qsub -N agrf_map_job \
    -W "depend=afterok:${consolidate_job_id}" \
    -v "AGRF_SHEET=${agrf_sheet_path},CONSOLIDATED_DIR=${consolidated_outdir},MAP_OUTPUT=${map_output},MAP_SCRIPT=${map_r_script}" \
    "$map_pbs_script"
)
map_job_id=${map_qsub_output%%.*}
log "INFO" "AGRF mapping job ${map_job_id}: ${map_output}"

if [[ $run_mlst_review == 1 ]]; then
  current_step="submitting MLST review job"
  review_tsv=${map_output%.tsv}_review_required.tsv
  review_qsub_output=$(
    qsub -N mlst_review_job \
      -W "depend=afterok:${map_job_id}" \
      -v "REVIEW_TSV=${review_tsv},RESULTS_ROOT=${RESULTS_ROOT},MAPPED_TSV=${map_output},OUTPUT_DIR=${review_output_dir},RUN_AGAR_ROOT=${run_agar_dir}" \
      "$review_mlst_pbs_script"
  )
  review_job_id=${review_qsub_output%%.*}
  log "INFO" "MLST review job ${review_job_id}: ${review_tsv}"

  if [[ $run_post_review_map == 1 ]]; then
    current_step="submitting post-review AGRF mapping job"
    review_mlst_file=${review_output_dir}/mlst_review.tsv
    post_review_map_qsub_output=$(
      qsub -N agrf_post_review_map_job \
        -W "depend=afterok:${review_job_id}" \
        -v "AGRF_SHEET=${agrf_sheet_path},CONSOLIDATED_DIR=${consolidated_outdir},MAP_OUTPUT=${post_review_map_output},MAP_SCRIPT=${map_r_script},MLST_FILE=${review_mlst_file}" \
        "$map_pbs_script"
    )
    post_review_map_job_id=${post_review_map_qsub_output%%.*}
    log "INFO" "Post-review AGRF mapping job ${post_review_map_job_id}: ${post_review_map_output}"
  fi
fi

log "INFO" "Pipeline submission completed successfully."
