#!/usr/bin/env bash

set -euo pipefail

results_dir="${1:-results_fimtyper}"
outfile="${2:-${results_dir}/fimtyper_summary.tsv}"

printf "sample\tfimtype\tidentity\tquery_hsp\tcontig\tposition\taccession\n" > "$outfile"

find "$results_dir" -path '*/results_tab.txt' | sort | while read -r f; do
  sample=$(basename "$(dirname "$(dirname "$f")")")

  data_line=$(awk '$1 ~ /^FimH/ && $2 ~ /^[0-9.]+$/ && $3 ~ /^[0-9]+\/[0-9]+$/ {print; exit}' "$f" || true)

  if [[ -n "$data_line" ]]; then
    fimtype=$(echo "$data_line" | awk '{print $1}')
    identity=$(echo "$data_line" | awk '{print $2}')
    query_hsp=$(echo "$data_line" | awk '{print $3}')
    contig=$(echo "$data_line" | awk '{print $4}')
    position=$(echo "$data_line" | awk '{print $5}')
    accession=$(echo "$data_line" | awk '{print $6}')
  else
    fimtype=""
    identity=""
    query_hsp=""
    contig=""
    position=""
    accession=""
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$sample" "$fimtype" "$identity" "$query_hsp" "$contig" "$position" "$accession" \
    >> "$outfile"
done

