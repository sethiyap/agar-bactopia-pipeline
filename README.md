# agar-bactopia-pipeline

Clean distributable AGAR Bactopia pipeline packaging with a single public
entrypoint and site-specific submission wrappers.

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
