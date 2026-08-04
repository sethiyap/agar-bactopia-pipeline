# Setup Guide: Non-Gadi Systems (Slurm / Generic Linux)

This guide is for running the pipeline on a **Slurm cluster or another Linux
machine** — anywhere that is not Gadi. Cloning the repo is not enough by itself:
you must also provide the external tools and databases the wrappers expect.

Once setup is done, running the pipeline is the same for everyone — see the main
[README](../README.md) for the universal command, metadata sheet, FOFN, and
outputs. Only the backend word changes (`submit slurm` instead of `submit gadi`).

There are **two** ways to run off Gadi:

- **`submit slurm`** — your cluster has a working Slurm scheduler (jobs go to `sbatch`).
- **`submit local`** — no scheduler (or Slurm is down): every stage runs on the
  current machine, and Bactopia's processes run with Nextflow's local executor.
  See [No Scheduler? Use The Local Backend](#no-scheduler-use-the-local-backend).

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

## No Scheduler? Use The Local Backend

Use `submit local` when the host has **no working job scheduler** — either there
is no Slurm/PBS at all, or (as on Firefly) Slurm is down so `sbatch` fails. The
local backend:

- runs every pipeline stage **on the current machine, in order** (no `qsub`/`sbatch`);
- drives Bactopia with Nextflow's **local executor** (via
  `scripts/nextflow.local.all_tools.config`, `executor = 'local'`), so Bactopia's
  own processes are local subprocesses too — nothing is ever submitted;
- uses tools from `PATH`/conda instead of environment modules (`USE_MODULES=0`).

Stages run sequentially (one batch at a time); parallelism happens *within* each
stage via Nextflow (`LOCAL_MAX_FORKS`). Per-stage output goes to log files under
the results/log directory. It is simpler and slower than a real cluster — fine
for trial runs and small batches on one host.

### Prerequisites on PATH

`nextflow`, a container engine (`singularity` or `apptainer`), `R`/`Rscript`, and
`python3` with `openpyxl` must all be on `PATH`. The MLST review env
(`MINIFORGE_ROOT`/`MLST_ENV` with `mlst`+`seqkit`) is still required (step 2).
Run everything from your activated conda env so the right tools are found.

### Set up the local site config

```bash
cp config/sites/local.env.example config/sites/local.local.env
```

Edit `config/sites/local.local.env` and set `BACTOPIA_PIPELINE`, `DATASETS_CACHE`,
`KRAKEN2_DB`, `MINIFORGE_ROOT`, `MLST_ENV`, and `SING_CACHE`. Already set for you:
`USE_MODULES=0`, `RUN_FIMTYPER=0` (FimTyper needs a scheduler-bound config), and
`NEXTFLOW_CONFIG` pointing at the local executor config. Optional resource caps:
`LOCAL_MAX_CPUS`, `LOCAL_MAX_MEMORY`, `LOCAL_MAX_FORKS`.

### Validate, then run

```bash
# from your activated conda env (e.g. `conda activate bactopia-3.2.0`)
./bin/agar-bactopia submit local \
  --site-config config/sites/local.local.env \
  --dry-run \
  /path/to/raw_fastqs \
  /path/to/metadata \
  "$HOME/bactopia_runs/project_001" \
  2
```

The dry run checks `nextflow`/`singularity`/`Rscript`/`python3` on PATH (not
`qsub`/`sbatch`). Fix anything flagged, then drop `--dry-run`. Everything else —
command shape, options, metadata sheet, FOFN, outputs — is identical to the main
[README](../README.md#running-the-pipeline).

### Firefly example

Firefly has `nextflow`, `singularity`, and `R` on PATH but no modulefiles, and a
`bactopia-3.2.0` conda env. So:

```bash
conda activate bactopia-3.2.0
cp config/sites/local.env.example config/sites/local.local.env
# edit BACTOPIA_PIPELINE / DATASETS_CACHE / KRAKEN2_DB / MINIFORGE_ROOT / MLST_ENV / SING_CACHE
./bin/agar-bactopia submit local --site-config config/sites/local.local.env --dry-run \
  ~/bactopia-trial-runs/raw ~/bactopia-trial-runs/metadata ~/bactopia-trial-runs/results 2
```

### Keep the run alive: tmux or screen

Unlike `submit gadi`/`submit slurm` (which hand jobs to a scheduler and return
immediately), `submit local` runs the whole pipeline as **one long-running
foreground process**. If you launch it over SSH and your connection drops, the
run is killed. On a remote host, always start it inside a detachable session —
`tmux` or `screen` — or with `nohup`.

**tmux:**

```bash
tmux new -s bactopia                 # start a named session
conda activate bactopia-3.2.0
./bin/agar-bactopia submit local \
  --site-config config/sites/local.local.env \
  ~/bactopia-trial-runs/raw ~/bactopia-trial-runs/metadata ~/bactopia-trial-runs/results 2
# detach and leave it running:  press Ctrl-b then d
# reconnect later:              tmux attach -t bactopia
# list sessions:                tmux ls
```

**screen:**

```bash
screen -S bactopia                   # start a named session
conda activate bactopia-3.2.0
./bin/agar-bactopia submit local \
  --site-config config/sites/local.local.env \
  ~/bactopia-trial-runs/raw ~/bactopia-trial-runs/metadata ~/bactopia-trial-runs/results 2
# detach:      press Ctrl-a then d
# reconnect:   screen -r bactopia
```

**nohup (no session manager available):**

```bash
nohup ./bin/agar-bactopia submit local \
  --site-config config/sites/local.local.env \
  ~/bactopia-trial-runs/raw ~/bactopia-trial-runs/metadata ~/bactopia-trial-runs/results 2 \
  > ~/bactopia-run.log 2>&1 &
tail -f ~/bactopia-run.log            # follow progress; Ctrl-c stops watching, not the run
```

Either way, per-stage Nextflow output is also written to log files under the
results/log directory, so you can `tail -f` those to watch an individual stage
even after detaching.
