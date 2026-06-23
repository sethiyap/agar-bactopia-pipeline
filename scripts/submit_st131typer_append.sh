#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/submit_st131typer_append.sh ASSEMBLIES_DIR [WORKBOOK_OUTPUT]

Environment variables:
  RESULTS_ROOT                 Default: parent directory of ASSEMBLIES_DIR
  ST131_TYPER_SCRIPT           Default: <current_workdir>/ST131Typer.sh
  ST131_TYPER_OUTPUT_DIR       Default: <results_root>/<basename(results_root)>_st131typer
  ST131_TYPER_PBS_SCRIPT       Default: <script_dir>/run_st131typer_from_assemblies.pbs
  EXPORT_RESULTS_WORKBOOK_PBS_SCRIPT Default: <script_dir>/run_export_bactopia_results_workbook.pbs
  EXPORT_RESULTS_WORKBOOK_SCRIPT      Default: <script_dir>/export_bactopia_results_workbook.py
  EXPORT_RESULTS_WORKBOOK_PYTHON_BIN  Default: python3
  PBS_LOG_DIR, PBS_MAIL_OPTIONS, PBS_MAIL_USER  Optional qsub settings

This submits two jobs:
  1. run ST131Typer against the assemblies directory
  2. append the resulting TSV/CSV tables into the workbook
EOF
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 1
fi

assemblies_dir=$1
workbook_output=${2:-${WORKBOOK_OUTPUT:-}}
results_root=${RESULTS_ROOT:-$(dirname "$assemblies_dir")}
st131typer_script=${ST131_TYPER_SCRIPT:-$PWD/ST131Typer.sh}
st131typer_output_dir=${ST131_TYPER_OUTPUT_DIR:-${results_root}/$(basename "$results_root")_st131typer}
st131typer_pbs_script=${ST131_TYPER_PBS_SCRIPT:-$script_dir/run_st131typer_from_assemblies.pbs}
export_results_workbook_pbs_script=${EXPORT_RESULTS_WORKBOOK_PBS_SCRIPT:-$script_dir/run_export_bactopia_results_workbook.pbs}
export_results_workbook_script=${EXPORT_RESULTS_WORKBOOK_SCRIPT:-$script_dir/export_bactopia_results_workbook.py}
export_results_workbook_python_bin=${EXPORT_RESULTS_WORKBOOK_PYTHON_BIN:-python3}
pbs_log_dir=${PBS_LOG_DIR:-}
pbs_mail_options=${PBS_MAIL_OPTIONS:-}
pbs_mail_user=${PBS_MAIL_USER:-}

if [[ ! -d $assemblies_dir ]]; then
  echo "ASSEMBLIES_DIR not found: $assemblies_dir" >&2
  exit 1
fi

if [[ -z $workbook_output ]]; then
  workbook_output=${results_root}/$(basename "$results_root")_results.xlsx
fi

if [[ ! -f $st131typer_script ]]; then
  echo "ST131_TYPER_SCRIPT not found: $st131typer_script" >&2
  exit 1
fi

if [[ ! -f $st131typer_pbs_script ]]; then
  echo "ST131_TYPER_PBS_SCRIPT not found: $st131typer_pbs_script" >&2
  exit 1
fi

if [[ ! -f $export_results_workbook_pbs_script || ! -f $export_results_workbook_script ]]; then
  echo "Workbook export scripts not found under $script_dir" >&2
  exit 1
fi

qsub_log_args=()
if [[ -n $pbs_log_dir ]]; then
  mkdir -p "$pbs_log_dir"
  qsub_log_args=(-o "$pbs_log_dir" -e "$pbs_log_dir")
fi
if [[ -n $pbs_mail_options ]]; then
  qsub_log_args+=(-m "$pbs_mail_options")
fi
if [[ -n $pbs_mail_user ]]; then
  qsub_log_args+=(-M "$pbs_mail_user")
fi

st131typer_job_output=$(
  qsub "${qsub_log_args[@]}" -N st131typer_append_job \
    -v "ASSEMBLIES_DIR=${assemblies_dir},RESULTS_ROOT=${results_root},ST131_TYPER_SCRIPT=${st131typer_script},ST131_TYPER_OUTPUT_DIR=${st131typer_output_dir}" \
    "$st131typer_pbs_script"
)
st131typer_job_id=${st131typer_job_output%%.*}
echo "st131typer job ${st131typer_job_id}: ${st131typer_output_dir}"

export_qsub_output=$(
  qsub "${qsub_log_args[@]}" -N st131typer_append_xlsx_job \
    -W "depend=afterok:${st131typer_job_id}" \
    -v "WORKBOOK_OUTPUT=${workbook_output},EXPORT_SCRIPT=${export_results_workbook_script},PYTHON_BIN=${export_results_workbook_python_bin},ST131_TYPER_DIR=${st131typer_output_dir},EXPORT_APPEND=1" \
    "$export_results_workbook_pbs_script"
)
export_job_id=${export_qsub_output%%.*}
echo "workbook job ${export_job_id}: ${workbook_output}"
