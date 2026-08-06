// Convert a VCF to MAF format using vcf2maf, which runs VEP annotation
// internally.
//
// The Tumor_Sample_Barcode written to the MAF is the id from the inputs CSV,
// not the sample name in the BAM read group header. The read group sample name
// is still needed to identify the normal, so it is carried through as
// _tumourSample for the tuple to destructure even though only the normal is
// used here.
process vcfToMaf {
    input:
        tuple val(id), path(vcf), val(_tumourSample), val(normalSample),
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
            --tumor-id ${id} \
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
