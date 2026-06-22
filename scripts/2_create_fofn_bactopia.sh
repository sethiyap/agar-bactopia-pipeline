#!/usr/bin/env bash

set -euo pipefail

RAW_DIR="${1:?Usage: $0 <raw_dir> <output.fofn.tsv>}"
OUT_FOFN="${2:?Usage: $0 <raw_dir> <output.fofn.tsv>}"
INCLUDE_SAMPLE_REGEX="${INCLUDE_SAMPLE_REGEX:-}"

printf "sample\truntype\tr1\tr2\textra\n" > "$OUT_FOFN"

total_r1=0
included_pairs=0
skipped_pairs=0

while IFS= read -r r1; do
  total_r1=$((total_r1 + 1))
  base=$(basename "$r1")
  sample="${base%%_*}"

  if [[ -n $INCLUDE_SAMPLE_REGEX && ! $sample =~ $INCLUDE_SAMPLE_REGEX ]]; then
    skipped_pairs=$((skipped_pairs + 1))
    continue
  fi

  if [[ $r1 == *_R1.fastq.gz ]]; then
    r2="${r1/_R1.fastq.gz/_R2.fastq.gz}"
  elif [[ $r1 == *_R1.fq.gz ]]; then
    r2="${r1/_R1.fq.gz/_R2.fq.gz}"
  else
    echo "Unsupported FASTQ layout: $r1" >&2
    exit 1
  fi

  if [[ ! -f "$r2" ]]; then
    echo "Missing R2 for: $r1" >&2
    exit 1
  fi

  printf "%s\tpaired-end\t%s\t%s\t\n" "$sample" "$r1" "$r2" >> "$OUT_FOFN"
  included_pairs=$((included_pairs + 1))
done < <(find "$RAW_DIR" -maxdepth 1 -type f \( -name "*_R1.fastq.gz" -o -name "*_R1.fq.gz" \) | sort)

if [[ $total_r1 -eq 0 ]]; then
  rm -f "$OUT_FOFN"
  echo "No R1 FASTQ files were found in: $RAW_DIR" >&2
  exit 1
fi

if [[ $included_pairs -eq 0 ]]; then
  rm -f "$OUT_FOFN"
  if [[ -n $INCLUDE_SAMPLE_REGEX ]]; then
    echo "No FASTQ pairs matched INCLUDE_SAMPLE_REGEX=$INCLUDE_SAMPLE_REGEX in: $RAW_DIR" >&2
  else
    echo "No FASTQ pairs were written to: $OUT_FOFN" >&2
  fi
  exit 1
fi

echo "FOFN pairs included: $included_pairs"
if [[ $skipped_pairs -gt 0 ]]; then
  echo "FOFN pairs skipped by sample filter: $skipped_pairs"
fi
