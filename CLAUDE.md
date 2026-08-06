# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Nextflow pipeline, written in the strict (V2) Nextflow language, that filters SNVs (single nucleotide variants) using [`htsjdk-tools`](https://github.com/crukci-bioinformatics/htsjdk-tools), then converts both SNVs and indels to MAF format using [vcf2maf](https://github.com/mskcc/vcf2maf) (which runs VEP annotation internally), and merges the results into a single MAF per sample.

## Smoke Test (stub run)

```bash
# One-time fixture setup (requires bgzip + tabix from the seqware conda env)
conda run -n seqware bash examples/setup_test_fixtures.sh

# Run the stub smoke test.
# Note the profile: the `standard` profile caps the local executor at 8 GB, but
# `calculateSNVMetrics` requests 24 GB, so the stub run aborts on `standard`.
nextflow run main.nf -stub -params-file examples/test_params.yml -profile bigserver
```

All processes have `stub:` blocks that `touch` their declared outputs instead of running the real tools. This validates channel wiring, input CSV parsing, and file-path/index resolution without needing GATK, VEP, or real sequencing data.

## Running the Pipeline

```bash
# Standard local run
nextflow run main.nf -params-file params.yml

# With a specific profile (standard, bigserver, cluster, epyc)
nextflow run main.nf -params-file params.yml -profile cluster

# Enable Sarek output directory structure
nextflow run main.nf -params-file params.yml --sarek_output true

# Resume a previous run
nextflow run main.nf -params-file params.yml -resume
```

## Building the Container

Commands are in [container/Makefile](container/Makefile):

```bash
cd container

# Build Docker image (default tag: latest)
make build

# Build with a specific version
make build version=0.1

# Build and push to Docker Hub
make release version=0.1

# Build Singularity image from local Docker image
make singularity version=0.1
```

The container is published as `crukcibioinformatics/filter-snvs`.

## Required Parameters

Specify in a params YAML file:
- `reference_fasta` — path to reference genome `.fa` or `.fasta` (must have co-located `.fai` and `.dict` files)
- `vep_cache` — path to VEP cache directory
- `species` — e.g. `"mus_musculus"` or `"homo_sapiens"`
- `assembly` — e.g. `"GRCm38"` or `"GRCh38"`

All parameters are declared with types in the `params` block at the top of [main.nf](main.nf).
Nextflow validates them itself: a missing required parameter or an undeclared parameter aborts the
run before any task is submitted. Defaults live in [nextflow.config](nextflow.config); the optional
parameters (`intervals`, `vcf_dir`, `bam_dir`) take their `null` default from `main.nf` and must not
be set to `null` in the config, because a config assignment counts as the parameter being specified.

## Input CSV Format

The `inputs_csv` file (default: `inputs.csv`) must have columns: `id`, `vcf`, `tumour_bam`, and optionally `normal_bam`. VCF files must be gzip-compressed (`.vcf.gz`) with a `.tbi` index. BAM files must have a `.bai` index (either `file.bai` or `file.bam.bai`).

## Pipeline Architecture

### Layout

```
main.nf                            params block, includes, entry workflow, output block
modules/get_sample_names.nf        one process per file
modules/select_rest.nf
modules/calculate_snv_metrics.nf
modules/apply_snv_filters.nf
modules/vcf_to_maf.nf
modules/merge_mafs.nf
functions/inputs.nf                inputs CSV row parsing and validation
functions/indexes.nf               index file resolution
```

### Workflow (`main.nf`)

The entry workflow has a `main:` section that runs these processes in order, and a `publish:`
section that names the channels to be published:

1. **`getSampleNames`** — extracts tumour/normal sample names from BAM read group headers via `gatk GetSampleName`
2. **`selectRest`** — extracts non-SNP variants (indels etc.) using `gatk SelectVariants`; runs in parallel with SNV processing
3. **`calculateSNVMetrics`** — selects PASS SNPs then runs `calculate-snv-metrics` (from htsjdk-tools) to add allele count and mapping quality metrics to the VCF
4. **`applySnvFilters`** — applies `gatk VariantFiltration` using the `snv_filters` expressions, then selects only PASS variants
5. **`vcfToMaf`** — converts each filtered VCF (SNVs and indels separately) to MAF format using `vcf2maf.pl`, which runs VEP annotation internally; `vep_cache`, `species` and `assembly` are passed in as `val` process inputs rather than read from `params` inside the process. `--tumor-id` is the inputs CSV `id`, so `Tumor_Sample_Barcode` matches the output file names; `--normal-id` is the read group sample name from the normal BAM, as the CSV has no normal identifier column
6. **`mergeMafs`** — groups the SNV and indel MAFs by sample ID (`.groupTuple(size: 2)`) and concatenates them into a single `<id>.merged.maf` output file

### Key design patterns

- **Index resolution at channel construction time**: [functions/indexes.nf](functions/indexes.nf) resolves `.fai`, `.dict`, `.tbi`, and `.bai` index files eagerly when building channels, calling `error()` at startup if any are missing.
- **Parameter validation is delegated to Nextflow**: the typed `params` block in [main.nf](main.nf) handles required and undeclared parameters. [functions/inputs.nf](functions/inputs.nf) only validates the contents of the inputs CSV, per row.
- **Publishing via the workflow output definition**: the `publish:` section of the entry workflow and the top-level `output {}` block replace `publishDir` directives on individual processes. The destination comes from `outputDir` in [nextflow.config](nextflow.config), which is set from `params.output_dir`.
- **Optional inputs as pre-computed CLI arg strings**: Neither the normal BAM nor an intervals file are ever staged as `path()` inputs. When absent, they default to `""`. When present, the absolute path (normal BAM) or `--intervals /path` flag (intervals) are computed at channel construction time and passed as `val()` strings directly into process scripts. This avoids Nextflow staging files that are only conditionally needed and prevents Singularity bind-mount side effects.
- **Dual conda environments**: The container uses two conda envs — `filter-snvs-pipeline` (GATK, VEP, vcf2maf, samtools) and `filter_snvs_env_R` (R/tidyverse, unused after switch to vcf2maf but retained) — both activated via `PATH` ordering in the Dockerfile. vcf2maf itself is installed by cloning from GitHub HEAD into `/opt/vcf2maf`.

### Profiles

| Profile | Executor | Notes |
|---------|----------|-------|
| `standard` | local | 4 CPUs / 8 GB |
| `bigserver` | local | 50 CPUs / 128 GB |
| `cluster` | SLURM | Singularity enabled |
| `epyc` | SLURM (`epyc` queue) | Singularity enabled, conda disabled |

### Default SNV Filters

Applied by `applySnvFilters` via `gatk VariantFiltration`:
- `VariantAlleleCount < 3`
- `VariantAlleleCountControl > 1`
- `VariantMapQualMedian < 40.0`
- `MapQualDiffMedian < -5.0 || > 5.0`
- `LowMapQual > 0.05`
- `VariantBaseQualMedian < 25.0`

Override with `snv_filters` in the params file.
