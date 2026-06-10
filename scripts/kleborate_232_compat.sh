#!/usr/bin/env bash

set -euo pipefail

# Some Kleborate environments call `tput` during startup. In batch jobs TERM can
# be unset, which causes noisy warnings before argument parsing even begins.
export TERM="${TERM:-dumb}"

# Compatibility wrapper for running Kleborate 2.3.2 with a newer
# Bactopia Kleborate process definition.
#
# It accepts a subset of the newer CLI style, ignores v3-only flags such as
# `--preset`, translates `--assemblies` into `-a`, honors `--outdir`, and
# translates the invocation into the older
# 2.3.x syntax:
#   kleborate -a <assembly> [--all] -o <outfile> ...

REAL_KLEBORATE="${KLEBORATE_REAL:-/usr/local/bin/kleborate}"

if [[ ! -x "$REAL_KLEBORATE" ]]; then
  REAL_KLEBORATE="$(command -v kleborate.real || true)"
fi

if [[ -z "$REAL_KLEBORATE" || ! -x "$REAL_KLEBORATE" ]]; then
  echo "Could not find the real kleborate binary. Set KLEBORATE_REAL first." >&2
  exit 127
fi

if [[ $# -eq 0 ]]; then
  exec "$REAL_KLEBORATE"
fi

assemblies=()
outdir="."
outfile=""
translated_args=()
need_all=true

normalize_sample_name() {
  local input="$1"
  local base
  base="$(basename "$input")"
  base="${base%.gz}"
  base="${base%.fasta}"
  base="${base%.fa}"
  base="${base%.fna}"
  printf '%s' "$base"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version|-h|--help)
      exec "$REAL_KLEBORATE" "$@"
      ;;
    --preset=*)
      shift
      ;;
    --preset)
      shift 2
      ;;
    --outdir=*)
      outdir="${1#--outdir=}"
      shift
      ;;
    --outdir)
      outdir="$2"
      shift 2
      ;;
    --assemblies=*)
      assemblies+=("${1#--assemblies=}")
      shift
      ;;
    --assemblies)
      shift
      while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
        assemblies+=("$1")
        shift
      done
      ;;
    --all|-r|-k|--kaptive_k|--kaptive_o|--force_index)
      translated_args+=("$1")
      [[ "$1" == "--all" ]] && need_all=false
      shift
      ;;
    --min_identity=*|--min_coverage=*|--min_spurious_identity=*|--min_spurious_coverage=*|--min_kaptive_confidence=*|--kaptive_k_outfile=*|--kaptive_o_outfile=*)
      translated_args+=("${1%%=*}" "${1#*=}")
      shift
      ;;
    -o=*)
      outfile="${1#*=}"
      translated_args+=("-o" "$outfile")
      shift
      ;;
    --min_identity|--min_coverage|--min_spurious_identity|--min_spurious_coverage|--min_kaptive_confidence|--kaptive_k_outfile|--kaptive_o_outfile|-o)
      translated_args+=("$1" "$2")
      [[ "$1" == "-o" ]] && outfile="$2"
      shift 2
      ;;
    -a)
      translated_args+=("$1")
      shift
      while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
        assemblies+=("$1")
        translated_args+=("$1")
        shift
      done
      ;;
    --*)
      # Ignore newer/unknown long options to maximize compatibility.
      if [[ "$1" == *=* ]]; then
        shift
      elif [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
        shift 2
      else
        shift
      fi
      ;;
    -*)
      translated_args+=("$1")
      shift
      ;;
    *)
      assemblies+=("$1")
      shift
      ;;
  esac
done

if [[ ${#assemblies[@]} -eq 0 ]]; then
  echo "No assemblies were provided to Kleborate." >&2
  exit 2
fi

mkdir -p "$outdir"
outdir="${outdir%/}"
[[ -z "$outdir" ]] && outdir="."

if [[ -z "$outfile" ]]; then
  sample_name="$(normalize_sample_name "${assemblies[0]}")"
  outfile="${outdir}/${sample_name}_output.txt"
  translated_args+=("-o" "$outfile")
fi

has_a=false
for arg in "${translated_args[@]}"; do
  if [[ "$arg" == "-a" ]]; then
    has_a=true
    break
  fi
done

if ! $has_a; then
  translated_args=("-a" "${assemblies[@]}" "${translated_args[@]}")
fi

if $need_all; then
  translated_args=("--all" "${translated_args[@]}")
fi

exec "$REAL_KLEBORATE" "${translated_args[@]}"

