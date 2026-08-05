// Concatenate the SNV and indel MAFs for a sample into a single MAF, keeping one
// copy of the two-line header.
process mergeMafs {
    input:
        tuple val(id), path(mafs)

    output:
        path mergedMaf

    script:
        mergedMaf = "${id}.merged.maf"
        """
        head -2 ${mafs[0]} > ${mergedMaf}
        for maf in ${mafs}; do
            tail -n +3 \${maf} >> ${mergedMaf}
        done
        """

    stub:
        mergedMaf = "${id}.merged.maf"
        """
        touch ${mergedMaf}
        """
}
