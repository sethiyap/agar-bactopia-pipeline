#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <input-file> [illumina|ont|assembly|accession]" >&2
  exit 1
fi

fofn="$1"
input_type=${2:-illumina}
input_type=$(printf '%s' "$input_type" | tr '[:upper:]' '[:lower:]')
[[ $input_type == "accessions" ]] && input_type=accession

if [[ ! -f $fofn ]]; then
  echo "File not found: $fofn" >&2
  exit 1
fi

case "$input_type" in
  accession)
    awk '
      NF == 0 { next }
      NF != 1 || $1 ~ /[[:space:]]/ { bad++ }
      seen[$1]++ { duplicate++ }
      { rows++ }
      END {
        if (!rows) {
          print "Accession file contains no accessions"
          exit 1
        }
        if (bad) {
          print "Invalid accession rows: " bad
          exit 1
        }
        if (duplicate) {
          print "Duplicate accession rows: " duplicate
          exit 1
        }
        print "Accession list looks valid"
      }
    ' "$fofn"
    exit
    ;;
  illumina) expected_runtype=paired-end ;;
  ont) expected_runtype=ont ;;
  assembly) expected_runtype=assembly ;;
  *)
    echo "Unsupported input type: $input_type" >&2
    exit 1
    ;;
esac

awk -F'\t' -v expected_runtype="$expected_runtype" '
NR == 1 {
  ok = ($1 == "sample" && $2 == "runtype" && $3 == "r1" && $4 == "r2")
  next
}
NF < 4 || $1 == "" || $2 != expected_runtype ||
  (expected_runtype != "assembly" && $3 == "") ||
  (expected_runtype == "paired-end" && $4 == "") ||
  (expected_runtype == "assembly" && (NF < 5 || $5 == "")) {
  bad++
}
seen[$1]++ { duplicate++ }
{ rows++ }
END {
  if (!ok) {
    print "Invalid header"
    exit 1
  }
  if (!rows) {
    print "FOFN contains no sample rows"
    exit 1
  }
  if (bad) {
    print "Invalid rows: " bad
    exit 1
  }
  if (duplicate) {
    print "Duplicate sample rows: " duplicate
    exit 1
  }
  print "FOFN looks valid"
}
' "$fofn"

while IFS=$'\t' read -r sample input_path; do
  if [[ ! -f $input_path ]]; then
    echo "Input file not found for sample $sample: $input_path" >&2
    exit 1
  fi
done < <(awk -F'\t' -v input_type="$input_type" 'NR > 1 {
  print $1 "\t" (input_type == "assembly" ? $5 : $3)
}' "$fofn")

if [[ $input_type == "illumina" ]]; then
  while IFS=$'\t' read -r sample r2; do
    if [[ ! -f $r2 ]]; then
      echo "R2 file not found for sample $sample: $r2" >&2
      exit 1
    fi
  done < <(awk -F'\t' 'NR > 1 { print $1 "\t" $4 }' "$fofn")
fi
