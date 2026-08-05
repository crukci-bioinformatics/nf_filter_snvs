// Select PASS SNPs and add allele count and mapping quality metrics to the VCF
// using calculate-snv-metrics from htsjdk-tools.
process calculateSNVMetrics {
    input:
        tuple val(id),
            path(vcf), path(_vcfIndex),
            path(tumourBam), path(_tumourBamIndex),
            val(tumourSample), val(normalArgs),
            val(intervalArgs),
            path(referenceFastaFile), path(_referenceFastaIndex), path(_referenceFastaDict)

    output:
        tuple val(id), path(snvMetricsVcf), path(snvMetricsVcfIndex)

    script:
        snvMetricsVcf = "${id}.snv.metrics.vcf"
        snvMetricsVcfIndex = "${id}.snv.metrics.vcf.idx"
        """
        gatk SelectVariants \
            --variant ${vcf} \
            ${intervalArgs} \
            --select-type-to-include SNP \
            --exclude-filtered \
            --tmp-dir . \
            --output ${id}.snv.pass.vcf

        calculate-snv-metrics \
            --reference-sequence ${referenceFastaFile} \
            --variants ${id}.snv.pass.vcf \
            --input ${tumourBam} \
            --sample ${tumourSample} \
            ${normalArgs} \
            --minimum-mapping-quality 1 \
            --minimum-base-quality 10 \
            --output ${snvMetricsVcf}

        gatk IndexFeatureFile \
            -I ${snvMetricsVcf}
        """

    stub:
        snvMetricsVcf = "${id}.snv.metrics.vcf"
        snvMetricsVcfIndex = "${id}.snv.metrics.vcf.idx"
        """
        touch ${snvMetricsVcf}
        touch ${snvMetricsVcfIndex}
        """
}
