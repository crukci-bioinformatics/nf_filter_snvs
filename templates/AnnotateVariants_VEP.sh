#!/bin/bash

# parameters from process
inpVCF=!{filteredVCF}
output=!{annotatedVcf}

# parameters from params
cacheDir=!{params.vepCache}
vepfa=!{params.vepFasta}
species=!{params.species}
assembly=!{params.assembly}

vep --cache \
    --input_file ${inpVCF} \
    --output_file ${output} \
    --species ${species} \
    --assembly ${assembly} \
    --format vcf \
    --vcf \
    --offline \
    --dir ${cacheDir} \
    --fasta ${vepfa} \
    --variant_class \
    --hgvs

vep | head
