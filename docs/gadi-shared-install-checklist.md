# Gadi Shared Install Checklist

Use this checklist when setting up a shared `agar-bactopia-pipeline` checkout on
Gadi for lab-wide use.

## Shared Project Layout

Recommended shared locations:

```text
/g/data/rg42/
  agar-bactopia-pipeline/
  bactopia/
  bactopia/kraken_indices/
  ps1744/bactopia_datasets_custom/
```

Optional shared external references:

```text
/g/data/rg42/custom_bactopia_refs/fimtyper/
```

## What Must Be In The Shared Project

The shared checkout should contain the full repo:

- `bin/agar-bactopia`
- `wrappers/submit.gadi.sh`
- `config/defaults.env`
- `config/sites/gadi.env.example`
- `config/sites/gadi.local.env`
- `scripts/`
- `README.md`
- `docs/runtime-dependencies.md`

Do not copy only selected scripts. Keep the whole repo together.

## What Must Exist Outside The Repo

These are required runtime dependencies and should be available on Gadi:

- shared Bactopia install
- shared datasets/custom cache
- shared Kraken2/Bracken DB
- shared FimTyper pipeline/config if not vendored into the repo
- module environment with `nextflow`, `singularity`, and `R`
- writable scratch locations for users
- optional Miniforge/Conda MLST review environment

## Gadi Setup Steps

1. Clone the repo into the shared Gadi location.

```bash
cd /g/data/rg42
git clone <repo-url> agar-bactopia-pipeline
cd /g/data/rg42/agar-bactopia-pipeline
```

2. Review the shared live config:

```bash
vi config/sites/gadi.local.env
```

3. Confirm these paths are correct in `config/sites/gadi.local.env`:

- `BACTOPIA_PIPELINE`
- `DATASETS_CACHE`
- `KRAKEN2_DB`
- `NEXTFLOW_CONFIG`
- `KLEBORATE_COMPAT_SCRIPT`
- `FIMTYPER_PIPELINE`
- `FIMTYPER_CONFIG`
- `MERGE_FIMTYPER_SCRIPT`
- `SING_CACHE`

4. Confirm the required software/modules exist on Gadi:

```bash
module avail nextflow
module avail singularity
module avail R
```

5. Test the public CLI help:

```bash
./bin/agar-bactopia
./wrappers/submit.gadi.sh --help
```

6. Run one small test submission:

```bash
./bin/agar-bactopia submit gadi \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

7. If needed, enable the extra tool bundle:

```bash
./bin/agar-bactopia submit gadi --additional-tools yes \
  /scratch/rg42/AGAR/raw_data/2025/B07/AGRF_CAGRF26050180_AAHJ2FTM5 \
  /scratch/rg42/AGAR/metadata/2025/B07 \
  /scratch/rg42/AGAR/intermediates/2025/B07 \
  50
```

## Notes

- `config/sites/gadi.local.env` is the real shared config for the Gadi install.
- Users should only need to pass raw-data, metadata, and results paths plus an
  optional additional-tools choice.
- Large reference data and databases should stay outside the repo and be
  referenced from `gadi.local.env`.
