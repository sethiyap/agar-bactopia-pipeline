# Setup Guide: Non-Gadi Systems (Slurm / Generic Linux)

This guide is for running the pipeline on a **Slurm cluster or another Linux
machine** — anywhere that is not Gadi. Cloning the repo is not enough by itself:
you must also provide the external tools and databases the wrappers expect.

Once setup is done, running the pipeline is the same for everyone — see the main
[README](../README.md) for the universal command, metadata sheet, FOFN, and
outputs. Only the backend word changes (`submit slurm` instead of `submit gadi`).

## 1. Prerequisites

The Slurm backend assumes a Linux host with:

- Slurm (`sbatch`)
- `nextflow`
- `singularity` or `apptainer`
- `R`
- writable scratch or project work space

Full list and per-backend assumptions:
[docs/runtime-dependencies.md](runtime-dependencies.md).

## 2. Install Optional Local Tools

The MLST review stage needs `mlst` + `seqkit` (in a conda env), and ST131Typer
needs its script. The packaged helper installs all three locally:

```bash
./scripts/install_optional_local_tools.sh
```

That installs Miniforge under `<repo_root>/.local`, creates a local `mlst` plus
`seqkit` environment, and clones ST131Typer. It prints the `MINIFORGE_ROOT`,
`MLST_ENV`, and `ST131_TYPER_SCRIPT` values to put in your site config.

Prefer to do it by hand? Minimal manual setup:

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

## 3. Install Bactopia + Datasets + Kleborate

Shared across all environments — follow the canonical guide:
[docs/bactopia-setup.md](bactopia-setup.md).

- clone the **Bactopia v3.2.0** source checkout (`BACTOPIA_PIPELINE`)
- obtain the custom datasets cache (`scripts/download_bactopia_datasets.sh`, or
  build your own); `DATASETS_CACHE` must point at a real cache before a run
- Kleborate runs inside Bactopia's container — no separate install

## 4. Create Your Slurm Site Config

```bash
cp config/sites/slurm.env.example config/sites/slurm.local.env
```

Edit `config/sites/slurm.local.env` and set the following. The scheduler is
selected by the `submit slurm` subcommand, not by a config key.

Path keys to point at your install:

- `BACTOPIA_PIPELINE`
- `DATASETS_CACHE`
- `KRAKEN2_DB`
- `NEXTFLOW_CONFIG` — use the Slurm variant, `scripts/nextflow.slurm.all_tools.config`
- `FIMTYPER_PIPELINE`
- `FIMTYPER_CONFIG` — use the Slurm variant (`fimtyper.slurm.config`)
- `MINIFORGE_ROOT` — from step 2 (default `$PIPELINE_ROOT/.local/miniforge3`)
- `MLST_ENV` — from step 2 (default `$PIPELINE_ROOT/.local/mlst_env`)
- `SING_CACHE` — writable scratch for Singularity images

Slurm-only settings you must set for your cluster:

- `SLURM_PARTITION`
- `SLURM_ACCOUNT`
- `SLURM_CLUSTER_OPTIONS`

Note: unlike the Gadi config, `CHECK_INODE_QUOTA` defaults to `0` (no inode
preflight) and there is no `${PROJECT}` segment in the scratch defaults.

## 5. ST131Typer Outside rg42

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

## 6. Validate, Then Run

```bash
./bin/agar-bactopia submit slurm \
  --site-config config/sites/slurm.local.env \
  --dry-run \
  /path/to/raw_fastqs \
  /path/to/metadata \
  /scratch/$USER/bactopia_runs/project_001 \
  50
```

Fix anything flagged, then drop `--dry-run` for the real run. The command shape,
options, metadata sheet, and FOFN are the same as on the main
[README](../README.md#running-the-pipeline); the public options are identical to
the Gadi backend (`--additional-tools`, `--dry-run`, `--is-agar-project`,
`--site-config`, `--mail-user`, `--mail-options`).
