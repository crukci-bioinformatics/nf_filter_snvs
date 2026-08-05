// Get sample names from the SM tag in the RG read group header of the input BAM
// files.
process getSampleNames {
    input:
        tuple val(id), path(tumourBam), path(_tumourBamIndex), val(normalBamPath), val(useNormal)

    output:
        tuple val(id), env('TUMOUR_SAMPLE'), env('NORMAL_SAMPLE')

    script:
        """
        gatk GetSampleName --input ${tumourBam} --output tumour_sample.txt
        TUMOUR_SAMPLE=`cat tumour_sample.txt`

        NORMAL_SAMPLE="UNSPECIFIED_NORMAL"
        if [[ "${useNormal}" == "true" ]]; then
            gatk GetSampleName --input "${normalBamPath}" --output normal_sample.txt
            NORMAL_SAMPLE=`cat normal_sample.txt`
        fi
        """

    stub:
        """
        TUMOUR_SAMPLE="STUB_TUMOUR"
        NORMAL_SAMPLE="UNSPECIFIED_NORMAL"
        if [[ "${useNormal}" == "true" ]]; then
            NORMAL_SAMPLE="STUB_NORMAL"
        fi
        """
}
