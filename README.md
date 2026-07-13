# agar-bactopia-pipeline

`agar-bactopia-pipeline` is an AGAR-compatible packaging of Bactopia for HPC
use. It wraps submission, batching, result consolidation, metadata mapping,
MLST review, workbook export, and optional ST131Typer follow-up into one
workflow.

This README is organised as a simple step-by-step guide first. Detailed
reference sections come later.

## Quick Index

1. [What This Pipeline Does](#what-this-pipeline-does)
2. [Step-By-Step On Gadi](#step-by-step-on-gadi)
3. [Common Variations](#common-variations)
4. [Optional ST131Typer Workflow](#optional-st131typer-workflow)
5. [Important Outputs](#important-outputs)
6. [Troubleshooting And Operational Notes](#troubleshooting-and-operational-notes)
7. [Shared Install And Other Systems](#shared-install-and-other-systems)
8. [Slurm Usage](#slurm-usage)
9. [Repository Layout](#repository-layout)

## What This Pipeline Does

For a normal run, the pipeline:

1. reads FASTQ files from a raw-data folder
2. creates or reuses `samplesheet.fofn`
3. splits the run into manageable batches
4. submits Bactopia jobs
5. consolidates the batch outputs
6. maps the results back to the metadata sheet
7. runs MLST review for flagged samples
8. exports a final workbook

Compared with plain Bactopia, this repo also includes AGAR-facing workflow
behaviour such as metadata mapping, MLST review logic, optional FimTyper
integration, and optional ST131Typer append workflows.

## Step-By-Step On Gadi

Most users on Gadi only need the steps in this section.

### 1. Log In To Gadi And Work From Your Home Directory

Use your home directory as the place where you launch commands. This keeps the
default PBS `.o` and `.e` files out of the shared `/g/data` install.

```bash
ssh <nci_username>@gadi.nci.org.au
cd /home/562/<nci_username>
```

Important paths used by the shared `rg42` install:

- pipeline code: `/g/data/rg42/agar-bactopia-pipeline`
- AGAR raw data: `/scratch/rg42/AGAR/raw_data`
- AGAR metadata: `/scratch/rg42/AGAR/metadata`
- AGAR intermediates and results: `/scratch/rg42/AGAR/intermediates`

### 2. Get Your Data Onto Gadi

Use one of the two options below.

#### Option A: Download A New AGRF Delivery

```bash
cd /home/562/<nci_username>

/g/data/rg42/agar-bactopia-pipeline/scripts/download_agrf_to_gadi.sh \
  user@source.example.org:/path/to/AGRF_CAGRF26050180_AAHJ2FTM5 \
  2025 \
  B07
```

This creates:

```bash
/scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5
```

Useful notes:

- `REMOTE_SPEC` must be an rsync-compatible source such as `user@host:/path/to/delivery`
- the default destination root is `/scratch/rg42/AGAR/raw_data`
- use `DEST_ROOT=/absolute/path` if you need a different raw-data root
- use `DRY_RUN=1` first if you want to preview the transfer

#### Option B: Restore Existing Data From RDS

```bash
cd /home/562/<nci_username>

RDS_SFTP_USER=<your_rds_username> \
/g/data/rg42/agar-bactopia-pipeline/scripts/copy_RDS_to_GADI.sh \
  /rds/PRJ-AGAR/PRJ-AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/raw_data/2025/B07
```

This helper submits a PBS job. It does not run the transfer interactively in
your login shell.

Useful notes:

- `RDS_SRC` can be a file or a directory
- `GADI_DEST` is the destination parent directory on Gadi
- set `GADI_LOCAL_NAME` if you want a different name on Gadi
- if the RDS server disconnects with `Too many authentication failures`, set `RDS_SFTP_IDENTITY_FILE=$HOME/.ssh/<your_key>` so the helper uses only that key
- set `RDS_RESUME_DOWNLOAD=1` to resume partial downloads
- set `RDS_SKIP_IF_DEST_EXISTS=1` to skip work when the final target already exists
- set `DEBUG_LOG_DIR=/scratch/rg42/${USER}/transfer_logs` if you want the detailed transfer log in a known place
- set `PBS_LOG_DIR=/scratch/rg42/${USER}/pbs_logs` if you want PBS `.o` and `.e` files somewhere explicit

### 3. Prepare The Metadata Folder

Your metadata directory must contain exactly one `*_samplesheet.txt` unless you
set `AGRF_SHEET_PATH` explicitly.

Preferred metadata columns:

- `Sample name`
- `Comments`

What those columns mean:

- `Sample name` is the identifier used to join metadata back onto the processed results
- `Comments` is the free-text phenotype or organism note used by downstream review logic

If those headers are missing, the pipeline falls back to:

- first column as `Sample name`
- second column as `Comments`

Important behaviour:

- for non-AGAR projects, sample names are used as they are
- for AGAR projects, the launcher can normalize AGAR-style FASTQ names before FOFN creation
- if `samplesheet.fofn` already exists in `METADATA_DIR`, the launcher reuses it
- mapped output files reuse the metadata sheet prefix
- the prefix comes from the metadata filename before `_samplesheet.txt`
- for example, `B07_samplesheet.txt` gives the prefix `B07` and produces
  outputs such as `B07_samplesheet_with_results.tsv`

If you have changed the raw FASTQ folder and want the batch list rebuilt,
delete or move aside the old `samplesheet.fofn` first.

For non-AGAR runs:

- if the launcher creates `samplesheet.fofn`, the sample name is taken from the FASTQ basename before the first underscore in `*_R1.fastq.gz`
- if you provide your own `samplesheet.fofn`, its `sample` values are used as provided
- in both cases, metadata sample names must match the final FOFN sample names

### 4. Short Gadi Install

If you are using the shared `rg42` install, the pipeline is expected at:

```bash
/g/data/rg42/agar-bactopia-pipeline
```

If it has not been installed yet on Gadi, a short shared install is:

```bash
cd /g/data/rg42
git clone https://github.com/sethiyap/agar-bactopia-pipeline.git agar-bactopia-pipeline
cd /home/562/<nci_username>
```

That is enough for most users to understand where the shared pipeline lives.
The fuller shared-install notes stay in `Shared Install And Other Systems`
below.

### 5. Check The Site Config Once Per Install

If you are using the shared `rg42` install and it has already been configured,
you may not need to touch this step. If you are maintaining the install or
setting up a new copy, verify the site config first.

Create the local Gadi site config:

```bash
cp /g/data/rg42/agar-bactopia-pipeline/config/sites/gadi.env.example \
  /g/data/rg42/agar-bactopia-pipeline/config/sites/gadi.local.env
```

Then review `config/sites/gadi.local.env` and confirm these paths are correct:

- `BACTOPIA_PIPELINE`
- `DATASETS_CACHE`
- `KRAKEN2_DB`
- `NEXTFLOW_CONFIG`
- `KLEBORATE_COMPAT_SCRIPT`
- `FIMTYPER_PIPELINE`
- `FIMTYPER_CONFIG`
- `MERGE_FIMTYPER_SCRIPT`
- `SING_CACHE`

### 6. Submit The Pipeline

Normal Gadi submission:

```bash
cd /home/562/<nci_username>

/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

Command shape:

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  [OPTIONS] RAW_FASTQ_DIR METADATA_DIR RESULTS_ROOT [BATCH_SIZE]
```

Main public options:

- `--additional-tools yes|no`: turn the extra tool bundle on or off
- `--dry-run`: validate config, inputs, and dependencies without submitting jobs
- `--is-agar-project auto|1|0`: control AGAR-specific normalization and filtering
- `--site-config /path/to/gadi.local.env`: use a different site config file
- `--mail-user you@example.org`: override `PBS_MAIL_USER` for one submission
- `--mail-options ae`: override `PBS_MAIL_OPTIONS` for one submission

Arguments:

- `RAW_FASTQ_DIR`: folder containing the input FASTQ files
- `METADATA_DIR`: folder containing the metadata sheet and optionally `samplesheet.fofn`
- `RESULTS_ROOT`: where batch outputs, consolidated outputs, mapped TSVs, and workbook are written
- `BATCH_SIZE`: optional; if omitted, the config default is used, otherwise `50`

The default batch family prefix is `batch_bactopia`, so outputs usually appear
under names such as:

- `batch_bactopia_001`
- `batch_bactopia_001_tools`
- `batch_bactopia_consolidated`

### 7. What Happens After Submission

After you submit, the launcher usually does the following in order:

1. validates the raw-data and metadata inputs
2. creates or reuses `samplesheet.fofn`
3. splits the FOFN into batch files
4. submits one PBS job per batch
5. consolidates the batch outputs
6. maps the consolidated results back to the metadata sheet
7. runs MLST review for flagged samples when enabled
8. exports the results workbook when enabled

If you also turn on ST131Typer, that runs later in the chain after the core
workflow has finished.

### 8. Expected Output Structure

After a normal run, the main outputs live under `RESULTS_ROOT`.

Example for:

- `RESULTS_ROOT=/scratch/rg42/AGAR/intermediates/2025/B07`
- metadata file `B07_samplesheet.txt`

Typical structure:

```text
/scratch/rg42/AGAR/intermediates/2025/B07/
├── submit_agar_full_pipeline_YYYYMMDD_HHMMSS.log
├── batch_bactopia_001/
├── batch_bactopia_001_tools/
├── batch_bactopia_001_kleborate/
├── batch_bactopia_001_fimtyper/              # only if FimTyper is enabled
├── batch_bactopia_002/
├── batch_bactopia_002_tools/
├── batch_bactopia_consolidated/
│   ├── project_summary.tsv
│   ├── tool_processing_log.tsv
│   ├── results_main/
│   └── tools/
├── B07_samplesheet_with_results.tsv
├── B07_samplesheet_with_results_review_required.tsv
├── B07_samplesheet_with_results_mlst_reviewed.tsv   # present when MLST review runs
├── B07_samplesheet_with_results_post_review.tsv     # only if RUN_POST_REVIEW_MAP=1
├── mlst_review_standalone/                          # present when MLST review runs
│   ├── mlst_review.tsv
│   ├── mlst_review_missing.tsv
│   └── mlst_review_raw.log
├── B07_results.xlsx                                 # present when workbook export runs
├── B07_assemblies/                                  # present when assembly collection runs
└── B07_st131typer/                                  # present when ST131Typer runs
```

Notes:

- the first file to check is usually `submit_agar_full_pipeline_*.log`
- the final reviewed TSV is usually `B07_samplesheet_with_results_mlst_reviewed.tsv` when MLST review is enabled
- if that reviewed TSV is not present, use `B07_samplesheet_with_results.tsv`
- `B07_results.xlsx` is the default workbook name because it uses `basename(RESULTS_ROOT)`
- `B07_assemblies/` and `B07_st131typer/` are optional post-processing outputs

Batch shard files are created under `METADATA_DIR`, not under `RESULTS_ROOT`.

Example:

```text
/scratch/rg42/AGAR/metadata/2025/B07/
├── B07_samplesheet.txt
├── samplesheet.fofn
└── batches/
    ├── batch_bactopia_001.fofn
    ├── batch_bactopia_002.fofn
    └── ...
```

### 9. Copy Finished Results Back To RDS

After the run finishes on Gadi, use the packaged upload helper. The recommended
pattern is `export ...` followed by `qsub -V`.

This is safer than `qsub -v` when you need to pass larger environment values
such as long include lists.

Copy a finished results root:

```bash
export SRC_PATH=/scratch/rg42/AGAR/intermediates/2025/B07
export RDS_DEST=/rds/PRJ-AGAR/PRJ-AGAR/intermediates/2025/B07
export RDS_SFTP_USER=<your_rds_username>
# Optional when the RDS server reports "Too many authentication failures":
# export RDS_SFTP_IDENTITY_FILE=$HOME/.ssh/<your_private_key>
export DEBUG_LOG_DIR=/scratch/rg42/${USER}/transfer_logs
export RDS_UPLOAD_MANIFEST_DIR=/scratch/rg42/${USER}/.rds_transfer_manifests
mkdir -p "$DEBUG_LOG_DIR" "$RDS_UPLOAD_MANIFEST_DIR"
qsub -V /g/data/rg42/agar-bactopia-pipeline/scripts/jobsubmission_transfer_gadi_to_rds.pbs
```

Copy only the main deliverables first:

```bash
export SRC_PATH=/scratch/rg42/AGAR/intermediates/2025/B07
export RDS_DEST=/rds/PRJ-AGAR/PRJ-AGAR/intermediates/2025/B07
export RDS_SFTP_USER=<your_rds_username>
# Optional when the RDS server reports "Too many authentication failures":
# export RDS_SFTP_IDENTITY_FILE=$HOME/.ssh/<your_private_key>
export RDS_INCLUDE_DIRS='<prefix>_samplesheet_with_results.tsv,batch_bactopia_consolidated'
export DEBUG_LOG_DIR=/scratch/rg42/${USER}/transfer_logs
export RDS_UPLOAD_MANIFEST_DIR=/scratch/rg42/${USER}/.rds_transfer_manifests
mkdir -p "$DEBUG_LOG_DIR" "$RDS_UPLOAD_MANIFEST_DIR"
qsub -V /g/data/rg42/agar-bactopia-pipeline/scripts/jobsubmission_transfer_gadi_to_rds.pbs
```

Here, `<prefix>` means the part before `_samplesheet.txt` in your metadata
filename.

Transfer notes:

- `RDS_SFTP_USER` is required for uploads
- if the upload log shows `Too many authentication failures`, set `RDS_SFTP_IDENTITY_FILE=$HOME/.ssh/<your_key>` before `qsub -V`
- passwords are not stored in the script
- the wrapper defaults to scratch-backed debug and manifest locations if you do not override them
- by default, `_work` and `.nextflow.log*` are excluded from upload

## Common Variations

These are the most common changes to the standard submission command.

### Validate The Installation Before Submitting

Use `--dry-run` to check the current config, metadata, FOFN handling, and key
dependencies without submitting any scheduler jobs.

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  --dry-run \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

This mode checks the submission path and exits before the actual pipeline
starts.

### Turn On The Additional Tools Bundle

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  --additional-tools yes \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

### Force Non-AGAR Mode

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  --is-agar-project 0 \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

### Use A Different Site Config

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  --site-config /g/data/rg42/agar-bactopia-pipeline/config/sites/gadi.local.env \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

### Override PBS Mail Settings

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  --mail-user your.name@example.org \
  --mail-options ae \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

### Run Non-Kleborate Tools In Parallel

```bash
RUN_TOOLS_PARALLEL=1 \
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

If `RUN_TOOLS_PARALLEL` is unset, the default is `0`.

### Test A Small Subset

Run only one named batch:

```bash
BATCH_IDS=005 BATCH_LIMIT=1 \
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

Start later in the batch list:

```bash
BATCH_START=3 BATCH_LIMIT=2 \
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

### Rerun Postprocessing Only

Use this when the batches already exist and you only want consolidation,
review, or workbook export again.

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

In `POSTPROCESS_ONLY=1` mode, the trailing `50` does not limit the work to 50
samples. Consolidation runs across all batch directories already present under
`RESULTS_ROOT`.

## Optional ST131Typer Workflow

ST131Typer is optional and does not run by default.

To include it in the main submission:

```bash
ST131_TYPER_DIR=/g/data/rg42/ST131Typer \
RUN_ST131_TYPER=1 \
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

Important points:

- `RUN_ST131_TYPER=1` is required
- on `rg42` Gadi, `ST131_TYPER_DIR=/g/data/rg42/ST131Typer` is the usual shared location
- the core batch workflow finishes before ST131Typer is submitted
- `RUN_COLLECT_ASSEMBLIES=1` must stay enabled unless you point `ST131_TYPER_INPUT_DIR` at an existing assemblies folder

If you want the workbook first and the ST131 sheet appended later:

```bash
ST131_TYPER_DIR=/g/data/rg42/ST131Typer \
RUN_ST131_TYPER=1 \
ST131_APPEND_AFTER_WORKBOOK=1 \
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

If you already have an assemblies folder and just want to append the ST131
summary into an existing workbook:

```bash
ST131_TYPER_DIR=/g/data/rg42/ST131Typer \
./scripts/submit_st131typer_append.sh \
  /scratch/rg42/AGAR/intermediates/2025/B07/batch_bactopia_001_assemblies \
  /scratch/rg42/AGAR/intermediates/2025/B07/batch_bactopia_results.xlsx
```

If ST131Typer output already exists and matches the run, you can reuse it
during workbook export by setting `USE_EXISTING_ST131_TYPER=1`.

## Important Outputs

The most useful outputs for most users are:

- `batch_bactopia_001`, `batch_bactopia_002`, and so on: per-batch run folders
- `batch_bactopia_consolidated`: merged summary outputs across batches
- `<prefix>_samplesheet_with_results.tsv`: metadata plus mapped tool results
- `<prefix>_samplesheet_with_results_review_required.tsv`: rows flagged for MLST follow-up
- `<prefix>_samplesheet_with_results_mlst_reviewed.tsv`: preferred final reviewed TSV when present
- final workbook under `RESULTS_ROOT`: exported Excel summary

Common metadata and review columns:

- always expected from metadata: `Sample name`, `Comments`
- common mapped result fields: MLST, Kleborate, FimTyper, abritAMR, PlasmidFinder, Bracken
- common review fields: `review_required`, `review_reason`, `mlst_review_note`

If `<prefix>_samplesheet_with_results_mlst_reviewed.tsv` exists, use that as
the preferred reviewed table. If it does not exist, use
`<prefix>_samplesheet_with_results.tsv`.

## Troubleshooting And Operational Notes

### If The Batch Count Looks Wrong

The launcher builds batch files from `samplesheet.fofn`, not directly from the
number of FASTQ files in the raw-data directory.

Check these first:

- does `METADATA_DIR/samplesheet.fofn` already exist
- does the row count in `samplesheet.fofn` match the number of samples you expect
- did the launcher reuse an old FOFN from a previous run

If the FOFN is stale, move it aside, clear old batch shard files if needed, and
submit again.

### Inode Warnings On Gadi

The launcher runs an inode preflight against `RESULTS_ROOT`. An inode limit is
a file-count limit, not a disk-size limit.

If you hit an inode warning or failure on Gadi:

- check `df -Pi /scratch/rg42/...`
- check `lquota`
- check `nci_account -P rg42`
- delete stale small-file-heavy directories first, especially old `work/` trees and old batch result folders

The warning threshold is earlier than the hard-stop threshold. That gives you a
chance to clean scratch before the run fails later.

### MLST Review Logic

The review helper compares the phenotype note in `Comments` with the genus
implied by the MLST scheme.

A sample is flagged when there is:

- a phenotype-vs-MLST mismatch
- an ambiguous MLST profile
- MLST warning text that needs follow-up

The automatic MLST call is preserved as:

- `auto_scheme`
- `auto_st`
- `auto_profile`

Resolved review outputs are written as:

- `resolved_scheme`
- `resolved_st`
- `resolved_profile`
- `resolution_note`

### Transfer Notes

- `RDS_SFTP_USER` is required for packaged uploads
- the script does not store a password
- `RDS_IGNORE_MANIFEST=1` forces a reupload when files were already recorded in the manifest
- `RDS_INCLUDE_DIRS` is source-relative and works for exact paths, not shell globs

## Shared Install And Other Systems

### Shared Install On Gadi

If you are maintaining a shared install on Gadi:

```bash
cd /g/data/rg42
git clone https://github.com/sethiyap/agar-bactopia-pipeline.git agar-bactopia-pipeline
cd /home/562/<nci_username>
```

Create the site config:

```bash
cp /g/data/rg42/agar-bactopia-pipeline/config/sites/gadi.env.example \
  /g/data/rg42/agar-bactopia-pipeline/config/sites/gadi.local.env
```

Then verify the entrypoints:

```bash
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia
/g/data/rg42/agar-bactopia-pipeline/wrappers/submit.gadi.sh --help
```

Keep the shared code in `/g/data`, but keep launch commands, PBS logs, and
other mutable runtime files in user or scratch paths.

### Non-Gadi Or Non-`rg42` Linux Systems

If you are not using the shared `rg42` Gadi install, cloning this repo is not
enough by itself. You must also provide the external dependencies expected by
the wrappers.

Standalone MLST review helper requirements:

- `MINIFORGE_ROOT`
- `MLST_ENV`
- `mlst`
- `seqkit`

Example local setup:

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
`mlst` plus `seqkit` environment, and clones ST131Typer.

### ST131Typer Outside `rg42`

- the repo does not bundle `ST131Typer.sh`
- set `ST131_TYPER_DIR=/absolute/path/to/ST131Typer` if the clone lives elsewhere
- or set `ST131_TYPER_SCRIPT=/absolute/path/to/ST131Typer.sh`
- if ST131Typer depends on `seqkit`, make sure the same environment has `seqkit` on `PATH`

Minimal verification:

```bash
test -f /absolute/path/to/ST131Typer.sh
source "$MINIFORGE_ROOT/etc/profile.d/conda.sh"
conda activate "$MLST_ENV"
command -v mlst
command -v seqkit
```

## Slurm Usage

For Linux sites that use Slurm instead of PBS:

```bash
./bin/agar-bactopia submit slurm \
  --site-config config/sites/slurm.local.env \
  /path/to/raw_fastqs \
  /path/to/metadata \
  /scratch/$USER/bactopia_runs/project_001 \
  50
```

First-time Slurm setup:

```bash
cp config/sites/slurm.env.example config/sites/slurm.local.env
```

Check the Slurm site config and verify paths such as:

- `BACTOPIA_PIPELINE`
- `DATASETS_CACHE`
- `KRAKEN2_DB`
- `NEXTFLOW_CONFIG`
- `FIMTYPER_PIPELINE`
- `FIMTYPER_CONFIG`
- `MINIFORGE_ROOT`
- `MLST_ENV`
- `SING_CACHE`

Optional Slurm settings include:

- `SLURM_PARTITION`
- `SLURM_ACCOUNT`
- `SLURM_CLUSTER_OPTIONS`

The public options are the same as the Gadi backend:

- `--additional-tools`
- `--dry-run`
- `--is-agar-project`
- `--site-config`
- `--mail-user`
- `--mail-options`

## Repository Layout

- `bin/agar-bactopia`: public command-line entrypoint
- `wrappers/submit.gadi.sh`: PBS Pro submission wrapper for Gadi
- `wrappers/submit.slurm.sh`: generic Slurm submission wrapper
- `config/defaults.env`: scheduler-agnostic defaults
- `config/sites/`: site-specific configuration files
- `scripts/`: helper scripts and job wrappers
- `docs/runtime-dependencies.md`: bundled versus external dependency notes
- `docs/gadi-shared-install-checklist.md`: shared Gadi deployment checklist
