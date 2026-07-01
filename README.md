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

## Access On Gadi

### Connecting To Gadi

Log in to Gadi with your NCI account, then move into the shared pipeline
install and AGAR working areas:

```bash
ssh <nci_username>@gadi.nci.org.au

cd /g/data/rg42/agar-bactopia-pipeline

# AGAR raw data, metadata, and intermediate processing roots
cd /scratch/rg42/AGAR
ls
```

Key Gadi paths used by this pipeline:

- pipeline code: `/g/data/rg42/agar-bactopia-pipeline`
- AGAR raw data root: `/scratch/rg42/AGAR/raw_data`
- AGAR metadata root: `/scratch/rg42/AGAR/metadata`
- AGAR intermediate processing root: `/scratch/rg42/AGAR/intermediates`

Typical Gadi workflow:

- log in to Gadi
- inspect or update the shared pipeline under `/g/data/rg42/agar-bactopia-pipeline`
- optionally download a new AGRF delivery into `/scratch/rg42/AGAR/raw_data/...`
- read batch inputs from `/scratch/rg42/AGAR/raw_data/...`
- read metadata from `/scratch/rg42/AGAR/metadata/...`
- write processing outputs under `/scratch/rg42/AGAR/intermediates/...`

### Downloading Data From AGRF

Download AGRF raw data onto Gadi:

The AGRF download helper defaults to `/scratch/rg42/AGAR/raw_data`, but that
raw-data destination root is configurable with `DEST_ROOT`.

```bash
cd /g/data/rg42/agar-bactopia-pipeline

./scripts/download_agrf_to_gadi.sh \
  user@source.example.org:/path/to/AGRF_CAGRF26050180_AAHJ2FTM5 \
  2025 \
  B07
```

That command creates:

```bash
/scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5
```

Notes:

- `REMOTE_SPEC` must be an rsync-compatible source such as
  `user@host:/path/to/delivery`
- the default destination root is `/scratch/rg42/AGAR/raw_data`
- if you want a different raw-data root, override `DEST_ROOT` with an absolute
  path, for example:
  `DEST_ROOT=/scratch/rg42/my_project/raw_data ./scripts/download_agrf_to_gadi.sh ...`
- if the source needs a custom SSH port or options, set `RSYNC_RSH`, for
  example `RSYNC_RSH="ssh -p 2222"`
- set `DRY_RUN=1` first if you want to preview the transfer
- the script is intended for raw-data delivery downloads only; metadata still
  belongs under `/scratch/rg42/AGAR/metadata/...`
- the metadata directory should contain a text file matching
  `*_samplesheet.txt`
- that metadata sheet must contain the columns `Sample name` and `Comments`
- `Sample name` must match the final sample ids used in the FOFN
- `Comments` should include the free-text phenotype or organism name used by
  the downstream MLST review and mapping steps

### Downloading Data From RDS

If the data already exists on the University of Sydney Research Data Store
(RDS), download it onto Gadi with the packaged restore helper.

This helper always submits a PBS job on Gadi. It does not run the transfer
interactively in the login shell.

```bash
cd /g/data/rg42/agar-bactopia-pipeline

RDS_SFTP_USER=<your_rds_username> \
./scripts/copy_RDS_to_GADI.sh \
  /rds/PRJ-AGAR/PRJ-AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/raw_data/2025/B07
```

That command creates:

```bash
/scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5
```

Notes:

- `RDS_SRC` can point to either a file or a directory on RDS
- `GADI_DEST` is the destination parent directory on Gadi
- when you run `./scripts/copy_RDS_to_GADI.sh ...`, the script submits a
  PBS job and prints the submitted job id
- if you want to rename the restored folder or file on Gadi, set
  `GADI_LOCAL_NAME`
- if you want to resume a partially completed download, keep
  `RDS_RESUME_DOWNLOAD=1`
- if you want to skip a restore when the final target already exists, set
  `RDS_SKIP_IF_DEST_EXISTS=1`
- if you want the detailed transfer log somewhere explicit, set
  `DEBUG_LOG_DIR=/scratch/rg42/${USER}/transfer_logs`
- if you want the PBS `.o` and `.e` files somewhere explicit, set
  `PBS_LOG_DIR=/scratch/rg42/${USER}/pbs_logs`
- if you are restoring AGAR raw data, the usual destination is
  `/scratch/rg42/AGAR/raw_data/<year>/<batch>`
- if you are restoring previous results or intermediates from RDS, point
  `GADI_DEST` at the matching location under `/scratch/rg42/AGAR/intermediates/...`

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
- `Comments`: free-text phenotype or organism name used by the MLST review
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

## Installing agar-bactopia-pipeline on Gadi

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

For other Linux servers, the repo now also ships a generic Slurm wrapper and
site-config template:

```bash
cp config/sites/slurm.env.example config/sites/slurm.local.env
./wrappers/submit.slurm.sh --help
```

Edit `config/sites/slurm.local.env` for your site before submitting.

## Quick start on Gadi

1. Copy the site config:

```bash
cp config/sites/gadi.env.example config/sites/gadi.local.env
```

2. Edit `config/sites/gadi.local.env` if your shared paths differ.

3. Submit:

```bash
cd /home/562/ps1744
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

## Submit On Gadi

Public entrypoint:

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi [OPTIONS] RAW_FASTQ_DIR METADATA_DIR RESULTS_ROOT [BATCH_SIZE]
```

Operational note:

- Run the public command from your home directory, for example
  `/home/562/ps1744`, rather than from `/g/data/rg42/agar-bactopia-pipeline`.
  That keeps any default PBS `.o`/`.e` files tied to your user area instead of
  cluttering the shared `/g/data` install.
- If you want the PBS `.o`/`.e` files somewhere explicit, set
  `PBS_LOG_DIR=/scratch/<project>/<user>/pbs_logs` before submission.

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
  config, otherwise `50`. The default split size keeps each PBS batch job
  small enough to manage on Gadi and makes partial reruns simpler if one batch
  fails. It is an operational default, not a biological threshold.

## Optional ST131Typer Run

ST131Typer does not run by default. If you want the pipeline to submit
`run_st131typer_from_assemblies.pbs`, you must explicitly set
`RUN_ST131_TYPER=1` on the submission command.

Brief install note:

- on `rg42` Gadi, point `ST131_TYPER_DIR` at the shared clone, for example
  `/g/data/rg42/ST131Typer`
- on other Linux systems, clone
  `https://github.com/JohnsonSingerLab/ST131Typer.git` and then set
  `ST131_TYPER_DIR=/absolute/path/to/ST131Typer`
- if you want the repo to install a local copy for you, run
  `./scripts/install_optional_local_tools.sh`

Example:

```bash
ST131_TYPER_DIR=/g/data/rg42/ST131Typer \
RUN_ST131_TYPER=1 \
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

Important requirements:

- `RUN_ST131_TYPER=1` is required. If you do not set it, no ST131Typer job is
  submitted.
- `RUN_COLLECT_ASSEMBLIES=1` must remain enabled because ST131Typer runs after
  the assemblies folder is created.
- if ST131Typer is installed outside the pipeline repo, define
  `ST131_TYPER_DIR=/absolute/path/to/ST131Typer`
- `ST131Typer.sh` must be available, by default at `<repo_root>/ST131Typer.sh`,
  or you must set
  `ST131_TYPER_SCRIPT=/absolute/path/to/ST131Typer.sh`.
- the standalone append helper also defaults `ST131_TYPER_SCRIPT` to
  `<repo_root>/ST131Typer.sh`, so you can run it from outside the repo checkout
  as long as that script exists in the cloned pipeline root
- for non-`rg42` or non-Gadi installs, see `For Non-Gadi And Non-rg42 Users`
  below for local installation guidance

If you only want to run ST131Typer later against an existing assemblies folder
and append its summary into the final workbook, use:

```bash
ST131_TYPER_DIR=/g/data/rg42/ST131Typer \
./scripts/submit_st131typer_append.sh \
  /scratch/rg42/AGAR/intermediates/2025/B07/batch_bactopia_001_assemblies \
  /scratch/rg42/AGAR/intermediates/2025/B07/batch_bactopia_results.xlsx
```

## Common Examples

### Default Submission

Submit a standard Gadi run with the default pipeline behavior.

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

### Enable The Additional Tools Bundle

Turn on the extra non-core typing and screening tools for the run.

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  --additional-tools yes \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

### Run Non-Kleborate Tools In Parallel

For faster completion, submit one non-Kleborate tool job per tool after
assembly.

```bash
RUN_TOOLS_PARALLEL=1 \
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

### Run Non-Kleborate Tools Sequentially

Keep the existing single bundled tools job instead of parallel per-tool jobs.

```bash
RUN_TOOLS_PARALLEL=0 \
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

If `RUN_TOOLS_PARALLEL` is unset, the default is `0`.

### Force Non-AGAR Mode

Skip AGAR-specific normalization and filtering for mixed or non-AGAR inputs.

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  --is-agar-project 0 \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

### Use A Different Site Config

Point the submitter at a non-default `gadi.local.env` file.

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  --site-config /g/data/rg42/agar-bactopia-pipeline/config/sites/gadi.local.env \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

### Override PBS Mail Settings

Send scheduler mail for one submission without changing shared defaults.

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  --mail-user your.name@example.org \
  --mail-options ae \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

### Test One Batch

Submit only a named batch when you want a small validation run.

```bash
BATCH_IDS=005 BATCH_LIMIT=1 \
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

### Start From Batch 3

Resume or retry from a later batch instead of rerunning from batch 1.

```bash
BATCH_START=3 BATCH_LIMIT=2 \
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

### Run Postprocess Only

Skip batch execution and rerun only consolidation, MLST review, and workbook
export on an existing `RESULTS_ROOT`.

```bash
POSTPROCESS_ONLY=1 \
RUN_CONSOLIDATE=1 \
RUN_MLST_REVIEW=1 \
RUN_EXPORT_RESULTS_WORKBOOK=1 \
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

### Run ST131Typer During The Main Submission

Submit ST131Typer after the assemblies folder is created as part of the main
pipeline dependency chain.

```bash
ST131_TYPER_DIR=/g/data/rg42/ST131Typer \
RUN_ST131_TYPER=1 \
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

### Append ST131Typer Summary To An Existing Workbook

Run ST131Typer separately against an existing assemblies folder and append its
summary sheet into an existing workbook.

```bash
ST131_TYPER_DIR=/g/data/rg42/ST131Typer \
./scripts/submit_st131typer_append.sh \
  /scratch/rg42/AGAR/intermediates/2025/B07/batch_bactopia_001_assemblies \
  /scratch/rg42/AGAR/intermediates/2025/B07/batch_bactopia_results.xlsx
```

## MLST Review And Discrepancy Resolution

The pipeline includes a review-driven standalone MLST follow-up for flagged
isolates.

Brief install note:

- the standalone MLST review helper needs `mlst` and `seqkit`
- on `rg42` Gadi, these usually come from the shared Miniforge install and
  shared `mlst_env`
- on other Linux systems, install Miniforge, create a Conda environment with
  `mlst` and `seqkit`, then point the pipeline at `MINIFORGE_ROOT` and
  `MLST_ENV`
- if you want the repo to install local copies for you, run
  `./scripts/install_optional_local_tools.sh`

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

In `POSTPROCESS_ONLY=1` mode, the trailing `50` does not limit the work to 50
samples. Consolidation runs across all batch directories already present under
the selected `RESULTS_ROOT`.

If you do not set `BATCH_LIMIT`, the launcher now submits all batch files
implied by `samplesheet.fofn` and `BATCH_SIZE`. For example, about 284 samples
at `BATCH_SIZE=50` yields 6 batch files, and about 150 samples yields 3 batch
files.

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
- `BATCH_LIMIT` for how many batches to submit from that point when you want a
  smaller subset than the default all-batches behavior
- `BATCH_IDS` for an exact comma-separated subset such as `001` or
  `batch_bactopia_001,batch_bactopia_004`

## Mapped Results Output

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

## For Non-Gadi And Non-`rg42` Users

If you are not using the shared `rg42` Gadi install, the clone alone is not
enough to provide every external helper. The repo does not auto-install these
tools on clone; install them only if they are not already available at your
site.

Standalone MLST review helper:

- `run_review_mlst_from_tsv.sh` expects a Miniforge/Conda activation root via
  `MINIFORGE_ROOT`
- the activated environment at `MLST_ENV` must provide both `mlst` and `seqkit`
- on `rg42` Gadi these usually point at the shared
  `/g/data/<PROJECT>/bactopia_datasets/miniforge3` and
  `/g/data/<PROJECT>/bactopia_datasets/envs/mlst_env`

Example Miniforge + MLST environment setup on a generic Linux host:

```bash
MINIFORGE_ROOT=$PWD/miniforge3
MLST_ENV=$PWD/mlst_env

mkdir -p "$MINIFORGE_ROOT"
curl -L -o /tmp/Miniforge3.sh \
  https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh
bash /tmp/Miniforge3.sh -b -p "$MINIFORGE_ROOT"

source "$MINIFORGE_ROOT/etc/profile.d/conda.sh"
conda create -y -p "$MLST_ENV" -c conda-forge -c bioconda mlst seqkit
conda activate "$MLST_ENV"

mlst --version
seqkit version
```

If you want the repo to manage local copies for you, use:

```bash
./scripts/install_optional_local_tools.sh
```

That helper installs Miniforge under `<repo_root>/.local`, creates a local
`mlst` + `seqkit` Conda environment, clones
`https://github.com/JohnsonSingerLab/ST131Typer.git`, and links
`<repo_root>/ST131Typer.sh` to the cloned script so the existing wrapper
defaults keep working.

ST131Typer helper:

- the ST131Typer steps do not bundle `ST131Typer.sh`
- if ST131Typer is installed in its own folder, set
  `ST131_TYPER_DIR=/absolute/path/to/ST131Typer`
- by default the launchers expect it at `<repo_root>/ST131Typer.sh`
- if you keep it elsewhere, set `ST131_TYPER_SCRIPT=/absolute/path/to/ST131Typer.sh`
- if the ST131Typer script itself depends on `seqkit`, make sure the same shell
  or Conda environment used to run ST131Typer has `seqkit` on `PATH`

Minimal verification for non-`rg42` installs:

```bash
test -f /absolute/path/to/ST131Typer.sh
source "$MINIFORGE_ROOT/etc/profile.d/conda.sh"
conda activate "$MLST_ENV"
command -v mlst
command -v seqkit
```

## Submit On Slurm

Public entrypoint:

```bash
./bin/agar-bactopia submit slurm [OPTIONS] RAW_FASTQ_DIR METADATA_DIR RESULTS_ROOT [BATCH_SIZE]
```

First-time setup:

```bash
cp config/sites/slurm.env.example config/sites/slurm.local.env
```

Edit `config/sites/slurm.local.env` for your site paths, especially:

- `BACTOPIA_PIPELINE`
- `DATASETS_CACHE`
- `KRAKEN2_DB`
- `NEXTFLOW_CONFIG`
- `FIMTYPER_PIPELINE`
- `FIMTYPER_CONFIG`
- `MINIFORGE_ROOT`
- `MLST_ENV`
- `SING_CACHE`
- optional `SLURM_PARTITION`
- optional `SLURM_ACCOUNT`
- optional `SLURM_CLUSTER_OPTIONS`

Example:

```bash
./bin/agar-bactopia submit slurm \
  --site-config config/sites/slurm.local.env \
  /path/to/raw_fastqs \
  /path/to/metadata \
  /scratch/$USER/bactopia_runs/project_001 \
  50
```

The public options are the same as `submit gadi`: `--additional-tools`,
`--is-agar-project`, `--site-config`, `--mail-user`, and `--mail-options`.

### Packaged Backends

- `gadi`: PBS Pro wrapper and Gadi-oriented shared-path defaults
- `slurm`: generic Slurm wrapper and Linux-oriented site template

Both backends still assume a Linux execution site with Nextflow plus
Singularity or Apptainer available. Cloning the repo on macOS is fine for code
inspection and editing, but the packaged pipeline runners are not a native
macOS execution target.

## Layout

- `bin/agar-bactopia`: public CLI
- `wrappers/submit.gadi.sh`: Gadi-facing submission wrapper
- `wrappers/submit.slurm.sh`: generic Slurm-facing submission wrapper
- `config/defaults.env`: scheduler-agnostic defaults
- `config/sites/`: site-specific shared paths
- `scripts/`: internal pipeline helpers plus scheduler job wrappers
- `docs/runtime-dependencies.md`: bundled-vs-external runtime dependency audit
- `docs/gadi-shared-install-checklist.md`: shared Gadi deployment checklist

## Next steps

- move more runtime assumptions out of PBS scripts into site configs
- add install and validation docs under `docs/`
