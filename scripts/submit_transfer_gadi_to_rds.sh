#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
wrapper_path="$script_dir/jobsubmission_transfer_gadi_to_rds.pbs"

usage() {
  cat <<'EOF'
Usage:
  export SRC_PATH=/scratch/rg42/AGAR/intermediates/2025/B07
  export RDS_DEST=/rds/PRJ-AGAR/PRJ-AGAR/intermediates/2025/B07
  export RDS_SFTP_USER=<your_rds_username>

  # Optional password mode:
  export RDS_SFTP_USE_PASSWORD=1

  ./scripts/submit_transfer_gadi_to_rds.sh

Optional environment variables:
  RDS_SFTP_USE_PASSWORD     If set to 1, prompt for the RDS password before qsub
  RDS_SFTP_PASSWORD_FILE    Existing password file to reuse instead of prompting
  PBS_LOG_DIR               Optional directory for PBS stdout/stderr files
EOF
}

SRC_PATH=${SRC_PATH:-}
RDS_DEST=${RDS_DEST:-}
RDS_SFTP_USER=${RDS_SFTP_USER:-}
RDS_SFTP_USE_PASSWORD=${RDS_SFTP_USE_PASSWORD:-0}
RDS_SFTP_PASSWORD_FILE=${RDS_SFTP_PASSWORD_FILE:-}
RDS_SFTP_DELETE_PASSWORD_FILE=${RDS_SFTP_DELETE_PASSWORD_FILE:-0}
PBS_LOG_DIR=${PBS_LOG_DIR:-}

default_secret_dir() {
  local project_name="${PROJECT:-rg42}"
  local scratch_root=""

  if [[ -n ${USER:-} ]]; then
    scratch_root="/scratch/${project_name}/${USER}"
    if [[ -d $scratch_root && -w $scratch_root ]]; then
      printf '%s\n' "$scratch_root/.rds_sftp_secrets"
      return
    fi
  fi

  printf '%s\n' "$HOME/.rds_sftp_secrets"
}

create_password_file_from_prompt() {
  local secret_dir=""
  local password=""
  local password_file=""

  secret_dir="$(default_secret_dir)"
  umask 077
  mkdir -p "$secret_dir"
  password_file="$(mktemp "$secret_dir/rds_sftp_password.XXXXXX")"
  read -r -s -p 'RDS SFTP password: ' password
  printf '\n'

  if [[ -z $password ]]; then
    rm -f "$password_file"
    echo "RDS SFTP password cannot be empty." >&2
    return 1
  fi

  printf '%s\n' "$password" > "$password_file"
  chmod 600 "$password_file"
  RDS_SFTP_PASSWORD_FILE="$password_file"
  RDS_SFTP_DELETE_PASSWORD_FILE=1
}

cleanup_on_submit_failure() {
  if [[ $RDS_SFTP_DELETE_PASSWORD_FILE == 1 && -n $RDS_SFTP_PASSWORD_FILE && -f $RDS_SFTP_PASSWORD_FILE ]]; then
    rm -f "$RDS_SFTP_PASSWORD_FILE"
  fi
}

if [[ ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z $SRC_PATH || -z $RDS_DEST || -z $RDS_SFTP_USER ]]; then
  usage >&2
  exit 1
fi

if ! [[ $RDS_SFTP_USE_PASSWORD =~ ^[01]$ ]]; then
  echo "RDS_SFTP_USE_PASSWORD must be 0 or 1." >&2
  exit 1
fi

if [[ ! -x $wrapper_path ]]; then
  echo "PBS wrapper not found or not executable: $wrapper_path" >&2
  exit 1
fi

if [[ $RDS_SFTP_USE_PASSWORD == 1 && -z $RDS_SFTP_PASSWORD_FILE ]]; then
  create_password_file_from_prompt
fi

trap cleanup_on_submit_failure EXIT

export SRC_PATH
export RDS_DEST
export RDS_SFTP_USER
export RDS_SFTP_USE_PASSWORD
export RDS_SFTP_PASSWORD_FILE
export RDS_SFTP_DELETE_PASSWORD_FILE

if [[ -n $PBS_LOG_DIR ]]; then
  mkdir -p "$PBS_LOG_DIR"
  job_output=$(qsub -V -o "$PBS_LOG_DIR" -e "$PBS_LOG_DIR" "$wrapper_path")
else
  job_output=$(qsub -V "$wrapper_path")
fi

trap - EXIT

printf 'Submitted PBS job %s for Gadi-to-RDS transfer\n' "${job_output%%.*}"
printf 'PBS wrapper: %s\n' "$wrapper_path"
if [[ $RDS_SFTP_USE_PASSWORD == 1 || -n $RDS_SFTP_PASSWORD_FILE ]]; then
  printf 'Auth mode: password file\n'
else
  printf 'Auth mode: SSH key/default\n'
fi
