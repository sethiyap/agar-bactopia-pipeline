#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/run_review_mlst_from_tsv.sh \
    --review-tsv /path/to/AGRF_samplesheet_with_results_review_required.tsv \
    --results-root /scratch/rg42/AGAR/intermediates/2025/B05 \
    [--batch-prefix batch_bactopia] \
    [--mapped-tsv /path/to/AGRF_samplesheet_with_results.tsv] \
    [--output-dir /scratch/rg42/AGAR/intermediates/2025/B05/mlst_review_standalone]

Optional environment variables:
  MINIFORGE_ROOT   Default: /g/data/rg42/bactopia_datasets/miniforge3
  MLST_ENV         Default: /g/data/rg42/bactopia_datasets/envs/mlst_env
  MLST_SCHEME      Optional: force a scheme, e.g. ecoli_achtman_4
EOF
}

REVIEW_TSV=""
RESULTS_ROOT=""
BATCH_PREFIX="batch_bactopia"
OUTPUT_DIR=""
MAPPED_TSV=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --review-tsv)
      REVIEW_TSV=${2:-}
      shift 2
      ;;
    --results-root)
      RESULTS_ROOT=${2:-}
      shift 2
      ;;
    --batch-prefix)
      BATCH_PREFIX=${2:-}
      shift 2
      ;;
    --mapped-tsv)
      MAPPED_TSV=${2:-}
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR=${2:-}
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z $REVIEW_TSV || -z $RESULTS_ROOT ]]; then
  usage
  exit 1
fi

if [[ ! -f $REVIEW_TSV ]]; then
  echo "Review TSV not found: $REVIEW_TSV" >&2
  exit 1
fi

if [[ ! -d $RESULTS_ROOT ]]; then
  echo "Results root not found: $RESULTS_ROOT" >&2
  exit 1
fi

mapped_output_from_review() {
  local review_tsv=$1
  local dir_name stub

  dir_name=$(dirname "$review_tsv")
  stub=$(basename "$review_tsv")
  stub=${stub%_review_required.tsv}
  printf '%s/%s.tsv\n' "$dir_name" "$stub"
}

reviewed_output_from_mapped() {
  local mapped_tsv=$1
  local dir_name stub

  dir_name=$(dirname "$mapped_tsv")
  stub=$(basename "$mapped_tsv")
  stub=${stub%.tsv}
  printf '%s/%s_mlst_reviewed.tsv\n' "$dir_name" "$stub"
}

MINIFORGE_ROOT=${MINIFORGE_ROOT:-/g/data/rg42/bactopia_datasets/miniforge3}
MLST_ENV=${MLST_ENV:-/g/data/rg42/bactopia_datasets/envs/mlst_env}
if [[ -z $OUTPUT_DIR ]]; then
  OUTPUT_DIR="${RESULTS_ROOT}/mlst_review_standalone"
fi
if [[ -z $MAPPED_TSV ]]; then
  MAPPED_TSV=$(mapped_output_from_review "$REVIEW_TSV")
fi
if [[ ! -f $MAPPED_TSV ]]; then
  echo "Mapped AGRF TSV not found: $MAPPED_TSV" >&2
  exit 1
fi

MLST_OUT="${OUTPUT_DIR}/mlst_review.tsv"
MISSING_OUT="${OUTPUT_DIR}/mlst_review_missing.tsv"
RAW_LOG="${OUTPUT_DIR}/mlst_review_raw.log"
REVIEWED_TSV=$(reviewed_output_from_mapped "$MAPPED_TSV")

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

find_assembly_for_sample() {
  local sample_name=$1
  local candidates

  candidates=$(find "$RESULTS_ROOT" \
    \( -path "*/${BATCH_PREFIX}_*/results_main/${sample_name}/main/assembler/${sample_name}.fna.gz" -o \
       -path "*/${BATCH_PREFIX}_*/results_main/${sample_name}/main/assembler/${sample_name}.fa.gz" -o \
       -path "*/${BATCH_PREFIX}_*/results_main/${sample_name}/main/assembler/${sample_name}.fasta.gz" -o \
       -path "*/${BATCH_PREFIX}_*/results_main/${sample_name}/main/assembler/${sample_name}.fna" -o \
       -path "*/${BATCH_PREFIX}_*/results_main/${sample_name}/main/assembler/${sample_name}.fa" -o \
       -path "*/${BATCH_PREFIX}_*/results_main/${sample_name}/main/assembler/${sample_name}.fasta" \) \
    -type f \
    2>/dev/null | sort || true)

  if [[ -n $candidates ]]; then
    printf '%s\n' "$candidates" | head -n 1
    return
  fi

  candidates=$(find "$RESULTS_ROOT" -type f \
    -path "*/${BATCH_PREFIX}_*/results_main/${sample_name}/*" \
    \( -name '*.fna.gz' -o -name '*.fa.gz' -o -name '*.fasta.gz' -o -name '*.fna' -o -name '*.fa' -o -name '*.fasta' \) \
    ! -path '*/tools/*' \
    ! -path '*/bactopia-runs/*' \
    2>/dev/null | sort || true)

  if [[ -n $candidates ]]; then
    printf '%s\n' "$candidates" | head -n 1
  fi
}

extract_review_records() {
  awk -F '\t' '
    NR == 1 {
      for (i = 1; i <= NF; i++) {
        if ($i == "Sample name") sample_col = i
        if ($i == "Comments") comments_col = i
        if ($i == "review_required") review_col = i
      }
      next
    }
    sample_col && review_col && $review_col == "yes" && $sample_col != "" {
      comments = comments_col ? $comments_col : ""
      print $sample_col "\t" comments
    }
  ' "$REVIEW_TSV" | sort -u
}

canonicalize_text() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

phenotype_to_scheme() {
  local phenotype
  phenotype=$(canonicalize_text "$1")

  case "$phenotype" in
    *escherichia\ coli*|*e.\ coli*)
      printf 'ecoli_achtman_4\n'
      ;;
    *salmonella*)
      printf 'salmonella\n'
      ;;
    *klebsiella*)
      printf 'klebsiella\n'
      ;;
    *citrobacter\ freundii*)
      printf 'cfreundii\n'
      ;;
    *enterobacter\ cloacae*)
      printf 'cloacae\n'
      ;;
    *serratia*)
      printf 'serratia\n'
      ;;
    *proteus*)
      printf 'proteus\n'
      ;;
    *morganella*)
      printf 'morganella\n'
      ;;
    *providencia*)
      printf 'providencia\n'
      ;;
    *cronobacter*)
      printf 'cronobacter\n'
      ;;
    *pseudomonas\ aeruginosa*)
      printf 'paeruginosa\n'
      ;;
    *)
      return 1
      ;;
  esac
}

parse_mlst_result_line() {
  local line=$1
  awk '
    BEGIN { OFS="\t" }
    {
      scheme = (NF >= 2 ? $2 : "")
      st = (NF >= 3 ? $3 : "")
      profile = ""
      if (NF > 3) {
        for (i = 4; i <= NF; i++) {
          profile = profile (i == 4 ? "" : " ") $i
        }
      }
      print scheme, st, profile
    }
  ' <<< "$line"
}

parse_warning_candidates() {
  local warning_line=$1
  awk '
    BEGIN { OFS="\t" }
    {
      line = $0
      sub(/^WARNING:[[:space:]]*/, "", line)
      split(line, bits, /[[:space:]]+/)
      schemes = bits[1]
      score = ""
      for (i = 1; i <= length(bits); i++) {
        if (bits[i] ~ /^score=/) {
          split(bits[i], score_parts, "=")
          score = score_parts[2]
        }
      }
      gsub(/\([^)]+\)/, "", schemes)
      gsub(/==/, "\t", schemes)
      print schemes, score
    }
  ' <<< "$warning_line"
}

run_mlst_capture() {
  local input=$1
  shift || true
  mapfile -t MLST_CAPTURE_LINES < <(mlst "$@" "$input" 2>&1)
}

find_result_line() {
  local assembly=$1
  local mlst_input=$2
  local line

  for line in "${MLST_CAPTURE_LINES[@]}"; do
    if [[ $line == "$assembly"* || $line == "$mlst_input"* ]]; then
      printf '%s\n' "$line"
      return 0
    fi
  done
  return 1
}

write_reviewed_agrf_table() {
  local input_tsv=$1
  local review_tsv=$2
  local output_tsv=$3

  awk -F '\t' -v OFS='\t' '
    NR == FNR {
      if (FNR == 1) {
        for (i = 1; i <= NF; i++) {
          if ($i == "sample") sample_col = i
          if ($i == "resolved_scheme") resolved_scheme_col = i
          if ($i == "resolved_st") resolved_st_col = i
          if ($i == "resolved_profile") resolved_profile_col = i
          if ($i == "resolution_note") resolution_note_col = i
          if ($i == "warning_score") warning_score_col = i
        }
        next
      }

      sample = $sample_col
      resolved_scheme[sample] = (resolved_scheme_col ? $resolved_scheme_col : "")
      resolved_st[sample] = (resolved_st_col ? $resolved_st_col : "")
      resolved_profile[sample] = (resolved_profile_col ? $resolved_profile_col : "")
      resolution_note[sample] = (resolution_note_col ? $resolution_note_col : "")
      warning_score[sample] = (warning_score_col ? $warning_score_col : "")
      next
    }

    FNR == 1 {
      for (i = 1; i <= NF; i++) {
        if ($i == "Sample name") sample_name_col = i
        if ($i == "mlst_scheme") mlst_scheme_col = i
        if ($i == "mlst_st") mlst_st_col = i
        if ($i == "mlst_profile") mlst_profile_col = i
      }
      print $0, "mlst_review_note"
      next
    }

    {
      sample = (sample_name_col ? $sample_name_col : "")
      if (mlst_scheme_col && resolved_scheme[sample] != "") {
        $mlst_scheme_col = resolved_scheme[sample]
      }
      if (mlst_st_col && resolved_st[sample] != "") {
        $mlst_st_col = resolved_st[sample]
      }
      if (mlst_profile_col && resolved_profile[sample] != "") {
        $mlst_profile_col = resolved_profile[sample]
      }
      review_note = ""
      if (resolved_scheme[sample] != "" || resolved_st[sample] != "" || resolved_profile[sample] != "") {
        review_note = "Resolved using standalone MLST"
        if (resolution_note[sample] != "") {
          review_note = review_note " (" resolution_note[sample]
          if (warning_score[sample] != "") {
            review_note = review_note ", warning_score=" warning_score[sample]
          }
          review_note = review_note ")"
        } else if (warning_score[sample] != "") {
          review_note = review_note " (warning_score=" warning_score[sample] ")"
        }
      }
      print $0, review_note
    }
  ' "$review_tsv" "$input_tsv" > "$output_tsv"
}

if [[ ! -f ${MINIFORGE_ROOT}/etc/profile.d/conda.sh ]]; then
  echo "Conda init script not found: ${MINIFORGE_ROOT}/etc/profile.d/conda.sh" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# shellcheck disable=SC1090
source "${MINIFORGE_ROOT}/etc/profile.d/conda.sh"
conda activate "$MLST_ENV"

if ! command -v mlst >/dev/null 2>&1; then
  echo "mlst not found after activating conda env: $MLST_ENV" >&2
  exit 1
fi

mapfile -t review_records < <(extract_review_records)

if [[ ${#review_records[@]} -eq 0 ]]; then
  {
    printf 'sample\tagrf_comments\tauto_scheme\tauto_st\tauto_profile\tresolved_scheme\tresolved_st\tresolved_profile\tresolution_note\twarning_score\tsource_assembly\n'
  } > "$MLST_OUT"
  {
    printf 'sample\treason\n'
  } > "$MISSING_OUT"
  : > "$RAW_LOG"
  write_reviewed_agrf_table "$MAPPED_TSV" "$MLST_OUT" "$REVIEWED_TSV"
  log "No review-required samples found in ${REVIEW_TSV}"
  log "Wrote empty MLST review outputs under: ${OUTPUT_DIR}"
  log "Wrote MLST-reviewed AGRF table: ${REVIEWED_TSV}"
  exit 0
fi

log "Running standalone MLST for ${#review_records[@]} review-required sample(s)"

{
  printf 'sample\tagrf_comments\tauto_scheme\tauto_st\tauto_profile\tresolved_scheme\tresolved_st\tresolved_profile\tresolution_note\twarning_score\tsource_assembly\n'
} > "$MLST_OUT"

{
  printf 'sample\treason\n'
} > "$MISSING_OUT"

: > "$RAW_LOG"

for record in "${review_records[@]}"; do
  sample_name=${record%%$'\t'*}
  agrf_comments=${record#*$'\t'}
  assembly=$(find_assembly_for_sample "$sample_name" || true)
  if [[ -z ${assembly:-} ]]; then
    log "No assembly found for ${sample_name}"
    printf '%s\tassembly_not_found\n' "$sample_name" >> "$MISSING_OUT"
    continue
  fi

  log "Running standalone MLST for ${sample_name}: ${assembly}"
  tmp_assembly=""
  mlst_input=$assembly
  if [[ $assembly == *.gz ]]; then
    tmp_assembly="${OUTPUT_DIR}/${sample_name}.fna"
    gunzip -c "$assembly" > "$tmp_assembly"
    mlst_input=$tmp_assembly
  fi

  if [[ -n ${MLST_SCHEME:-} ]]; then
    run_mlst_capture "$mlst_input" --scheme "$MLST_SCHEME"
  else
    run_mlst_capture "$mlst_input"
  fi

  printf '### %s ###\n' "$sample_name" >> "$RAW_LOG"
  printf '%s\n' "${MLST_CAPTURE_LINES[@]}" >> "$RAW_LOG"

  final_line=$(find_result_line "$assembly" "$mlst_input" || true)
  warning_line=""
  for line in "${MLST_CAPTURE_LINES[@]}"; do
    if [[ $line == WARNING:* ]]; then
      warning_line=$line
    fi
  done

  if [[ -z $final_line ]]; then
    log "No parseable MLST result line for ${sample_name}"
    printf '%s\tmlst_result_not_parseable\n' "$sample_name" >> "$MISSING_OUT"
  else
    IFS=$'\t' read -r auto_scheme auto_st auto_profile <<< "$(parse_mlst_result_line "$final_line")"
    resolved_scheme=$auto_scheme
    resolved_st=$auto_st
    resolved_profile=$auto_profile
    resolution_note="highest_scorer"
    warning_score=""

    if [[ -n $warning_line ]]; then
      warning_fields=$(parse_warning_candidates "$warning_line")
      warning_score=${warning_fields##*$'\t'}
      candidate_schemes=${warning_fields%$'\t'*}
      preferred_scheme=""
      if [[ -n ${MLST_SCHEME:-} ]]; then
        preferred_scheme=$MLST_SCHEME
      else
        preferred_scheme=$(phenotype_to_scheme "$agrf_comments" || true)
      fi

      if [[ -n $preferred_scheme ]] && grep -Fxq "$preferred_scheme" <<< "$(printf '%s\n' "$candidate_schemes" | tr '\t' '\n')"; then
        run_mlst_capture "$mlst_input" --scheme "$preferred_scheme"
        forced_line=$(find_result_line "$assembly" "$mlst_input" || true)
        if [[ -n $forced_line ]]; then
          IFS=$'\t' read -r resolved_scheme resolved_st resolved_profile <<< "$(parse_mlst_result_line "$forced_line")"
          resolution_note="phenotype_tie_break"
        fi
      fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$sample_name" \
      "$agrf_comments" \
      "$auto_scheme" \
      "$auto_st" \
      "$auto_profile" \
      "$resolved_scheme" \
      "$resolved_st" \
      "$resolved_profile" \
      "$resolution_note" \
      "$warning_score" \
      "$assembly" >> "$MLST_OUT"
  fi

  if [[ -n $tmp_assembly && -f $tmp_assembly ]]; then
    rm -f "$tmp_assembly"
  fi
done

log "Standalone review MLST written to: ${MLST_OUT}"
log "Missing/failed samples written to: ${MISSING_OUT}"
log "Raw MLST log written to: ${RAW_LOG}"
write_reviewed_agrf_table "$MAPPED_TSV" "$MLST_OUT" "$REVIEWED_TSV"
log "Wrote MLST-reviewed AGRF table: ${REVIEWED_TSV}"
