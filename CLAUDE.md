# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Nextflow (DSL2) pipeline that filters SNVs (single nucleotide variants) using [`htsjdk-tools`](https://github.com/crukci-bioinformatics/htsjdk-tools), then converts both SNVs and indels to MAF format using [vcf2maf](https://github.com/mskcc/vcf2maf) (which runs VEP annotation internally), and merges the results into a single MAF per sample.

## Smoke Test (stub run)

```bash
# One-time fixture setup (requires bgzip + tabix from the seqware conda env)
conda run -n seqware bash examples/setup_test_fixtures.sh

# Run the stub smoke test
nextflow run main.nf -stub -params-file examples/test_params.yml
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
- `REFERENCE_FASTA` — path to reference genome `.fa` or `.fasta` (must have co-located `.fai` and `.dict` files)
- `vepCache` — path to VEP cache directory
- `vepFasta` — path to VEP FASTA file
- `species` — e.g. `"mus_musculus"` or `"homo_sapiens"`
- `assembly` — e.g. `"GRCm38"` or `"GRCh38"`

## Input CSV Format

The `INPUTS_CSV` file (default: `inputs.csv`) must have columns: `id`, `vcf`, `tumour_bam`, and optionally `normal_bam`. VCF files must be gzip-compressed (`.vcf.gz`) with a `.tbi` index. BAM files must have a `.bai` index (either `file.bai` or `file.bam.bai`).

## Pipeline Architecture

### Workflow (`main.nf`)

The main workflow runs these processes in order:

1. **`getSampleNames`** — extracts tumour/normal sample names from BAM read group headers via `gatk GetSampleName`
2. **`selectRest`** — extracts non-SNP variants (indels etc.) using `gatk SelectVariants`; runs in parallel with SNV processing
3. **`calculateSNVMetrics`** — selects PASS SNPs then runs `calculate-snv-metrics` (from htsjdk-tools) to add allele count and mapping quality metrics to the VCF
4. **`applySnvFilters`** — applies `gatk VariantFiltration` using `SNV_FILTERS` expressions, then selects only PASS variants
5. **`vcfToMaf`** — converts each filtered VCF (SNVs and indels separately) to MAF format using `vcf2maf.pl`, which runs VEP annotation internally; requires `vepCache`, `vepFasta`, `species`, `assembly` params
6. **`mergeMafs`** — groups the SNV and indel MAFs by sample ID (`.groupTuple(size: 2)`) and concatenates them into a single `<id>.merged.maf` output file

### Key design patterns

- **Index resolution at channel construction time**: [functions/indexes.nf](functions/indexes.nf) resolves `.fai`, `.dict`, `.tbi`, and `.bai` index files eagerly when building channels, throwing at startup if any are missing.
- **Parameter validation**: [functions/configuration.nf](functions/configuration.nf) wraps all `params` access with null/empty checks and trimming.
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

Override with `SNV_FILTERS` in the params file.
