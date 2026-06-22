#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./wrappers/submit.gadi.sh RAW_FASTQ_DIR METADATA_DIR RESULTS_ROOT [BATCH_SIZE]
  ./wrappers/submit.gadi.sh --additional-tools yes RAW_FASTQ_DIR METADATA_DIR RESULTS_ROOT [BATCH_SIZE]
  ./wrappers/submit.gadi.sh --is-agar-project 0 RAW_FASTQ_DIR METADATA_DIR RESULTS_ROOT [BATCH_SIZE]
  ./wrappers/submit.gadi.sh --site-config config/sites/gadi.local.env RAW_FASTQ_DIR METADATA_DIR RESULTS_ROOT [BATCH_SIZE]
  ./wrappers/submit.gadi.sh --mail-user you@example.org [--mail-options ae] RAW_FASTQ_DIR METADATA_DIR RESULTS_ROOT [BATCH_SIZE]

Options:
  --is-agar-project auto|1|0   Override AGAR auto-detection for mixed or non-AGAR inputs
EOF
}

wrapper_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd "$wrapper_dir/.." && pwd)
site_config=${SITE_CONFIG:-$project_root/config/sites/gadi.local.env}
additional_tools_override=
is_agar_project_override=
mail_user_override=
mail_options_override=

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --site-config)
      site_config=$2
      shift 2
      ;;
    --additional-tools)
      additional_tools_override=$2
      shift 2
      ;;
    --is-agar-project)
      is_agar_project_override=$2
      shift 2
      ;;
    --mail-user)
      mail_user_override=$2
      shift 2
      ;;
    --mail-options)
      mail_options_override=$2
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

if [[ $# -lt 3 || $# -gt 4 ]]; then
  usage >&2
  exit 1
fi

if [[ ! -f $site_config ]]; then
  cat >&2 <<EOF
Site config not found: $site_config

Create it with:
  cp $project_root/config/sites/gadi.env.example $project_root/config/sites/gadi.local.env
EOF
  exit 1
fi

export PIPELINE_ROOT=$project_root
export PIPELINE_CONFIG=$site_config
set -a
# shellcheck disable=SC1090
source "$project_root/config/defaults.env"
# shellcheck disable=SC1090
source "$site_config"
set +a

# Keep PBS mail settings per-submission only; do not inherit them from shared site config.
unset PBS_MAIL_USER
unset PBS_MAIL_OPTIONS

case "${additional_tools_override:-}" in
  yes|YES|true|TRUE|1) export RUN_ADDITIONAL_TOOLS=1 ;;
  no|NO|false|FALSE|0) export RUN_ADDITIONAL_TOOLS=0 ;;
  "") ;;
  *)
    echo "--additional-tools must be yes|no|1|0" >&2
    exit 1
    ;;
esac

case "${is_agar_project_override:-}" in
  auto|1|0|true|TRUE|false|FALSE|agar|other) export IS_AGAR_PROJECT=$is_agar_project_override ;;
  "") ;;
  *)
    echo "--is-agar-project must be auto|1|0" >&2
    exit 1
    ;;
esac

if [[ -n ${mail_user_override:-} ]]; then
  export PBS_MAIL_USER=$mail_user_override
fi

if [[ -n ${mail_options_override:-} ]]; then
  export PBS_MAIL_OPTIONS=$mail_options_override
elif [[ -n ${mail_user_override:-} && -z ${PBS_MAIL_OPTIONS:-} ]]; then
  export PBS_MAIL_OPTIONS=ae
fi

export RUN_AGAR_DIR=$project_root
batch_size=${4:-${BATCH_SIZE_DEFAULT:-50}}

exec "$project_root/scripts/submit_agar_full_pipeline.sh" --config "$site_config" \
  "$1" "$2" "$3" "$batch_size"
