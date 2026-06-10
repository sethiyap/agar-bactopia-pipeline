#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/fetch_batch_assemblies.sh BATCH_DIR_RESULTS_MAIN_OR_SEARCH_ROOT OUTPUT_DIR

Examples:
  ./scripts/fetch_batch_assemblies.sh \
    /scratch/rg42/AGAR/intermediates/2025/B05/agar_batch_001 \
    /scratch/rg42/AGAR/intermediates/2025/B05/agar_batch_001_assemblies

  ./scripts/fetch_batch_assemblies.sh \
    /scratch/rg42/AGAR/intermediates/2025/B05/agar_batch_001/results_main \
    ./assemblies_batch_001

  ./scripts/fetch_batch_assemblies.sh \
    /scratch/rg42/AGAR/intermediates/2025/B05/agar_batch_XX \
    ./assemblies_all_batches

  ./scripts/fetch_batch_assemblies.sh \
    /scratch/rg42/AGAR/intermediates/2025/B05 \
    ./assemblies_all_batches

What it does:
  1. Finds files matching:
       */main/assembler/*.fna.gz
     beneath one or more batch results_main directories
  2. Copies them into OUTPUT_DIR
  3. Unzips them in place so OUTPUT_DIR ends up with *.fna files

Notes:
  - If the first argument ends with `results_main`, that directory is searched directly.
  - If it contains `XX`, that is treated as a wildcard matching batch numbers,
    for example `agar_batch_XX` matches `agar_batch_001`, `agar_batch_002`, ...
  - Otherwise, if it is a parent directory, the script recursively searches for
    `agar_batch*/results_main` beneath it.
EOF
}

if [[ $# -ne 2 ]]; then
  usage >&2
  exit 1
fi

input_path=$1
output_dir=$2

for cmd in find cp gunzip mkdir basename sort; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
done

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

mkdir -p "$output_dir"

resolve_results_main_dirs() {
  local raw_input=$1
  local search_input=""
  local input_dir=""
  local input_base=""

  if [[ $raw_input == *XX* ]]; then
    input_dir=$(dirname "$raw_input")
    input_base=$(basename "$raw_input")
    search_input=${input_base//XX/*}

    if [[ ! -d $input_dir ]]; then
      echo "Input parent directory not found: $input_dir" >&2
      exit 1
    fi

    find "$input_dir" -mindepth 1 -maxdepth 1 -type d -name "$search_input" | sort
    return
  fi

  if [[ ! -d $raw_input ]]; then
    echo "Input directory not found: $raw_input" >&2
    exit 1
  fi

  if [[ $(basename "$raw_input") == "results_main" ]]; then
    printf '%s\n' "$raw_input"
    return
  fi

  if [[ $(basename "$raw_input") == agar_batch* ]]; then
    printf '%s\n' "$raw_input"
    return
  fi

  find "$raw_input" -type d -path '*/agar_batch*/results_main' | sort
}

mapfile -t input_dirs < <(resolve_results_main_dirs "$input_path")

if [[ ${#input_dirs[@]} -eq 0 ]]; then
  echo "No batch directories matched: $input_path" >&2
  exit 1
fi

assembly_files=()
copied_count=0
unzipped_count=0

for matched_dir in "${input_dirs[@]}"; do
  if [[ $(basename "$matched_dir") == "results_main" ]]; then
    results_main=$matched_dir
  else
    results_main="${matched_dir%/}/results_main"
  fi

  if [[ ! -d $results_main ]]; then
    echo "results_main directory not found: $results_main" >&2
    exit 1
  fi

  while IFS= read -r assembly; do
    assembly_files+=("$assembly")
  done < <(
    find "$results_main" -type f -path '*/main/assembler/*.fna.gz' \
      ! -path '*/bactopia-runs/*' \
      | sort
  )
done

if [[ ${#assembly_files[@]} -eq 0 ]]; then
  echo "No assembler .fna.gz files found under: $input_path" >&2
  exit 1
fi

log "Found ${#input_dirs[@]} batch results_main directories"
log "Found ${#assembly_files[@]} compressed assemblies"

for assembly in "${assembly_files[@]}"; do
  dest_gz="${output_dir}/$(basename "$assembly")"
  dest_fna=${dest_gz%.gz}

  if [[ -e $dest_gz || -e $dest_fna ]]; then
    echo "Destination file already exists, refusing to overwrite: $dest_gz" >&2
    exit 1
  fi

  cp "$assembly" "$dest_gz"
  copied_count=$((copied_count + 1))
  gunzip "$dest_gz"
  unzipped_count=$((unzipped_count + 1))
  log "Copied and unzipped: $(basename "$dest_fna")"
done

log "Summary: copied ${copied_count} files and unzipped ${unzipped_count} files"
log "Assemblies written to: $output_dir"
