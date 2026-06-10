#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/normalize_agar_fastq_sample_names.sh <fastq_dir>
  ./scripts/normalize_agar_fastq_sample_names.sh --dry-run <fastq_dir>
  ./scripts/normalize_agar_fastq_sample_names.sh --log-file sample_name_validation.log <fastq_dir>

Validate AGAR FASTQ sample names before starting Bactopia.

This is a prerequisite filename check and rename helper. It is not part of the
transfer workflow.

Valid sample name examples:
  25GNB-1363
  25GNB-1317R

If the sample name does not match the valid pattern, the script tries to fix it
by replacing underscores with hyphens in the sample name only.

Example:
  25GNB_1363_AAJ3GMMM5_CCTTGGCATC-GACCGATTCG_L001_R1.fastq.gz
becomes:
  25GNB-1363_AAJ3GMMM5_CCTTGGCATC-GACCGATTCG_L001_R1.fastq.gz

Behaviour:
  --dry-run   Report the filenames that would be changed without renaming them
  --log-file  Write a per-file validation log
  default     Rename invalid sample-name prefixes in place when they can be fixed

If no filenames need to be changed, the script reports:
  All FASTQ file names are correct.
EOF
}

dry_run=0
log_file=

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --dry-run)
      dry_run=1
      shift
      ;;
    --log-file)
      if [[ $# -lt 2 ]]; then
        echo "--log-file requires a path" >&2
        exit 1
      fi
      log_file=$2
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

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

fastq_dir=$1

if [[ ! -d $fastq_dir ]]; then
  echo "Directory not found: $fastq_dir" >&2
  exit 1
fi

if [[ -z $log_file ]]; then
  log_file="${fastq_dir%/}/sample_name_validation.log"
fi

for cmd in find mv basename dirname; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
done

printf 'status\tchanged_at_source\toriginal_filename\tfinal_filename\tnote\n' > "$log_file"

write_log() {
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$log_file"
}

valid_pattern='^[0-9]{2}GNB-[0-9]+R?$'
checked=0
renamed=0
unchanged=0
invalid=0

while IFS= read -r -d '' path; do
  base=$(basename "$path")
  dir=$(dirname "$path")
  checked=$((checked + 1))

  if [[ ! $base =~ ^(.+)_([^_]+)_([^_]+)_L([0-9]{3})_R([12])\.(fastq|fq)\.gz$ ]]; then
    echo "SKIP    $base"
    echo "        filename does not match the expected FASTQ layout" >&2
    write_log "SKIP" "unknown" "$base" "$base" "filename does not match expected FASTQ layout"
    invalid=$((invalid + 1))
    continue
  fi

  sample_name=${BASH_REMATCH[1]}
  flowcell=${BASH_REMATCH[2]}
  barcode=${BASH_REMATCH[3]}
  lane=${BASH_REMATCH[4]}
  read_pair=${BASH_REMATCH[5]}
  extension=${BASH_REMATCH[6]}

  if [[ $sample_name =~ $valid_pattern ]]; then
    write_log "OK" "no" "$base" "$base" "sample name already valid"
    unchanged=$((unchanged + 1))
    continue
  fi

  fixed_sample_name=${sample_name//_/-}
  if [[ ! $fixed_sample_name =~ $valid_pattern ]]; then
    echo "INVALID $base"
    echo "        sample name '$sample_name' does not match and cannot be fixed with '_' -> '-'" >&2
    write_log "INVALID" "unknown" "$base" "$base" "sample name '$sample_name' cannot be fixed with '_' -> '-'"
    invalid=$((invalid + 1))
    continue
  fi

  new_base="${fixed_sample_name}_${flowcell}_${barcode}_L${lane}_R${read_pair}.${extension}.gz"
  new_path="$dir/$new_base"

  if [[ -e $new_path ]]; then
    echo "CONFLICT $base"
    echo "        target already exists: $new_base" >&2
    write_log "CONFLICT" "yes" "$base" "$new_base" "target already exists"
    invalid=$((invalid + 1))
    continue
  fi

  if [[ $dry_run -eq 1 ]]; then
    echo "RENAME  $base -> $new_base"
    write_log "RENAME" "yes" "$base" "$new_base" "dry run only"
  else
    mv "$path" "$new_path"
    echo "RENAME  $base -> $new_base"
    write_log "RENAME" "yes" "$base" "$new_base" "renamed in place"
  fi
  renamed=$((renamed + 1))
done < <(find "$fastq_dir" -type f \( -name '*.fastq.gz' -o -name '*.fq.gz' \) -print0)

echo
if [[ $renamed -eq 0 && $invalid -eq 0 ]]; then
  echo "All FASTQ file names are correct."
  echo
fi

echo "Checked:   $checked"
if [[ $dry_run -eq 1 ]]; then
  echo "To rename: $renamed"
else
  echo "Renamed:   $renamed"
fi
echo "Unchanged: $unchanged"
echo "Invalid:   $invalid"
echo "Log file:  $log_file"
