// Convert a VCF to MAF format using vcf2maf, which runs VEP annotation
// internally.
process vcfToMaf {
    input:
        tuple val(id), path(vcf), val(tumourSample), val(normalSample),
            path(referenceFastaFile), path(_referenceFastaIndex), path(_referenceFastaDict)
        val vepCache
        val species
        val assembly

    output:
        tuple val(id), path(mafFile)

    script:
        mafFile = "${vcf.baseName}.maf"
        """
        NORMAL_ID_ARG=""
        if [[ "${normalSample}" != "UNSPECIFIED_NORMAL" ]]; then
            NORMAL_ID_ARG="--normal-id ${normalSample}"
        fi

        vcf2maf.pl \
            --input-vcf ${vcf} \
            --output-maf ${mafFile} \
            --tumor-id ${tumourSample} \
            \${NORMAL_ID_ARG} \
            --ref-fasta ${referenceFastaFile} \
            --vep-path \$(dirname \$(which vep)) \
            --vep-data ${vepCache} \
            --species ${species} \
            --ncbi-build ${assembly}
        """

    stub:
        mafFile = "${vcf.baseName}.maf"
        """
        touch ${mafFile}
        """
}
