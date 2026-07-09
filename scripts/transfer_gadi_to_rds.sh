#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/transfer_gadi_to_rds.sh

  ./scripts/transfer_gadi_to_rds.sh \
    '/scratch/rg42/ps1744/source_parent' \
    '/rds/PRJ-AGAR/PRJ-AGAR/intermediates/2025/B05'

Optional environment variables:
  RDS_DEST             Overrides the interactive RDS destination prompt
  RDS_SFTP_HOST        Default: research-data-ext.sydney.edu.au
  RDS_SFTP_USER        Required RDS username for sftp login
  RDS_SFTP_OPTS        Extra options passed to sftp, for example: -v
  RDS_SFTP_CHUNK_SIZE  Number of files per SFTP session, default: 100
  RDS_UPLOAD_MANIFEST  Persistent uploaded-files manifest path
  RDS_UPLOAD_MANIFEST_DIR Directory for the persistent uploaded-files manifest
                         Default: /scratch/<project>/<user>/.rds_transfer_manifests
  RDS_IGNORE_MANIFEST  If set to 1, queue all eligible local files and ignore the manifest
  RDS_PRIORITIZE_UPLOADS If set to 0, keep discovery order and skip expensive per-file ranking
  RDS_INCLUDE_DIRS     Comma-separated source-relative directories to keep
  RDS_EXCLUDE_DIRS     Comma-separated source-relative directories to skip
  RDS_EXCLUDE_FILES    Comma-separated file glob patterns to skip
  RDS_EXCLUDE_PATHS    Comma-separated source-relative path glob patterns to skip
  RDS_COPY_SINCE       Copy only files newer than this timestamp
EOF
}

if [[ $# -gt 2 ]]; then
  usage >&2
  exit 1
fi

src_path=${1:-}
dest=${2:-${RDS_DEST:-}}
host=${RDS_SFTP_HOST:-research-data-ext.sydney.edu.au}
user=${RDS_SFTP_USER:-}
sftp_opts=${RDS_SFTP_OPTS:-}
chunk_size=${RDS_SFTP_CHUNK_SIZE:-100}
manifest_path=${RDS_UPLOAD_MANIFEST:-}
ignore_manifest=${RDS_IGNORE_MANIFEST:-0}
prioritize_uploads=${RDS_PRIORITIZE_UPLOADS:-1}
include_dirs_raw=${RDS_INCLUDE_DIRS:-}
exclude_dirs_raw=${RDS_EXCLUDE_DIRS:-}
exclude_files_raw=${RDS_EXCLUDE_FILES:-.nextflow.log,.nextflow.log.*}
exclude_paths_raw=${RDS_EXCLUDE_PATHS:-}
copy_since_raw=${RDS_COPY_SINCE:-}

if [[ -z $src_path ]]; then
  read -r -p 'Gadi source file or folder: ' src_path
fi

if [[ -z $dest ]]; then
  read -r -p 'RDS destination folder: ' dest
fi

if [[ -z $user ]]; then
  if [[ -t 0 ]]; then
    read -r -p 'RDS SFTP username: ' user
  else
    echo "RDS_SFTP_USER is required." >&2
    exit 1
  fi
fi

if [[ -z $copy_since_raw && -t 0 ]]; then
  read -r -p 'Copy only files newer than timestamp (YYYY-MM-DD [HH:MM:SS], leave blank for all): ' copy_since_raw
fi

if [[ -z $src_path || -z $dest || -z $user ]]; then
  echo "Gadi source path, RDS destination folder, and RDS_SFTP_USER are required." >&2
  exit 1
fi

if [[ ! -e $src_path ]]; then
  echo "Source path not found: $src_path" >&2
  exit 1
fi

if ! [[ $chunk_size =~ ^[0-9]+$ ]] || [[ $chunk_size -lt 1 ]]; then
  echo "RDS_SFTP_CHUNK_SIZE must be a positive integer." >&2
  exit 1
fi

if ! [[ $prioritize_uploads =~ ^[01]$ ]]; then
  echo "RDS_PRIORITIZE_UPLOADS must be 0 or 1." >&2
  exit 1
fi

for cmd in find sftp basename dirname sort awk sed comm wc mktemp cp mv tr touch grep cut mkdir; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
done

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

default_manifest_dir() {
  local scratch_root=""
  local project_name="${PBS_PROJECT:-${PROJECT:-rg42}}"

  if [[ -n ${RDS_UPLOAD_MANIFEST_DIR:-} ]]; then
    printf '%s\n' "$RDS_UPLOAD_MANIFEST_DIR"
    return
  fi

  if [[ -n ${USER:-} ]]; then
    scratch_root="/scratch/${project_name}/${USER}"
    if [[ -d $scratch_root && -w $scratch_root ]]; then
      printf '%s\n' "$scratch_root/.rds_transfer_manifests"
      return
    fi
  fi

  printf '%s\n' "$HOME/.rds_transfer_manifests"
}

sanitize_manifest_token() {
  printf '%s' "$1" | sed 's#^/*##; s#[^A-Za-z0-9._-]#_#g; s#_\\{2,\\}#_#g; s#_$##'
}

prioritize_pending_files() {
  local input_file="$1"
  local output_file="$2"
  local ranked_file="$tmpdir/pending_files_ranked.txt"
  local rel_path=""
  local local_match=""
  local priority=2
  local mtime=""

  : > "$ranked_file"

  while IFS= read -r rel_path; do
    local_match="$src_root/$rel_path"
    [[ -f $local_match ]] || continue

    priority=2
    if [[ $rel_path != */* && $rel_path == *_samplesheet_with_results.tsv ]]; then
      priority=0
    elif [[ $rel_path == *_consolidated/* ]]; then
      priority=1
    fi

    mtime=$(find "$local_match" -prune -printf '%T@\n')
    printf '%s\t%s\t%s\n' "$priority" "$mtime" "$rel_path" >> "$ranked_file"
  done < "$input_file"

  sort -t $'\t' -k1,1n -k2,2nr -k3,3 "$ranked_file" | awk -F '\t' '{print $3}' > "$output_file"
}

run_sftp() {
  local commands_file="$1"

  if [[ -n $sftp_opts ]]; then
    # shellcheck disable=SC2206
    sftp_opts_array=($sftp_opts)
  else
    sftp_opts_array=()
  fi

  sftp "${sftp_opts_array[@]}" "$user@$host" < "$commands_file"
}

append_remote_mkdirs() {
  local commands_file="$1"
  local target_dir="$2"
  local cache_file="$3"
  local current_remote=""
  local part=""
  local -a remote_parts=()

  target_dir="${target_dir%/}"
  if [[ -z $target_dir || $target_dir == "." ]]; then
    return
  fi

  IFS='/' read -r -a remote_parts <<< "${target_dir#/}"
  current_remote=""
  for part in "${remote_parts[@]}"; do
    [[ -z $part ]] && continue
    current_remote="${current_remote}/${part}"
    if [[ -f $cache_file ]] && grep -Fxq "$current_remote" "$cache_file"; then
      continue
    fi
    printf 'mkdir %s\n' "$current_remote" >> "$commands_file"
    printf '%s\n' "$current_remote" >> "$cache_file"
  done
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
run_name="$(basename "$src_path")"

if [[ -z $manifest_path ]]; then
  manifest_dir="$(default_manifest_dir)"
  mkdir -p "$manifest_dir"
  src_token="$(sanitize_manifest_token "$src_path")"
  dest_token="$(sanitize_manifest_token "$dest")"
  manifest_path="$manifest_dir/${src_token}__TO__${dest_token}.uploaded_files.txt"
fi

touch "$manifest_path"

local_files="$tmpdir/local_files.txt"
already_done="$tmpdir/already_done.txt"
missing_files="$tmpdir/missing_files.txt"
info_file="$tmpdir/gadi_to_rds_transfer_info.txt"
timestamp_marker="$tmpdir/copy_since.marker"
total_files_queued=0
uploaded_files_count=0

if [[ -n $copy_since_raw ]]; then
  if ! touch -d "$copy_since_raw" "$timestamp_marker" 2>/dev/null; then
    echo "Invalid RDS_COPY_SINCE timestamp: $copy_since_raw" >&2
    exit 1
  fi
fi

if [[ -f $src_path ]]; then
  src_root="$(dirname "$src_path")"
  rel_file="$(basename "$src_path")"
  if [[ -n $copy_since_raw && ! $src_path -nt $timestamp_marker ]]; then
    : > "$local_files"
  else
    printf '%s\n' "$rel_file" > "$local_files"
  fi
else
  src_root="$src_path"
  if [[ -n $copy_since_raw ]]; then
    find "$src_path" -type f -newer "$timestamp_marker" -printf '%P\n' | sort -u > "$local_files"
  else
    find "$src_path" -type f -printf '%P\n' | sort -u > "$local_files"
  fi
fi

filter_excluded_files() {
  local input_file="$1"
  local output_file="$2"
  local patterns_file="$3"
  local rel_path=""
  local rel_dir=""
  local rel_base=""
  local pattern=""
  local keep_file=1

  : > "$output_file"

  while IFS= read -r rel_path; do
    keep_file=1
    rel_dir=$(dirname "$rel_path")
    rel_base=$(basename "$rel_path")

    while IFS= read -r pattern; do
      [[ -z $pattern ]] && continue
      if [[ $rel_path == $pattern || $rel_base == $pattern ]]; then
        keep_file=0
        break
      fi
      if [[ $rel_dir != "." && $rel_dir == $pattern ]]; then
        keep_file=0
        break
      fi
    done < "$patterns_file"

    if [[ $keep_file -eq 1 ]]; then
      printf '%s\n' "$rel_path" >> "$output_file"
    fi
  done < "$input_file"
}

filter_excluded_paths() {
  local input_file="$1"
  local output_file="$2"
  local patterns_file="$3"
  local rel_path=""
  local pattern=""
  local keep_file=1

  : > "$output_file"

  while IFS= read -r rel_path; do
    keep_file=1

    while IFS= read -r pattern; do
      [[ -z $pattern ]] && continue
      if [[ $rel_path == $pattern ]]; then
        keep_file=0
        break
      fi
    done < "$patterns_file"

    if [[ $keep_file -eq 1 ]]; then
      printf '%s\n' "$rel_path" >> "$output_file"
    fi
  done < "$input_file"
}

filter_included_dirs() {
  local input_file="$1"
  local output_file="$2"
  local include_file="$3"

  awk '
    NR == FNR {
      include[++n] = $0
      next
    }
    {
      keep = 0
      for (i = 1; i <= n; i++) {
        prefix = include[i]
        if ($0 == prefix || index($0, prefix "/") == 1) {
          keep = 1
          break
        }
      }
      if (keep) {
        print
      }
    }
  ' "$include_file" "$input_file" > "$output_file"
}

if [[ -n $include_dirs_raw ]]; then
  include_file="$tmpdir/include_dirs.txt"
  printf '%s\n' "$include_dirs_raw" | tr ',' '\n' | sed 's#//*#/#g; s#^/##; s#/$##' | sed '/^$/d' > "$include_file"

  if [[ -s $include_file ]]; then
    filter_included_dirs "$local_files" "$tmpdir/local_files.included" "$include_file"
    mv "$tmpdir/local_files.included" "$local_files"
  fi
fi

if [[ -n $exclude_dirs_raw ]]; then
  exclude_file="$tmpdir/exclude_dirs.txt"
  printf '%s\n' "$exclude_dirs_raw" | tr ',' '\n' | sed 's#//*#/#g; s#^/##; s#/$##' | sed '/^$/d' > "$exclude_file"

  if [[ -s $exclude_file ]]; then
    awk '
      NR == FNR {
        excluded[++n] = $0
        next
      }
      {
        keep = 1
        for (i = 1; i <= n; i++) {
          prefix = excluded[i]
          if ($0 == prefix || index($0, prefix "/") == 1) {
            keep = 0
            break
          }
        }
        if (keep) {
          print
        }
      }
    ' "$exclude_file" "$local_files" > "$tmpdir/local_files.filtered"
    mv "$tmpdir/local_files.filtered" "$local_files"
  fi
fi

exclude_files_file="$tmpdir/exclude_files.txt"
printf '%s\n' "$exclude_files_raw" | tr ',' '\n' | sed 's#^##; s#[[:space:]]*$##' | sed '/^$/d' > "$exclude_files_file"

if [[ -s $exclude_files_file ]]; then
  filter_excluded_files "$local_files" "$tmpdir/local_files.no_excluded_files" "$exclude_files_file"
  mv "$tmpdir/local_files.no_excluded_files" "$local_files"
fi

exclude_paths_file="$tmpdir/exclude_paths.txt"
printf '%s\n' "$exclude_paths_raw" | tr ',' '\n' | sed 's#^##; s#[[:space:]]*$##' | sed '/^$/d' > "$exclude_paths_file"

if [[ -s $exclude_paths_file ]]; then
  filter_excluded_paths "$local_files" "$tmpdir/local_files.no_excluded_paths" "$exclude_paths_file"
  mv "$tmpdir/local_files.no_excluded_paths" "$local_files"
fi

if [[ ! -s $local_files ]]; then
  if [[ -n $copy_since_raw ]]; then
    log "No files newer than $copy_since_raw under: $src_path"
    exit 0
  fi
  echo "No files found to transfer from: $src_path" >&2
  exit 1
fi

log "Checking manifest-tracked files for RDS destination $dest"
if [[ $ignore_manifest == 1 ]]; then
  cp "$local_files" "$missing_files"
  : > "$already_done"
else
  if [[ -s $manifest_path ]] && grep -q $'\t' "$manifest_path"; then
    cut -f2- "$manifest_path" | sort -u > "$already_done"
  else
    sort -u "$manifest_path" -o "$manifest_path"
    cp "$manifest_path" "$already_done"
  fi
  comm -23 "$local_files" "$already_done" > "$missing_files"
fi
if [[ $prioritize_uploads == 1 ]]; then
  prioritize_pending_files "$missing_files" "$tmpdir/missing_files.prioritized"
  mv "$tmpdir/missing_files.prioritized" "$missing_files"
fi
total_files_queued=$(wc -l < "$missing_files")

cat > "$info_file" <<EOF
Data copied from: $src_path
Destination: $dest
Copy since: ${copy_since_raw:-all files}
Files queued for upload: $total_files_queued
Transfer prepared on: $(date '+%Y-%m-%d %H:%M:%S %Z')
EOF

log "Local files found: $(wc -l < "$local_files")"
log "Manifest-tracked files: $(wc -l < "$manifest_path")"
log "Already accounted for: $(wc -l < "$already_done")"
log "Files queued for upload: $total_files_queued"
log "Transfer info file: $info_file"
log "SFTP chunk size: $chunk_size"
log "Upload manifest: $manifest_path"
log "Prioritize uploads: $prioritize_uploads"
if [[ $ignore_manifest == 1 ]]; then
  log "Manifest handling: ignored for this run; all eligible local files will be queued"
fi
if [[ -n $include_dirs_raw ]]; then
  log "Included source directories: $include_dirs_raw"
fi
if [[ -n $exclude_dirs_raw ]]; then
  log "Excluded source directories: $exclude_dirs_raw"
fi
if [[ -n $exclude_files_raw ]]; then
  log "Excluded file patterns: $exclude_files_raw"
fi
if [[ -n $exclude_paths_raw ]]; then
  log "Excluded path patterns: $exclude_paths_raw"
fi
if [[ -n $copy_since_raw ]]; then
  log "Copying only files newer than: $copy_since_raw"
fi

if [[ ! -s $missing_files ]]; then
  log "No new files need uploading"
  exit 0
fi

priority_results_file=$(grep -E -m1 '^[^/]+_samplesheet_with_results\.tsv$' "$missing_files" || true)
if [[ -n $priority_results_file ]]; then
  log "Priority upload queued: $priority_results_file"
fi
if grep -q '^[^/]*_consolidated/' "$missing_files"; then
  matched_consolidated_dir=$(grep -m1 '^[^/]*_consolidated/' "$missing_files" | cut -d/ -f1)
  log "Priority upload queued: ${matched_consolidated_dir}/"
fi

upload_chunk="$tmpdir/upload_001.sftp"
upload_chunk_list="$tmpdir/upload_001.files"
upload_chunk_dirs="$tmpdir/upload_001.dirs"
chunk_index=1
chunk_file_count=0
total_chunk_count=0
: > "$upload_chunk"
: > "$upload_chunk_dirs"
append_remote_mkdirs "$upload_chunk" "$dest" "$upload_chunk_dirs"
printf 'cd %s\n' "$dest" >> "$upload_chunk"
: > "$upload_chunk_list"

while read -r rel_path; do
  local_match="$src_root/$rel_path"
  if [[ ! -f $local_match ]]; then
    continue
  fi

  if [[ $chunk_file_count -ge $chunk_size ]]; then
    printf 'bye\n' >> "$upload_chunk"
    chunk_index=$((chunk_index + 1))
    total_chunk_count=$((total_chunk_count + 1))
    upload_chunk=$(printf '%s/upload_%03d.sftp' "$tmpdir" "$chunk_index")
    upload_chunk_list=$(printf '%s/upload_%03d.files' "$tmpdir" "$chunk_index")
    upload_chunk_dirs=$(printf '%s/upload_%03d.dirs' "$tmpdir" "$chunk_index")
    : > "$upload_chunk"
    : > "$upload_chunk_dirs"
    append_remote_mkdirs "$upload_chunk" "$dest" "$upload_chunk_dirs"
    printf 'cd %s\n' "$dest" >> "$upload_chunk"
    : > "$upload_chunk_list"
    chunk_file_count=0
  fi

  remote_dir=$(dirname "$rel_path")
  if [[ $remote_dir != "." ]]; then
    append_remote_mkdirs "$upload_chunk" "$dest/$remote_dir" "$upload_chunk_dirs"
  fi

  printf 'put %s %s/%s\n' "$local_match" "$dest" "$rel_path" >> "$upload_chunk"
  printf '%s\n' "$rel_path" >> "$upload_chunk_list"
  chunk_file_count=$((chunk_file_count + 1))
done < "$missing_files"

printf 'put %s %s/%s_transfer_info.txt\n' \
  "$info_file" "$dest" "$run_name" >> "$upload_chunk"
printf 'bye\n' >> "$upload_chunk"
total_chunk_count=$((total_chunk_count + 1))

log "Uploading files to RDS via SFTP in $total_chunk_count chunk(s)"
for chunk_file in "$tmpdir"/upload_*.sftp; do
  log "Running $(basename "$chunk_file")"
  run_sftp "$chunk_file"
  chunk_list="${chunk_file%.sftp}.files"
  if [[ -f $chunk_list ]]; then
    while IFS= read -r uploaded_rel_path; do
      [[ -n $uploaded_rel_path ]] || continue
      printf '%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$uploaded_rel_path" >> "$manifest_path"
      uploaded_files_count=$((uploaded_files_count + 1))
    done < "$chunk_list"
    log "Completed $(basename "$chunk_file"): uploaded $uploaded_files_count / $total_files_queued files"
  fi
done
log "Upload complete"
