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
        tuple val(id), path(tumourBam), path(tumourBamIndex), val(normalBamPath), val(useNormal)

    output:
        tuple val(id), env(TUMOUR_SAMPLE), env(NORMAL_SAMPLE)

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

// Calculate SNV metrics
process calculateSNVMetrics {
    memory 2.GB
    errorStrategy 'retry'
    maxRetries 5

    input:
        tuple(
            val(id),
            path(vcf), path(vcfIndex),
            path(tumourBam), path(tumourBamIndex),
            val(tumourSample), val(normalArgs),
            val(intervalArgs),
            path(referenceFasta), path(referenceFastaIndex), path(referenceFastaDictionary)
        )

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

    stub:
        snvMetricsVcf = "${id}.snv.metrics.vcf"
        snvMetricsVcfIndex = "${id}.snv.metrics.vcf.idx"
        """
        touch ${snvMetricsVcf}
        touch ${snvMetricsVcfIndex}
        """
}

// Output rest of VCF - create a VCF that contains everything except the SNPs
process selectRest{
    memory 2.GB
    errorStrategy 'retry'
    maxRetries 5

    publishDir "${outputDirectory()}", mode: 'link'

    input:
        tuple val(id), path(vcf), path(vcfIndex), val(intervalArgs)

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
            --output ${id}.rest.vcf
        """

    stub:
        indelsVcf = "${id}.rest.vcf"
        """
        touch ${indelsVcf}
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

process vcfToMaf {
    errorStrategy 'retry'
    maxRetries 5

    input:
        tuple val(id), path(vcf), val(tumourSample), val(normalSample),
            path(referenceFasta), path(referenceFastaIndex), path(referenceFastaDictionary)

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
            --ref-fasta ${referenceFasta} \
            --vep-path \$(dirname \$(which vep)) \
            --vep-data ${params.vepCache} \
            --species ${params.species} \
            --ncbi-build ${params.assembly}
        """

    stub:
        mafFile = "${vcf.baseName}.maf"
        """
        touch ${mafFile}
        """
}

process mergeMafs {
    publishDir "${outputDirectory()}", mode: 'link'

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


workflow {
    // channel for the reference sequence FASTA file and its associated index
    // and dictionary
    referenceFasta = channel.fromPath(referenceFasta(), checkIfExists: true)
        .map { fasta -> tuple fasta, referenceFastaIndex(fasta), referenceFastaDictionary(fasta) }

    def intervalsFile = intervals()
    def intervalArgsCh = Channel.value(intervalsFile ? "--intervals ${intervalsFile}" : "")

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
        .map { id, vcf, tumourBam, normalBam ->
            def vcfPath  = vcfDir ? (params.sarek_output ? "${vcfDir}/${id}/${vcf}" : "${vcfDir}/${vcf}") : vcf
            def tBamPath = bamDir ? "${bamDir}/${tumourBam}" : tumourBam
            def useNormal = normalBam != null
            def nBamStr  = ""
            if (useNormal) {
                def nBamPath = bamDir ? "${bamDir}/${normalBam}" : normalBam
                def nBamFile = file(nBamPath, checkIfExists: true)
                bamIndex(nBamFile)
                nBamStr = nBamFile.toAbsolutePath().toString()
            }
            def vcfFile  = file(vcfPath, checkIfExists: true)
            def tBamFile = file(tBamPath, checkIfExists: true)
            tuple(id, vcfFile, vcfIndex(vcfFile), tBamFile, bamIndex(tBamFile), nBamStr, useNormal)
        }

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
    sampleNames = getSampleNames(
        inputs.map { id, vcf, vcfIdx, tBam, tBamIdx, nBamPath, useNormal ->
            tuple(id, tBam, tBamIdx, nBamPath, useNormal)
        }
    )

    // select non-SNV variants
    selectRest(
        inputs
            .map { id, vcf, vcfIdx, tBam, tBamIdx, nBamPath, useNormal -> tuple(id, vcf, vcfIdx) }
            .combine(intervalArgsCh)
    )

    // calculate SNV metrics
    calculateSNVMetrics(
        inputs
            .join(sampleNames)
            .map { id, vcf, vcfIdx, tBam, tBamIdx, nBamPath, useNormal, tSample, nSample ->
                def nArgs = useNormal ? "--input ${nBamPath} --control-sample \"${nSample}\"" : ""
                tuple(id, vcf, vcfIdx, tBam, tBamIdx, tSample, nArgs)
            }
            .combine(intervalArgsCh)
            .combine(referenceFasta)
    )

    // apply filters based on SNV metrics
    applySnvFilters(calculateSNVMetrics.out)

    // convert filtered VCFs to MAF format (runs VEP internally)
    vcfsChannel = selectRest.out.mix(applySnvFilters.out.filtvcf)
    vcfToMaf(
        vcfsChannel
            .combine(sampleNames, by: 0)
            .combine(referenceFasta)
    )

    // merge SNV and indel MAFs into one file per sample
    mergeMafs(vcfToMaf.out.groupTuple(size: 2))
}
