#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/download_kraken2_db.sh [OPTIONS]

Find-or-install a Kraken2 / Bracken database for the extra-tools bundle
(kraken2 + bracken). If KRAKEN2_DB already contains a built database (*.k2d
files) it is reused; otherwise a prebuilt index tarball is downloaded and
extracted into it. Prebuilt indexes from the Kraken2/Bracken index collection
already include the Bracken files, so one download covers both tools.

Behaviour:
  - If KRAKEN2_DB exists and contains hash.k2d/opts.k2d/taxo.k2d, do nothing
    (reuse) unless --force.
  - Otherwise download KRAKEN2_DB_URL and extract it into KRAKEN2_DB.
  - You are prompted before the (large, often 8-100+ GB) download unless --yes.

Options:
  --dest DIR    Target database dir (default: $KRAKEN2_DB)
  --url URL     Tarball URL of a prebuilt Kraken2+Bracken index (default: $KRAKEN2_DB_URL)
  --yes         Do not prompt before downloading
  --force       Re-download even if a built DB is already present
  --help        Print this message

Where to get a URL:
  Pick a collection (Standard, PlusPF, PlusPFP, ... at various sizes) from the
  Kraken2/Bracken index collection and copy its dated tarball URL:
    https://benlangmead.github.io/aws-indexes/k2
  e.g. PlusPF capped at 16 GB looks like:
    https://genome-idx.s3.amazonaws.com/kraken/k2_pluspf_16gb_YYYYMMDD.tar.gz
  Pass it with --url or set KRAKEN2_DB_URL. Match the size to your host memory
  (Kraken2 loads the whole DB into RAM).

On success, prints the KRAKEN2_DB=... line to add to your site config.
EOF
}

log() {
  printf '[download-kraken2-db] %s\n' "$*"
}

fail() {
  printf '[download-kraken2-db] ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

dest="${KRAKEN2_DB:-}"
url="${KRAKEN2_DB_URL:-}"
assume_yes=0
force=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) dest=$2; shift 2 ;;
    --url) url=$2; shift 2 ;;
    --yes) assume_yes=1; shift ;;
    --force) force=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -n $dest ]] || fail "No target set. Pass --dest DIR or set KRAKEN2_DB."

db_is_built() {
  local d=$1
  [[ -f "$d/hash.k2d" && -f "$d/opts.k2d" && -f "$d/taxo.k2d" ]]
}

# Reuse-if-present: a built Kraken2 DB has the three *.k2d files.
if db_is_built "$dest"; then
  if [[ $force -eq 0 ]]; then
    log "Kraken2 DB already present: $dest"
    log "Found hash.k2d / opts.k2d / taxo.k2d. Nothing to do (use --force to re-download)."
    exit 0
  fi
  log "DB present but --force given; re-downloading into: $dest"
fi

if [[ -z $url ]]; then
  cat >&2 <<EOF
[download-kraken2-db] ERROR: No download URL set.

Choose a prebuilt Kraken2/Bracken index and copy its tarball URL from:
  https://benlangmead.github.io/aws-indexes/k2

Then re-run with --url, e.g.:
  KRAKEN2_DB=$dest \\
  ./scripts/download_kraken2_db.sh \\
    --url https://genome-idx.s3.amazonaws.com/kraken/k2_pluspf_16gb_YYYYMMDD.tar.gz

Pick a size that fits your host RAM (Kraken2 loads the whole DB into memory).
EOF
  exit 1
fi

need_cmd curl
need_cmd tar

log "Kraken2 DB source: $url"
log "Kraken2 DB target: $dest"
log "NOTE: prebuilt indexes are large (commonly 8-100+ GB) and load into RAM at run time."

if [[ $assume_yes -ne 1 ]]; then
  printf '[download-kraken2-db] Download and extract this database now? [y/N] '
  read -r reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) log "Aborted by user. Nothing downloaded."; exit 0 ;;
  esac
fi

mkdir -p "$dest"
tmp_archive=$(mktemp "${TMPDIR:-/tmp}/kraken2-db.XXXXXX.tar.gz")
cleanup() { rm -f "$tmp_archive"; }
trap cleanup EXIT

log "Downloading archive (this can take a while)..."
if ! curl -fL --retry 3 -o "$tmp_archive" "$url"; then
  fail "Download failed from: $url. Check the URL at https://benlangmead.github.io/aws-indexes/k2"
fi
[[ -s $tmp_archive ]] || fail "Downloaded archive is empty: $url"

log "Extracting into $dest ..."
# Index tarballs contain the *.k2d files at the archive root.
tar -xzf "$tmp_archive" -C "$dest"

if ! db_is_built "$dest"; then
  fail "Extraction did not produce hash.k2d/opts.k2d/taxo.k2d in $dest. The archive may be wrong or wrapped in a subdirectory (move the *.k2d files to $dest)."
fi

log "Done. Kraken2/Bracken DB ready at: $dest"
cat <<EOF

Add this line to your site config (config/sites/<backend>.local.env), or export
it before submitting:

  KRAKEN2_DB=${dest}

EOF
