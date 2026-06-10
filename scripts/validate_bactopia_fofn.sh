#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <fofn.tsv>" >&2
  exit 1
fi

fofn="$1"

if [ ! -f "$fofn" ]; then
  echo "File not found: $fofn" >&2
  exit 1
fi

awk -F'\t' '
NR == 1 {
  ok = ($1 == "sample" && $2 == "runtype" && $3 == "r1" && $4 == "r2")
  next
}
NF < 4 || $1 == "" || $2 == "" || $3 == "" || ($2 == "paired-end" && $4 == "") {
  bad++
}
END {
  if (!ok) {
    print "Invalid header"
    exit 1
  }
  if (bad) {
    print "Invalid rows: " bad
    exit 1
  }
  print "FOFN looks valid"
}
' "$fofn"
