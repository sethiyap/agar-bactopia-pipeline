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
  RDS_SFTP_IDENTITY_FILE    Optional SSH private key file for sftp; when set
                            the helper adds `-i <file> -o IdentitiesOnly=yes`
  RDS_SFTP_USE_PASSWORD     If set to 1, prompt for the RDS password before qsub
  RDS_SFTP_PASSWORD_FILE    Optional file containing the SFTP password; when set
                            the helper uses SSH_ASKPASS-driven password auth
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
RDS_SFTP_IDENTITY_FILE=${RDS_SFTP_IDENTITY_FILE:-}
RDS_SFTP_USE_PASSWORD=${RDS_SFTP_USE_PASSWORD:-0}
RDS_SFTP_PASSWORD_FILE=${RDS_SFTP_PASSWORD_FILE:-}
RDS_SFTP_DELETE_PASSWORD_FILE=${RDS_SFTP_DELETE_PASSWORD_FILE:-0}
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

  if ! [[ $RDS_SFTP_USE_PASSWORD =~ ^[01]$ ]]; then
    echo "RDS_SFTP_USE_PASSWORD must be 0 or 1." >&2
    exit 1
  fi

  if [[ -n $RDS_SFTP_IDENTITY_FILE && -n $RDS_SFTP_PASSWORD_FILE ]]; then
    echo "Set only one of RDS_SFTP_IDENTITY_FILE or RDS_SFTP_PASSWORD_FILE." >&2
    exit 1
  fi

  if ! validate_sftp_identity_file "$RDS_SFTP_IDENTITY_FILE"; then
    exit 1
  fi

  if ! validate_sftp_password_file "$RDS_SFTP_PASSWORD_FILE"; then
    exit 1
  fi
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

validate_sftp_identity_file() {
  local identity_file="$1"
  local identity_base=""
  local first_line=""

  [[ -n $identity_file ]] || return 0

  if [[ ! -f $identity_file ]]; then
    echo "RDS_SFTP_IDENTITY_FILE not found: $identity_file" >&2
    return 1
  fi

  identity_base=$(basename "$identity_file")
  case "$identity_base" in
    known_hosts|authorized_keys|config|*.pub)
      echo "RDS_SFTP_IDENTITY_FILE must point to an SSH private key, not: $identity_file" >&2
      echo "Use the actual private key file under \$HOME/.ssh, not known_hosts, authorized_keys, config, or a .pub file." >&2
      return 1
      ;;
  esac

  if IFS= read -r first_line < "$identity_file"; then
    case "$first_line" in
      ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-nistp*\ *|sk-ssh-*\ *|sk-ecdsa-*\ *)
        echo "RDS_SFTP_IDENTITY_FILE looks like a public key, not a private key: $identity_file" >&2
        echo "Use the matching private key file under \$HOME/.ssh instead of the .pub file." >&2
        return 1
        ;;
    esac
  fi
}

validate_sftp_password_file() {
  local password_file="$1"

  [[ -n $password_file ]] || return 0

  if [[ ! -f $password_file ]]; then
    echo "RDS_SFTP_PASSWORD_FILE not found: $password_file" >&2
    return 1
  fi

  if [[ ! -s $password_file ]]; then
    echo "RDS_SFTP_PASSWORD_FILE is empty: $password_file" >&2
    return 1
  fi
}

default_secret_dir() {
  local project_name="${PBS_PROJECT:-${PROJECT:-rg42}}"
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

cleanup_password_file() {
  if [[ $RDS_SFTP_DELETE_PASSWORD_FILE == 1 && -n $RDS_SFTP_PASSWORD_FILE && -f $RDS_SFTP_PASSWORD_FILE ]]; then
    rm -f "$RDS_SFTP_PASSWORD_FILE"
  fi
}

submit_job() {
  local job_output
  local -a qsub_args

  require_settings

  if [[ $RDS_SFTP_USE_PASSWORD == 1 && -z $RDS_SFTP_PASSWORD_FILE ]]; then
    if ! create_password_file_from_prompt; then
      exit 1
    fi
  fi

  mkdir -p "$DEBUG_LOG_DIR"
  if [[ -n $PBS_LOG_DIR ]]; then
    mkdir -p "$PBS_LOG_DIR"
    qsub_args=(-o "$PBS_LOG_DIR" -e "$PBS_LOG_DIR")
  else
    qsub_args=()
  fi

  trap cleanup_password_file EXIT

  export RDS_SRC
  export GADI_DEST
  export RDS_SFTP_USER
  export GADI_LOCAL_NAME
  export RDS_SFTP_HOST
  export RDS_SFTP_IDENTITY_FILE
  export RDS_SFTP_USE_PASSWORD
  export RDS_SFTP_PASSWORD_FILE
  export RDS_SFTP_DELETE_PASSWORD_FILE
  export RDS_SFTP_OPTS
  export RDS_RESUME_DOWNLOAD
  export RDS_SKIP_IF_DEST_EXISTS
  export DEBUG_LOG_DIR
  export PBS_LOG_DIR

  job_output=$(qsub -V "${qsub_args[@]}" "$script_path")
  trap - EXIT
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
  local askpass_script=""

  if [[ -n $RDS_SFTP_OPTS ]]; then
    # shellcheck disable=SC2206
    sftp_opts_array=($RDS_SFTP_OPTS)
  else
    sftp_opts_array=()
  fi

  if [[ -n $RDS_SFTP_PASSWORD_FILE ]]; then
    askpass_script="$tmpdir/ssh_askpass.sh"
    cat > "$askpass_script" <<'EOF'
#!/usr/bin/env bash
cat "$RDS_SFTP_PASSWORD_FILE"
EOF
    chmod 700 "$askpass_script"
    env \
      DISPLAY='ssh-askpass:0' \
      SSH_ASKPASS="$askpass_script" \
      SSH_ASKPASS_REQUIRE=force \
      RDS_SFTP_PASSWORD_FILE="$RDS_SFTP_PASSWORD_FILE" \
      sftp \
      "${sftp_opts_array[@]}" \
      -o PreferredAuthentications=keyboard-interactive,password \
      -o KbdInteractiveAuthentication=yes \
      -o PubkeyAuthentication=no \
      -o NumberOfPasswordPrompts=1 \
      "${RDS_SFTP_USER}@${RDS_SFTP_HOST}" < "$commands_file" > "$output_file" 2> "$error_file"
  else
    if [[ -n $RDS_SFTP_IDENTITY_FILE ]]; then
      sftp_opts_array+=(-o IdentitiesOnly=yes -i "$RDS_SFTP_IDENTITY_FILE")
    fi

    sftp "${sftp_opts_array[@]}" "${RDS_SFTP_USER}@${RDS_SFTP_HOST}" < "$commands_file" > "$output_file" 2> "$error_file"
  fi
}

sftp_error_log_file() {
  printf '%s\n' "$2"
}

show_sftp_auth_hint() {
  cat >&2 <<EOF
SFTP disconnected after too many authentication failures.
If your SSH agent is offering several keys, export RDS_SFTP_IDENTITY_FILE to the
single private key that should be used, then resubmit the helper.
If you prefer password auth, set RDS_SFTP_USE_PASSWORD=1 before running the
helper. Example:
  export RDS_SFTP_IDENTITY_FILE=\$HOME/.ssh/<your_private_key>
EOF
}

show_sftp_password_hint() {
  cat >&2 <<EOF
SFTP password auth is available for this helper.
From a login shell, set:
  export RDS_SFTP_USE_PASSWORD=1
Then rerun ./scripts/copy_RDS_to_GADI.sh ...
EOF
}

show_sftp_password_rejected_hint() {
  cat >&2 <<EOF
The RDS server rejected the interactive password login.
This helper now tries keyboard-interactive first and plain password second.
Check that the RDS username/password are correct. If the same credentials still
fail, this RDS account likely requires SSH key auth instead of password auth.
EOF
}

show_sftp_invalid_identity_hint() {
  cat >&2 <<EOF
RDS_SFTP_IDENTITY_FILE is not a usable SSH private key.
Use the private key itself, not known_hosts, authorized_keys, config, or a .pub
file. Check what you have with:
  ls -la \$HOME/.ssh
Then export the real private key path and resubmit the helper.
EOF
}

show_sftp_invalid_password_hint() {
  cat >&2 <<EOF
RDS_SFTP_PASSWORD_FILE is missing or empty.
If you want password auth, resubmit from a login shell with:
  export RDS_SFTP_USE_PASSWORD=1
  ./scripts/copy_RDS_to_GADI.sh ...
EOF
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
  local path_check_log=""

  printf 'cd "%s"\npwd\nbye\n' "$(sftp_quote "$remote_path")" > "$commands_file"

  if ! run_sftp "$commands_file" "$output_file" "$error_file"; then
    return 1
  fi

  path_check_log="$(sftp_error_log_file "$output_file" "$error_file")"
  if has_sftp_path_error "$path_check_log"; then
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
  local path_check_log=""

  printf 'ls -l "%s"\nbye\n' "$(sftp_quote "$remote_path")" > "$commands_file"

  if ! run_sftp "$commands_file" "$output_file" "$error_file"; then
    return 1
  fi

  path_check_log="$(sftp_error_log_file "$output_file" "$error_file")"
  if has_sftp_path_error "$path_check_log"; then
    return 1
  fi

  remote_listing="$(extract_remote_listing "$output_file")"
  [[ -n $remote_listing ]]
}

run_transfer() {
  local debug_stamp debug_run_log
  local rds_src_trimmed default_local_name local_name local_target
  local remote_type download_commands download_output download_error info_file
  local auth_error_log=""

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
  if [[ -n $RDS_SFTP_PASSWORD_FILE ]]; then
    log "  SFTP auth mode=password file"
  else
    log "  RDS_SFTP_IDENTITY_FILE=${RDS_SFTP_IDENTITY_FILE:-<default ssh selection>}"
  fi
  log "  GADI_LOCAL_NAME=${GADI_LOCAL_NAME:-<source basename>}"
  log "  RDS_RESUME_DOWNLOAD=$RDS_RESUME_DOWNLOAD"
  log "  RDS_SKIP_IF_DEST_EXISTS=$RDS_SKIP_IF_DEST_EXISTS"

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"; cleanup_password_file' EXIT

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
    auth_error_log="$(sftp_error_log_file "$download_output" "$download_error")"
    if [[ -s $auth_error_log ]]; then
      cat "$auth_error_log" >&2
    fi
    if grep -Fqi 'invalid format' "$auth_error_log"; then
      show_sftp_invalid_identity_hint
    elif grep -Fqi 'Too many authentication failures' "$auth_error_log"; then
      show_sftp_auth_hint
    elif grep -Fqi 'Permission denied' "$auth_error_log"; then
      show_sftp_password_rejected_hint
    elif [[ -n $RDS_SFTP_PASSWORD_FILE ]]; then
      show_sftp_invalid_password_hint
    fi
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
