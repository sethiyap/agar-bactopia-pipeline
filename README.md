# agar-bactopia-pipeline

Clean distributable AGAR Bactopia pipeline packaging with a single public
entrypoint and site-specific submission wrappers.

## Clone And Install On A Server

Example shared install on Gadi:

```bash
cd /g/data/rg42
git clone <repo-url> agar-bactopia-pipeline
cd /g/data/rg42/agar-bactopia-pipeline
```

Create the shared Gadi site config:

```bash
cp config/sites/gadi.env.example config/sites/gadi.local.env
```

Review and edit `config/sites/gadi.local.env` so the server-specific paths are
correct for that install.

Minimum paths to verify:

- `BACTOPIA_PIPELINE`
- `DATASETS_CACHE`
- `KRAKEN2_DB`
- `NEXTFLOW_CONFIG`
- `KLEBORATE_COMPAT_SCRIPT`
- `FIMTYPER_PIPELINE`
- `FIMTYPER_CONFIG`
- `MERGE_FIMTYPER_SCRIPT`
- `SING_CACHE`

Then test the entrypoints:

```bash
./bin/agar-bactopia
./wrappers/submit.gadi.sh --help
```

For other servers, keep the same repo layout and add a site config plus wrapper
for that scheduler/backend, for example `slurm`.

## Current backend

- `gadi` submit wrapper
- PBS batch orchestration
- shared Bactopia/Kraken/datasets config through a site env file

## Quick start on Gadi

1. Copy the site config:

```bash
cp config/sites/gadi.env.example config/sites/gadi.local.env
```

2. Edit `config/sites/gadi.local.env` if your shared paths differ.

3. Submit:

```bash
./bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

4. Enable the additional tools bundle if needed:

```bash
./bin/agar-bactopia submit gadi --additional-tools yes \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

## MLST Review And Discrepancy Resolution

The pipeline includes a review-driven standalone MLST follow-up for flagged
isolates.

Review logic:

- `map_agrf_samplesheet_results.R` compares the AGRF phenotype label in
  `Comments` to the genus implied by the MLST scheme
- samples are flagged `review_required == "yes"` when there is a
  phenotype-vs-MLST genus mismatch, an ambiguous MLST profile, or MLST warning
  text that needs follow-up
- only those flagged samples are rerun through the standalone review MLST step

Resolution logic:

- the raw automatic MLST call is preserved as `auto_scheme`, `auto_st`, and
  `auto_profile`
- if automatic `mlst` reports an ambiguity or tie and one tied scheme matches
  the AGRF phenotype, the helper reruns `mlst --scheme <matching>` and saves
  that as the resolved call
- if there is no phenotype-matching tied scheme, the resolved call stays the
  same as the automatic highest-scoring MLST result
- resolved outputs are written as `resolved_scheme`, `resolved_st`, and
  `resolved_profile`, with `resolution_note` showing how the discrepancy was
  handled

Outputs:

- `AGRF_samplesheet_with_results_review_required.tsv`
- `mlst_review_standalone/mlst_review.tsv`
- `AGRF_samplesheet_with_results_mlst_reviewed.tsv`
- optional `AGRF_samplesheet_with_results_post_review.tsv`

The final Excel workbook export prefers
`AGRF_samplesheet_with_results_mlst_reviewed.tsv` when present; otherwise it
falls back to `AGRF_samplesheet_with_results.tsv`.

## Layout

- `bin/agar-bactopia`: public CLI
- `wrappers/submit.gadi.sh`: Gadi-facing submission wrapper
- `config/defaults.env`: scheduler-agnostic defaults
- `config/sites/`: site-specific shared paths
- `scripts/`: internal pipeline helpers and PBS jobs
- `docs/runtime-dependencies.md`: bundled-vs-external runtime dependency audit
- `docs/gadi-shared-install-checklist.md`: shared Gadi deployment checklist

## Next steps

- add a `slurm` backend
- move more runtime assumptions out of PBS scripts into site configs
- add install and validation docs under `docs/`
