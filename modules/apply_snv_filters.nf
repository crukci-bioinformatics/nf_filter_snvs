// Apply filters based on the SNV metrics using GATK VariantFiltration, then
// select only the variants that pass.
process applySnvFilters {
    input:
        tuple val(id), path(snvMetricsVcf), path(_snvMetricsVcfIndex)
        val snvFilters

    output:
        path filteredSnvMetricsVcf, emit: filteredVcf
        path filteredSnvMetricsVcfIndex, emit: filteredVcfIndex
        tuple val(id), path(passSnvMetricsVcf), emit: filtvcf
        path passSnvMetricsVcfIndex, emit: passVcfIndex

    script:
        filteredSnvMetricsVcf = "${id}.snv.metrics.filtered.vcf"
        filteredSnvMetricsVcfIndex = "${filteredSnvMetricsVcf}.idx"
        passSnvMetricsVcf = "${id}.snv.metrics.pass.vcf"
        passSnvMetricsVcfIndex = "${passSnvMetricsVcf}.idx"
        """
        gatk VariantFiltration \
            --variant ${snvMetricsVcf} \
            --output ${filteredSnvMetricsVcf} \
            ${snvFilters}

        gatk SelectVariants \
            --variant ${filteredSnvMetricsVcf} \
            --exclude-filtered \
            --output ${passSnvMetricsVcf}
        """

    stub:
        filteredSnvMetricsVcf = "${id}.snv.metrics.filtered.vcf"
        filteredSnvMetricsVcfIndex = "${filteredSnvMetricsVcf}.idx"
        passSnvMetricsVcf = "${id}.snv.metrics.pass.vcf"
        passSnvMetricsVcfIndex = "${passSnvMetricsVcf}.idx"
        """
        touch ${filteredSnvMetricsVcf}
        touch ${filteredSnvMetricsVcfIndex}
        touch ${passSnvMetricsVcf}
        touch ${passSnvMetricsVcfIndex}
        """
}
