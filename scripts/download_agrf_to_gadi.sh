#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/download_agrf_to_gadi.sh REMOTE_SPEC YEAR BATCH
  ./scripts/download_agrf_to_gadi.sh REMOTE_SPEC YEAR BATCH DEST_NAME

Examples:
  ./scripts/download_agrf_to_gadi.sh \
    user@source.example.org:/path/to/AGRF_CAGRF26050180_AAHJ2FTM5 \
    2025 \
    B07

  ./scripts/download_agrf_to_gadi.sh \
    user@source.example.org:/path/to/AGRF_CAGRF26050180_AAHJ2FTM5 \
    2025 \
    B07 \
    AGRF_CAGRF26050180_AAHJ2FTM5

What it does:
  1. Creates /scratch/<project>/AGAR/raw_data/<YEAR>/<BATCH>/<DEST_NAME>
  2. Uses rsync over ssh to copy the remote delivery into that directory
  3. Writes beneath DEST_ROOT, which defaults to the AGAR raw_data tree

Arguments:
  REMOTE_SPEC  rsync-compatible remote source, usually user@host:/path/to/delivery
  YEAR         Processing year, for example 2025
  BATCH        Batch id, for example B07
  DEST_NAME    Optional target directory name. Default: basename(REMOTE_SPEC)

Environment variables:
  PROJECT      Default: rg42
  DEST_ROOT    Default: /scratch/<PROJECT>/AGAR/raw_data. May be overridden
               to another absolute destination root
  RSYNC_RSH    Optional custom remote shell, for example "ssh -p 2222"
  RSYNC_ARGS   Optional extra rsync args appended to the command
  DRY_RUN      Set to 1 to print the rsync plan without copying
EOF
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
  usage >&2
  exit 1
fi

remote_spec=$1
year=$2
batch=$3
dest_name=${4:-}

PROJECT=${PROJECT:-rg42}
DEST_ROOT=${DEST_ROOT:-/scratch/${PROJECT}/AGAR/raw_data}
RSYNC_RSH=${RSYNC_RSH:-}
RSYNC_ARGS=${RSYNC_ARGS:-}
DRY_RUN=${DRY_RUN:-0}

if ! command -v rsync >/dev/null 2>&1; then
  echo "Required command not found: rsync" >&2
  exit 1
fi

if [[ -z $dest_name ]]; then
  source_path=${remote_spec#*:}
  source_path=${source_path%/}
  dest_name=$(basename "$source_path")
fi

if [[ ! $year =~ ^20[0-9]{2}$ ]]; then
  echo "YEAR must look like 2025: $year" >&2
  exit 1
fi

if [[ ! $batch =~ ^[Bb][0-9]{2}$ ]]; then
  echo "BATCH must look like B07: $batch" >&2
  exit 1
fi

if [[ -z $dest_name || $dest_name == "." || $dest_name == "/" ]]; then
  echo "Could not derive DEST_NAME from REMOTE_SPEC. Pass DEST_NAME explicitly." >&2
  exit 1
fi

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

dest_dir="${DEST_ROOT%/}/${year}/${batch}/${dest_name}"

if [[ $DEST_ROOT != /* ]]; then
  echo "DEST_ROOT must be an absolute path: $DEST_ROOT" >&2
  exit 1
fi

mkdir -p "$dest_dir"

rsync_cmd=(rsync -av --partial --progress)
if [[ -n $RSYNC_RSH ]]; then
  rsync_cmd+=(-e "$RSYNC_RSH")
fi
if [[ -n $RSYNC_ARGS ]]; then
  # shellcheck disable=SC2206
  extra_rsync_args=($RSYNC_ARGS)
  rsync_cmd+=("${extra_rsync_args[@]}")
fi
if [[ $DRY_RUN == 1 ]]; then
  rsync_cmd+=(--dry-run)
fi

remote_with_trailing_slash=${remote_spec%/}/
rsync_cmd+=("$remote_with_trailing_slash" "$dest_dir/")

log "Remote source: $remote_spec"
log "Destination: $dest_dir"
if [[ $DRY_RUN == 1 ]]; then
  log "DRY_RUN=1, no files will be copied"
fi

"${rsync_cmd[@]}"

log "Raw data transfer completed: $dest_dir"
