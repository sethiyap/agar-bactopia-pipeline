# Runtime Dependencies

This project ships the orchestration scripts, PBS wrappers, small config files,
and helper logic needed to run the AGAR Bactopia workflow.

## Bundled In This Repo

- `bin/agar-bactopia`
- `wrappers/submit.gadi.sh`
- `config/defaults.env`
- `config/sites/gadi.env.example`
- `scripts/submit_agar_full_pipeline.sh`
- `scripts/submit_bactopia_batch_pipeline.sh`
- PBS wrappers under `scripts/*.pbs`
- helper shell scripts under `scripts/*.sh`
- shipped workflow configs:
  - `scripts/nextflow.gadi.all_tools.config`
  - `scripts/kleborate_232_compat.config`
  - `scripts/kleborate_232_compat.sh`

## External Runtime Dependencies

These are not bundled in the repo and must exist on the execution site.

- Bactopia pipeline install:
  - `BACTOPIA_PIPELINE`
- shared Bactopia datasets cache / custom datasets:
  - `DATASETS_CACHE`
- Kraken2 / Bracken database:
  - `KRAKEN2_DB`
- FimTyper pipeline:
  - `FIMTYPER_PIPELINE`
- FimTyper config:
  - `FIMTYPER_CONFIG`
- optional FimTyper merge helper:
  - `MERGE_FIMTYPER_SCRIPT`
- Singularity cache and, if pre-pulled, container images:
  - `SING_CACHE`
  - optional `MLST_CONTAINER`
  - optional `KLEBORATE_CONTAINER`
- Conda / Miniforge install used by the standalone MLST review helper:
  - `MINIFORGE_ROOT`
  - `MLST_ENV`
- Python environment for final workbook export:
  - `python3`
  - `openpyxl`

## MLST Review Workflow

The packaged workflow includes a phenotype-guided MLST review stage.

- `map_agrf_samplesheet_results.R` writes the main AGRF-mapped results table and
  a review-only subset called `AGRF_samplesheet_with_results_review_required.tsv`
- a sample is flagged for review when the canonicalized AGRF phenotype in
  `Comments` disagrees with the canonicalized genus implied by the MLST scheme,
  or when MLST carries an ambiguity that requires follow-up
- `run_review_mlst_from_tsv.sh` reruns standalone `mlst` only for those flagged
  isolates

Resolution behavior:

- the raw automatic MLST call is preserved as `auto_scheme`, `auto_st`, and
  `auto_profile`
- if `mlst` reports an ambiguous or tied result and one tied scheme matches the
  AGRF phenotype, the helper reruns `mlst --scheme <matching>` and records the
  resolved call
- if no phenotype-matching tied scheme exists, the resolved call remains the
  automatic call

Reviewed outputs include:

- `mlst_review.tsv`
- `AGRF_samplesheet_with_results_mlst_reviewed.tsv`
- optional `AGRF_samplesheet_with_results_post_review.tsv`

## Gadi Environment Assumptions

The current `gadi` backend assumes:

- PBS Pro scheduler
- module environment with:
  - `nextflow`
  - `singularity`
  - `R`
- writable scratch space under `/scratch/<project>/<user>/...`

## Site Config Entry Point

All shared Gadi paths should be set through:

- `config/sites/gadi.local.env`

Create it from:

```bash
cp config/sites/gadi.env.example config/sites/gadi.local.env
```

That file is the intended place to define the shared database paths and site
defaults before distribution.
