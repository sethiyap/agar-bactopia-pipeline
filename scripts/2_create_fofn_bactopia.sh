#!/usr/bin/env bash

set -euo pipefail

RAW_DIR="${1:?Usage: $0 <raw_dir> <output.fofn.tsv>}"
OUT_FOFN="${2:?Usage: $0 <raw_dir> <output.fofn.tsv>}"

printf "sample\truntype\tr1\tr2\textra\n" > "$OUT_FOFN"

find "$RAW_DIR" -maxdepth 1 -type f -name "*_R1.fastq.gz" | sort | while read -r r1; do
  base=$(basename "$r1")
  sample="${base%%_*}"

  r2="${r1/_R1.fastq.gz/_R2.fastq.gz}"

  if [[ ! -f "$r2" ]]; then
    echo "Missing R2 for: $r1" >&2
    exit 1
  fi

  printf "%s\tpaired-end\t%s\t%s\t\n" "$sample" "$r1" "$r2" >> "$OUT_FOFN"
done
