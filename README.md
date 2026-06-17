# agar-bactopia-pipeline

AGAR-compatible Bactopia packaging with a single public entrypoint,
site-specific submission wrappers, and compatibility fixes for cases where
stock Bactopia output was not operationally consistent with AGAR review.

## Motivation

This package was created because native `bactopia v3.2.1` was not consistently
compatible with the AGAR interpretation workflow on Gadi, especially when the
bundled typing databases disagreed with phenotype expectations and external
cross-check tools.

The motivation is practical rather than architectural:

- AGAR needs the pipeline output to agree as closely as possible with phenotype
  labels and with the external tools the lab already trusts for spot checks
- stock Bactopia behavior was producing biologically important discrepancies
  that could not be explained away as simple rerun noise
- once those discrepancies were understood, the fixes were no longer just
  "run Bactopia"; they became a reproducible compatibility layer that needed to
  be packaged and documented

The clearest MLST example was `25GNB_0500`:

- phenotype data identified the isolate as Klebsiella
- native Bactopia MLST identified it as E. coli with low confidence
- Galaxy identified it as Klebsiella
- updating the `mlst` software version alone did not fix the discrepancy

Visual summary:

| Checkpoint | Result for `25GNB_0500` | Interpretation |
| --- | --- | --- |
| AGRF phenotype | `Klebsiella` | Expected biological label |
| Native `bactopia v3.2.1` MLST | `E. coli` with low confidence | Discordant with phenotype |
| Galaxy MLST cross-check | `Klebsiella` | Supports phenotype, not native Bactopia |
| Bactopia after `mlst` software update | discrepancy persisted | Software update alone was insufficient |
| AGAR-compatible patched MLST database | `Klebsiella` | Discrepancy resolved |

```text
AGRF phenotype says Klebsiella
            |
            v
Native Bactopia v3.2.1 MLST says E. coli (low confidence)
            |
            +--> Galaxy MLST says Klebsiella
            |
            +--> upgrade mlst software only: still discordant
            |
            v
Conclusion: the problem is not just the mlst executable
            |
            v
Root cause: bundled MLST database snapshot mismatch
            |
            v
AGAR-compatible fix: patch/control the MLST database bundle
            |
            v
Resolved AGAR-compatible output: Klebsiella
```

The key finding was that `mlst` software version is not the same thing as MLST
database version. Different environments were bundling different PubMLST
snapshots, and those database differences were driving the disagreement.

In other words, the original problem was not simply "Bactopia called the wrong
scheme". The problem was that stock Bactopia was coupled to an MLST database
snapshot that did not match the database context being used in Galaxy and other
validation workflows. That is why:

- upgrading `mlst` inside Bactopia did not automatically resolve the issue
- cross-validation on Galaxy still pointed to a different biological answer
- AGAR needed explicit control over the MLST database bundle, not just the
  `mlst` executable version

The patched AGAR-compatible workflow therefore treats MLST database provenance
as a first-class compatibility requirement. Missing schemes can be copied from a
working newer MLST database into the local Bactopia-compatible bundle, that
bundle can be rebuilt and reused for reruns, and the chosen MLST dataset and
database version can be reported back in the output metadata.

That led to AGAR-specific changes that native `bactopia v3.2.1` did not provide
out of the box:

- patched MLST database handling so the required missing schemes could be copied
  from a working newer MLST database into the local Bactopia-compatible bundle
- explicit tracking of MLST dataset/database provenance so the output records
  which patched database was actually used
- review-driven MLST follow-up so flagged isolates can be resolved against AGRF
  phenotype context instead of leaving low-confidence or ambiguous calls buried
  in the merged output

There was a second compatibility problem with Kleborate:

- the newer Bactopia Kleborate workflow could produce widespread `Not tested`
  output, including for Klebsiella isolates
- the expected output matched older `kleborate 2.3.2`
- the practical fix was to keep the newer Bactopia workflow wiring but run it
  through a compatibility shim that translates modern Bactopia-style arguments
  into the older working Kleborate CLI

There was also a workflow gap around FimTyper:

- FimTyper is not part of the stock Bactopia tool bundle in the form needed by
  AGAR
- the AGAR workflow therefore runs FimTyper as a separate Nextflow-compatible
  step after `results_main`, then merges those per-sample outputs back into the
  project summary tables

So `agar-bactopia-pipeline` is not a new biological pipeline so much as an
AGAR-compatible distribution of Bactopia with the compatibility pieces needed
to make the results operationally usable:

- stable launcher and site config
- patched MLST database workflow
- Kleborate compatibility shim
- standalone FimTyper integration
- AGRF mapping, MLST review, and workbook export as first-class outputs

In short, the package exists because native Bactopia was close, but not
sufficiently reliable for AGAR without these compatibility fixes and
workflow-level additions.

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
/g/data/rg42/agar-bactopia-pipeline/bin/agar-bactopia
/g/data/rg42/agar-bactopia-pipeline/wrappers/submit.gadi.sh --help
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

If the batch outputs already exist and you only want to rerun consolidation,
metadata mapping, MLST review, and workbook export, use:

```bash
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

For retry work on a specific batch or subset, the batch submitter accepts:

- `BATCH_START` for a 1-based starting batch number
- `BATCH_LIMIT` for how many batches to submit from that point
- `BATCH_IDS` for an exact comma-separated subset such as `001` or
  `batch_bactopia_001,batch_bactopia_004`

## Mapped Result Columns

The metadata-mapped results table is derived from your `*_samplesheet.txt`
file.

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
