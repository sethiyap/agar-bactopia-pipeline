# agar-bactopia-pipeline

AGAR-compatible Bactopia packaging with a single public entrypoint,
site-specific submission wrappers, and compatibility fixes for cases where
stock Bactopia output was not operationally consistent with AGAR review.

## Motivation

This package exists because stock `bactopia v3.2.1` was close to the AGAR
workflow, but not reliably consistent enough for routine interpretation on
Gadi.

The main gap was not just software versioning. In practice, AGAR needed tighter
control over MLST database provenance, because different bundled PubMLST
snapshots could produce calls that disagreed with phenotype expectations and
external cross-checks. That made database choice, review follow-up, and output
traceability operational requirements rather than optional extras.

The package also carries a few workflow-level compatibility fixes that AGAR
needed in routine use:

- patched MLST database handling and provenance tracking
- review-driven MLST follow-up for flagged isolates
- Kleborate compatibility shims for the expected working behavior
- standalone FimTyper integration and merge-back into project summaries
- stable launcher, site config, and AGAR-facing mapped outputs

So `agar-bactopia-pipeline` is best understood as an AGAR-compatible
distribution of Bactopia rather than a completely separate biological pipeline.

## Clone And Install On A Server

Example shared install on Gadi:

```bash
cd /g/data/rg42
git clone https://github.com/sethiyap/agar-bactopia-pipeline.git agar-bactopia-pipeline
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
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia
/g/data/rg42/agar-bactopia-pipeline/wrappers/submit.gadi.sh --help
```

For other servers, keep the same repo layout and add a site config plus wrapper
for that scheduler/backend, for example `slurm`.

## Current backend

- `gadi` submit wrapper
- PBS batch orchestration
- shared Bactopia/Kraken/datasets config through a site env file

## Submit On Gadi

Public entrypoint:

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi [OPTIONS] RAW_FASTQ_DIR METADATA_DIR RESULTS_ROOT [BATCH_SIZE]
```

Supported options:

- `--additional-tools yes|no`
  Turns the extra tool bundle on or off for this submission.
- `--is-agar-project auto|1|0`
  Controls AGAR auto-detection. Use `1` to force AGAR normalization and AGAR-only
  FOFN filtering, `0` to skip AGAR-specific handling, or `auto` to use path-based
  detection.
- `--site-config /path/to/gadi.local.env`
  Uses a different site env file instead of the default
  `/g/data/rg42/agar-bactopia-pipeline/config/sites/gadi.local.env`.
- `--mail-user you@example.org`
  Overrides `PBS_MAIL_USER` for this submission only.
- `--mail-options ae`
  Overrides `PBS_MAIL_OPTIONS` for this submission only. If you pass
  `--mail-user` without `--mail-options`, the wrapper defaults to `ae`.
- `--help`
  Prints the wrapper usage message.

Positional arguments:

- `RAW_FASTQ_DIR`
  Directory containing the input FASTQ files.
- `METADATA_DIR`
  Directory containing exactly one `*_samplesheet.txt` and optionally
  `samplesheet.fofn`.
- `RESULTS_ROOT`
  Output root for batches, consolidated results, review outputs, and workbook.
- `BATCH_SIZE`
  Optional batch size. If omitted, the wrapper uses `BATCH_SIZE_DEFAULT` from
  config, otherwise `50`.

Examples:

Default submission:

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

Enable the additional tools bundle:

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  --additional-tools yes \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

Force non-AGAR mode for mixed or non-AGAR folders:

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  --is-agar-project 0 \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

Use a different site config:

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  --site-config /g/data/rg42/agar-bactopia-pipeline/config/sites/gadi.local.env \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

Override PBS mail settings for one submission:

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  --mail-user your.name@example.org \
  --mail-options ae \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

## Quick start on Gadi

1. Copy the site config:

```bash
cp config/sites/gadi.env.example config/sites/gadi.local.env
```

2. Edit `config/sites/gadi.local.env` if your shared paths differ.

3. Submit:

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

## Metadata Sheet Requirements

The submit wrapper expects exactly one metadata sheet matching
`*_samplesheet.txt` under `METADATA_DIR`, unless you set `AGRF_SHEET_PATH`
explicitly.

The default batch family prefix is now `batch_bactopia`, so batch outputs are
written under paths such as `batch_bactopia_001`,
`batch_bactopia_001_tools`, and `batch_bactopia_consolidated` unless you
override `BATCH_PREFIX`.

Required metadata columns:

- `Sample name`: sample identifier used to join metadata back onto the
  consolidated Bactopia outputs
- `Comments`: free-text phenotype or lab note field used by the MLST review
  logic

For non-AGAR projects, sample names are not rewritten by the launcher. When
`IS_AGAR_PROJECT=0` or auto-detection resolves the input as non-AGAR, the
wrapper skips `normalize_agar_fastq_sample_names.sh` and goes straight to FOFN
creation or validation.

For AGAR projects, the built-in FOFN creator keeps only sample prefixes that
match `AGAR_SAMPLE_REGEX`, reports the skipped sample prefixes, and excludes
those other FASTQs from `samplesheet.fofn`. The default AGAR regex is
`^[0-9]{2}GNB-[0-9]+R?$`, so mixed folders do not carry non-AGAR sample names
forward unless you provide a custom `samplesheet.fofn` or override the regex
explicitly.

At the public wrapper layer you can force the mode with
`--is-agar-project auto|1|0`, for example `--is-agar-project 0` for non-AGAR
or mixed folders that should skip AGAR normalization.

How non-AGAR sample names are managed:

- if the launcher creates `samplesheet.fofn`, the sample name is taken as-is
  from each FASTQ basename before the first underscore in `*_R1.fastq.gz`
- if you provide an existing `samplesheet.fofn`, its `sample` values are used
  as provided
- in both cases, the metadata `Sample name` column must match the final sample
  names in the FOFN because no AGAR-specific renaming is applied

All other metadata columns are ignored by the metadata-mapping step. They may
still be kept in your source sheet for lab bookkeeping, but they are not
required for downstream processing by this pipeline.

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

If `AGRF_samplesheet_with_results_mlst_reviewed.tsv` is present, it is the
preferred reviewed output; otherwise use
`AGRF_samplesheet_with_results.tsv`.

When `RUN_EXPORT_RESULTS_WORKBOOK=1`, the launcher submits
`run_export_bactopia_results_workbook.pbs` after mapping and optional MLST
review. The exporter prefers
`AGRF_samplesheet_with_results_mlst_reviewed.tsv` when present and otherwise
falls back to `AGRF_samplesheet_with_results.tsv`.

Common examples:

```bash
# test one batch
BATCH_IDS=005 BATCH_LIMIT=1 \
./bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50

# start from batch 3
BATCH_START=3 BATCH_LIMIT=2 \
./bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50

# send PBS email notifications for this run only
./bin/agar-bactopia submit gadi \
  --mail-user your.name@example.org \
  --mail-options ae \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50

# postprocess only: consolidate + review + workbook export
POSTPROCESS_ONLY=1 \
RUN_CONSOLIDATE=1 \
RUN_MLST_REVIEW=1 \
RUN_EXPORT_RESULTS_WORKBOOK=1 \
./bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

In `POSTPROCESS_ONLY=1` mode, the trailing `50` does not limit the work to 50
samples. Consolidation runs across all batch directories already present under
the selected `RESULTS_ROOT`.

The launcher now runs an inode preflight against `RESULTS_ROOT` before
submission. On Gadi scratch it checks filesystem inode headroom and also looks
for project scratch quota issues via `lquota` or `nci_account`. Set
`CHECK_INODE_QUOTA=0` to skip it, or tune `INODE_FS_MIN_FREE_COUNT`,
`INODE_FS_MIN_FREE_PCT`, and `PROJECT_INODE_MAX_USE_PCT`.
An inode limit is a file-count limit, not a size limit, so you can hit it even
when there is still disk space left. If this check fails on Gadi, clean up old
batch result folders, `work/` directories, and other no-longer-needed files
under your project scratch area such as `/scratch/rg42/...`.

How to get rid of an inode overload error on Gadi:

- check whether the problem is filesystem inode headroom or project quota:
  `df -Pi /scratch/rg42/...`, `lquota`, and `nci_account -P rg42`
- remove old small-file-heavy scratch directories first, especially stale
  Nextflow `work/` trees, old `batch_bactopia_*` result folders, and abandoned
  temporary outputs under your previous `RESULTS_ROOT` paths
- if the run has already finished and you only need the deliverables, archive
  or transfer the final outputs elsewhere, then delete the older scratch copy
- if scratch is crowded across multiple runs, start the next submission with a
  fresh `RESULTS_ROOT` instead of reusing a directory full of old batch files
- do not rely on `CHECK_INODE_QUOTA=0` as the fix: that only skips the early
  guardrail and the job can still fail later if scratch inode usage is still
  too high

For retry work on a specific batch or subset, the batch submitter accepts:

- `BATCH_START` for a 1-based starting batch number
- `BATCH_LIMIT` for how many batches to submit from that point
- `BATCH_IDS` for an exact comma-separated subset such as `001` or
  `batch_bactopia_001,batch_bactopia_004`

## Mapped Result Columns

The metadata-mapped results table is derived from the sample names present in
the consolidated outputs. Your `*_samplesheet.txt` is then used to attach the
matching metadata columns for those processed samples only.

Always-present metadata columns:

- `Sample name`: sample identifier from the metadata sheet
- `Comments`: phenotype label or free-text lab note from the metadata sheet

Optional result columns added when the corresponding tool outputs exist:

- `mlst_scheme`: MLST scheme assigned to the sample
- `mlst_st`: MLST sequence type
- `mlst_profile`: MLST allele profile summary
- `kleborate_species`: species call from Kleborate
- `kleborate_species_match`: whether the Kleborate species agrees with the
  metadata phenotype/genus expectation
- `kleborate_st`: Kleborate sequence type when reported
- `kleborate_virulence_score`: Kleborate virulence score
- `kleborate_resistance_score`: Kleborate resistance score
- `kleborate_k_locus`: Klebsiella K locus call
- `kleborate_k_type`: Klebsiella capsule type derived from the K locus
- `kleborate_o_locus`: Klebsiella O locus call
- `kleborate_o_type`: Klebsiella O antigen type derived from the O locus
- `fimtyper_fimtype`: FimTyper fimbrial type call
- `fimtyper_identity`: identity score or percent identity reported by FimTyper
- `abritamr_beta_lactam`: beta-lactam resistance summary from abritAMR
- `abritamr_esbl`: ESBL resistance summary from abritAMR
- `abritamr_carbapenemase`: carbapenemase resistance summary from abritAMR
- `abritamr_quinolone`: quinolone resistance summary from abritAMR
- `abritamr_sulfonamide`: sulfonamide resistance summary from abritAMR
- `plasmidfinder_replicon`: plasmid replicon summary from PlasmidFinder
- `plasmidfinder_plasmid`: plasmid call or summary from PlasmidFinder
- `bracken_primary_species`: top Bracken species assignment
- `bracken_primary_species_abundance`: abundance for the top Bracken species
- `bracken_secondary_species`: second-ranked Bracken species assignment
- `bracken_secondary_species_abundance`: abundance for the second-ranked Bracken species
- `bracken_unclassified_abundance`: Bracken abundance assigned as unclassified

Review columns:

- `review_required`: `yes` when the MLST result needs manual or standalone
  review, otherwise `no`
- `review_reason`: explanation for why the sample was flagged
- `mlst_review_note`: present in the reviewed mapped TSV; explains how the
  standalone MLST review resolved, or failed to resolve, the flagged sample

If a reviewed table is available, the standalone MLST values are written back
into `mlst_scheme`, `mlst_st`, and `mlst_profile` in the reviewed TSV.

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
