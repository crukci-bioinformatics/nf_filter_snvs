#!/usr/bin/env nextflow

// enable DSL 2 syntax
nextflow.enable.dsl = 2

// include functions
include { referenceFasta; intervals; vcfDirectory; bamDirectory; outputDirectory; inputsCsv; extractInputRowValues; snvFilters } from './functions/configuration'
include { referenceFastaIndex; referenceFastaDictionary; vcfIndex; bamIndex } from './functions/indexes'

// Get sample names from SM tag in RG read group header in the input BAM files.
process getSampleNames {
    errorStrategy 'retry'
    maxRetries 5

    input:
        tuple val(id), path(vcf), path(vcfIndex), path(tumourBam), path(normalBam), path(bamIndexes), val(useNormal)

    output:
        tuple val(id), env(TUMOUR_SAMPLE), env(NORMAL_SAMPLE)

    script:
        """
        gatk GetSampleName --input ${tumourBam} --output tumour_sample.txt
        TUMOUR_SAMPLE=`cat tumour_sample.txt`

        NORMAL_SAMPLE="UNSPECIFIED_NORMAL"
        if [[ "${useNormal}" == "true" ]]; then
            gatk GetSampleName --input ${normalBam} --output normal_sample.txt
            NORMAL_SAMPLE=`cat normal_sample.txt`
        fi
        """
}

// Calculate SNV metrics
process calculateSNVMetrics {
    memory 2.GB
    errorStrategy 'retry'
    maxRetries 5

    input:
        tuple(
            val(id),
            path(vcf), path(vcfIndex),
            path(tumourBam), path(normalBam), path(bamIndexes), val(useNormal),
            val(tumourSample), val(normalSample),
            path(intervals),
            path(referenceFasta), path(referenceFastaIndex), path(referenceFastaDictionary)
        )

    output:
        tuple val(id), path(snvMetricsVcf), path(snvMetricsVcfIndex)

    script:
        snvMetricsVcf = "${id}.snv.metrics.vcf"
        snvMetricsVcfIndex = "${id}.snv.metrics.vcf.idx"
        normalArgs = useNormal ? "--input ${normalBam} --control-sample \"${normalSample}\"" : ""
        """
        gatk SelectVariants \
            --variant ${vcf} \
            --intervals ${intervals} \
            --select-type-to-include SNP \
            --exclude-filtered \
            --tmp-dir . \
            --output ${id}.snv.pass.vcf

        calculate-snv-metrics \
            --reference-sequence ${referenceFasta} \
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
}

// Output rest of VCF - create a VCF that contains everything except the SNPs
process selectRest{
    memory 2.GB
    errorStrategy 'retry'
    maxRetries 5

    publishDir "${outputDirectory()}", mode: 'link'

    input:
        tuple(
            val(id),
            path(vcf), path(vcfIndex),
            path(tumourBam), path(normalBam), path(bamIndexes), val(useNormal),
            path(intervals)
        )

    output:
        tuple val(id), path(indelsVcf)

    script:
        indelsVcf = "${id}.rest.vcf"
        """
        gatk SelectVariants \
            --variant ${vcf} \
            --intervals ${intervals} \
            --select-type-to-exclude SNP \
            --exclude-filtered \
            --tmp-dir . \
            --output ${id}.rest.vcf
        """
}

// Apply filters based on SNV metrics using GATK VariantFiltration
process applySnvFilters {
    errorStrategy 'retry'
    maxRetries 5

    publishDir "${outputDirectory()}", mode: 'link'

    input:
        tuple val(id), path(snvMetricsVcf), path(snvMetricsVcfIndex)

    output:
        path filteredSnvMetricsVcf
        path filteredSnvMetricsVcfIndex
        tuple val(id), path(passSnvMetricsVcf), emit: filtvcf
        path passSnvMetricsVcfIndex
        

    script:
        filters = snvFilters()
        filteredSnvMetricsVcf = "${id}.snv.metrics.filtered.vcf"
        filteredSnvMetricsVcfIndex = "${filteredSnvMetricsVcf}.idx"
        passSnvMetricsVcf = "${id}.snv.metrics.pass.vcf"
        passSnvMetricsVcfIndex = "${passSnvMetricsVcf}.idx"
        """
        gatk VariantFiltration \
            --variant ${snvMetricsVcf} \
            --output ${filteredSnvMetricsVcf} \
            ${filters}

        gatk SelectVariants \
            --variant ${filteredSnvMetricsVcf} \
            --exclude-filtered \
            --output ${passSnvMetricsVcf}
        """
}

process annotateVariants {
    errorStrategy 'retry'
    maxRetries 5

    publishDir "${outputDirectory()}", mode: 'link'

    input:
        tuple val(id), path(filteredVCF)

    output:
        tuple val(id), path(annotatedVcf)

    shell:
        annotatedVcf = "${filteredVCF.baseName}.vep_annotated.vcf"
        template 'AnnotateVariants_VEP.sh'
}

process vcfToTab {
    
    publishDir "${outputDirectory()}", mode: 'link'

    // conda 'r r-tidyverse'

    input:
        tuple val(id), path(vcfs)

    output:
        path variantsTab
        

    shell:
        variantsTab = "${id}.annotated_filtered.tsv"
        template 'VEP_VCF_to_tabular.sh'
}


workflow {
    // channel for the reference sequence FASTA file and its associated index
    // and dictionary
    referenceFasta = channel.fromPath(referenceFasta(), checkIfExists: true)
        .map { fasta -> tuple fasta, referenceFastaIndex(fasta), referenceFastaDictionary(fasta) }

    // channel for the intervals file which could be left unset
    // the first value in the tuple is a boolean for whether the intervals file
    // was set
    def intervalsFile = intervals()
    boolean useIntervals = intervalsFile != null
    intervals = channel.fromPath(intervalsFile ?: "${projectDir}/resources/UNSPECIFIED_INTERVALS", checkIfExists: useIntervals)
    //    .map { intervals -> tuple intervals, useIntervals }

    // channel for the input CSV file which should contain the following columns:
    //   id
    //   vcf
    //   tumour_bam
    //   normal_bam (may be empty if calling was tumour only)
    def inputsCsv = inputsCsv()
    def bamDir = bamDirectory()
    def vcfDir = vcfDirectory()
    int rowNumber = 0
    inputs = channel.fromPath(inputsCsv, checkIfExists: true)
        .splitCsv(header: true, quote: '"')
        .map { row -> extractInputRowValues(row, inputsCsv, ++rowNumber) }
        .map { id, vcf, tumourBam, normalBam -> tuple (
            id,
            vcfDir ? (params.sarek_output ? "${vcfDir}/${id}/${vcf}" : "${vcfDir}/${vcf}") : vcf,
            bamDir ? "${bamDir}/${tumourBam}" : tumourBam,
            normalBam ? (bamDir ? "${bamDir}/${normalBam}" : normalBam) : "${projectDir}/resources/UNSPECIFIED_BAM",
            normalBam != null
        ) }
        .map { id, vcf, tumourBam, normalBam, useNormalBam -> tuple (
            id,
            file(vcf, checkIfExists: true),
            file(tumourBam, checkIfExists: true),
            file(normalBam, checkIfExists: useNormalBam),
            useNormalBam
        ) }
        .map { id, vcf, tumourBam, normalBam, useNormalBam -> tuple (
            id,
            file(vcf, checkIfExists: true),
            vcfIndex(vcf),
            file(tumourBam, checkIfExists: true),
            file(normalBam, checkIfExists: useNormalBam),
            useNormalBam ? tuple(bamIndex(tumourBam), bamIndex(normalBam)) : bamIndex(tumourBam),
            useNormalBam
        ) }

    // check for no entries in inputs CSV file
    inputs
        .count()
        .filter { it == 0}
        .subscribe { exit 1, "No entries in ${inputsCsv}" }

    // check for multiple inputs with same id
    inputs
        .map { tuple it[0], it[1] }
        .groupTuple()
        .filter { it[1].size() > 1}
        .subscribe { exit 1, "Multiple entries with id ${it[0]} in ${inputsCsv}" }



    // get tumour and normal sample names
    sampleNames = getSampleNames(inputs)

    // select non-SNV variants
    selectRest(
        inputs
            .combine(intervals)
    )

    // calculate SNV metrics
    calculateSNVMetrics(
        inputs
            .join(sampleNames)
            .combine(intervals)
            .combine(referenceFasta)
    )

    // apply filters based on SNV metrics
    applySnvFilters(calculateSNVMetrics.out)

    // annotate variants
    vcfsChannel = selectRest.out.mix(applySnvFilters.out.filtvcf)
    annotateVariants(vcfsChannel)

    // convert VCF to tabular format
    // combine vcfs in the annotateVariants output channel by id
    annotatedChannel = annotateVariants.out 
        .groupTuple(size: 2)
    annotatedChannel.view()
    vcfToTab(annotatedChannel)
}
