// Create a VCF that contains everything except the SNPs, i.e. indels and other
// non-SNP variants.
process selectRest {
    input:
        tuple val(id), path(vcf), path(_vcfIndex), val(intervalArgs)

    output:
        tuple val(id), path(indelsVcf)

    script:
        indelsVcf = "${id}.rest.vcf"
        """
        gatk SelectVariants \
            --variant ${vcf} \
            ${intervalArgs} \
            --select-type-to-exclude SNP \
            --exclude-filtered \
            --tmp-dir . \
            --output ${indelsVcf}
        """

    stub:
        indelsVcf = "${id}.rest.vcf"
        """
        touch ${indelsVcf}
        """
}
