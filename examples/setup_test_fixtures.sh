#!/usr/bin/env bash
# Generates test fixture files required for the stub smoke test.
# Requires bgzip and tabix — run via: conda run -n seqware bash examples/setup_test_fixtures.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Compress and index the stub VCF
bgzip -c "${SCRIPT_DIR}/vcf/stub_test.vcf" > "${SCRIPT_DIR}/vcf/stub_test.vcf.gz"
tabix -p vcf "${SCRIPT_DIR}/vcf/stub_test.vcf.gz"

# Stub BAM + index (content is irrelevant for a stub run)
mkdir -p "${SCRIPT_DIR}/bam"
touch "${SCRIPT_DIR}/bam/stub_tumour.bam"
touch "${SCRIPT_DIR}/bam/stub_tumour.bai"

# Stub reference FASTA + index files (indexes.nf only checks for file existence)
mkdir -p "${SCRIPT_DIR}/ref"
printf ">1\nACGT\n" > "${SCRIPT_DIR}/ref/stub_ref.fa"
touch "${SCRIPT_DIR}/ref/stub_ref.fa.fai"
touch "${SCRIPT_DIR}/ref/stub_ref.dict"

# Stub VEP cache directory. The vep_cache param is declared as a Path, so
# Nextflow checks it exists before the run starts, even for a stub run.
mkdir -p "${SCRIPT_DIR}/vep_cache"
touch "${SCRIPT_DIR}/vep_cache/.gitkeep"

echo "Test fixtures created successfully."
