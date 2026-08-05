#!/usr/bin/env nextflow

params {
    // The reference genome sequence FASTA file. Must have co-located .fai and
    // .dict files.
    reference_fasta : Path

    // The genomic intervals over which to filter variants.
    // Can be a BED file or a Picard interval list file.
    // If left unset the entire reference sequence will be used.
    intervals : Path? = null

    // The directory containing the VCF files specified in the inputs CSV file.
    // If left unset the VCF files specified in the inputs CSV are treated as
    // having valid paths which may be relative to the launch directory or
    // absolute paths.
    vcf_dir : Path? = null

    // The directory containing the BAM files specified in the inputs CSV file.
    // If left unset the BAM files specified in the inputs CSV are treated as
    // having valid paths which may be relative to the launch directory or
    // absolute paths.
    bam_dir : Path? = null

    // CSV file specifying the input VCF and BAM files.
    // Must contain an id, vcf and tumour_bam column and optionally a normal_bam
    // column where a matched normal is available.
    inputs_csv : Path

    // Top-level directory containing the output files.
    output_dir : String

    // Filter names and expressions provided to GATK VariantFiltration.
    snv_filters : String

    // If the output is from sarek the VCFs are in subdirectories named after the
    // sample.
    sarek_output : Boolean = false

    // VEP cache directory, species and genome assembly, passed through to
    // vcf2maf.
    vep_cache : Path
    species : String
    assembly : String
}

include { extractInputRowValues } from './functions/inputs.nf'
include { resolveFastaIndex ; resolveFastaDict ; resolveVcfIndex ; resolveBamIndex } from './functions/indexes.nf'

include { getSampleNames } from './modules/get_sample_names.nf'
include { selectRest } from './modules/select_rest.nf'
include { calculateSNVMetrics } from './modules/calculate_snv_metrics.nf'
include { applySnvFilters } from './modules/apply_snv_filters.nf'
include { vcfToMaf } from './modules/vcf_to_maf.nf'
include { mergeMafs } from './modules/merge_mafs.nf'

workflow {
    main:
    // channel for the reference sequence FASTA file and its associated index
    // and dictionary
    def refFastaCh = channel.fromPath(params.reference_fasta, checkIfExists: true)
        .map { fasta -> tuple(fasta, resolveFastaIndex(fasta), resolveFastaDict(fasta)) }

    // the intervals are passed to the GATK processes as a pre-computed argument
    // string so that no file is staged when no intervals are given
    def intervalArgsCh = channel.value(params.intervals ? "--intervals ${params.intervals}" : "")

    // channel for the input CSV file which should contain the following columns:
    //   id
    //   vcf
    //   tumour_bam
    //   normal_bam (may be empty if calling was tumour only)
    def inputsCsv = params.inputs_csv.toString()
    def bamDir = params.bam_dir
    def vcfDir = params.vcf_dir

    def inputsCh = channel.fromPath(params.inputs_csv, checkIfExists: true)
        .splitCsv(header: true, quote: '"')
        // pair each row with its position so that validation messages can name
        // the row they refer to. Rows are numbered from one, not counting the
        // header. extractInputRowValues is called from a map closure rather
        // than from a nested closure so that the errors it raises are reported
        // with their message rather than as a wrapped InvocationTargetException.
        .toList()
        .flatMap { rows -> rows.withIndex() }
        .map { row, i -> extractInputRowValues(row, inputsCsv, i + 1) }
        .map { id, vcf, tumourBam, normalBam ->
            def vcfPath = vcfDir ? (params.sarek_output ? "${vcfDir}/${id}/${vcf}" : "${vcfDir}/${vcf}") : vcf
            def tBamPath = bamDir ? "${bamDir}/${tumourBam}" : tumourBam
            def useNormal = normalBam != null
            def nBamStr = ""
            if( useNormal ) {
                def nBamPath = bamDir ? "${bamDir}/${normalBam}" : normalBam
                def nBamFile = file(nBamPath, checkIfExists: true)
                // the normal BAM is passed to the processes as a path string
                // rather than being staged, so its index is only checked for
                // here, not carried through the channel
                resolveBamIndex(nBamFile)
                nBamStr = nBamFile.toAbsolutePath().toString()
            }
            def vcfFile = file(vcfPath, checkIfExists: true)
            def tBamFile = file(tBamPath, checkIfExists: true)
            tuple(id, vcfFile, resolveVcfIndex(vcfFile), tBamFile, resolveBamIndex(tBamFile), nBamStr, useNormal)
        }

    // check for no entries in the inputs CSV file
    inputsCh
        .count()
        .subscribe { n ->
            if( n == 0 )
                error("No entries in ${inputsCsv}")
        }

    // check for multiple inputs with the same id
    inputsCh
        .map { row -> tuple(row[0], row[1]) }
        .groupTuple()
        .subscribe { id, vcfs ->
            if( vcfs.size() > 1 )
                error("Multiple entries with id ${id} in ${inputsCsv}")
        }

    // get tumour and normal sample names
    def sampleNamesCh = getSampleNames(
        inputsCh.map { id, _vcf, _vcfIdx, tBam, tBamIdx, nBamPath, useNormal ->
            tuple(id, tBam, tBamIdx, nBamPath, useNormal)
        }
    )

    // select non-SNV variants
    selectRest(
        inputsCh
            .map { id, vcf, vcfIdx, _tBam, _tBamIdx, _nBamPath, _useNormal -> tuple(id, vcf, vcfIdx) }
            .combine(intervalArgsCh)
    )

    // calculate SNV metrics
    calculateSNVMetrics(
        inputsCh
            .join(sampleNamesCh)
            .map { id, vcf, vcfIdx, tBam, tBamIdx, nBamPath, useNormal, tSample, nSample ->
                def nArgs = useNormal ? "--input ${nBamPath} --control-sample \"${nSample}\"" : ""
                tuple(id, vcf, vcfIdx, tBam, tBamIdx, tSample, nArgs)
            }
            .combine(intervalArgsCh)
            .combine(refFastaCh)
    )

    // apply filters based on the SNV metrics.
    // snv_filters is a block of command line arguments spread over several lines
    // for readability, so collapse it to a single line before it is interpolated
    // into the process script: a stray newline would terminate the gatk command
    // early and leave the remaining arguments to be run as a command of their
    // own. This also makes the parameter safe to supply as a YAML block scalar.
    def snvFilterArgs = params.snv_filters.trim().replaceAll(/\s+/, ' ')
    applySnvFilters(calculateSNVMetrics.out, snvFilterArgs)

    // convert the filtered VCFs to MAF format (runs VEP internally)
    def vcfsCh = selectRest.out.mix(applySnvFilters.out.filtvcf)
    vcfToMaf(
        vcfsCh
            .combine(sampleNamesCh, by: 0)
            .combine(refFastaCh),
        params.vep_cache,
        params.species,
        params.assembly
    )

    // merge the SNV and indel MAFs into one file per sample
    mergeMafs(vcfToMaf.out.groupTuple(size: 2))

    publish:
    indel_vcfs = selectRest.out.map { _id, vcf -> vcf }
    snv_vcfs = applySnvFilters.out.filteredVcf
        .mix(
            applySnvFilters.out.filteredVcfIndex,
            applySnvFilters.out.filtvcf.map { _id, vcf -> vcf },
            applySnvFilters.out.passVcfIndex
        )
    merged_mafs = mergeMafs.out
}

output {
    indel_vcfs {
        path '.'
        mode 'link'
    }

    snv_vcfs {
        path '.'
        mode 'link'
    }

    merged_mafs {
        path '.'
        mode 'link'
    }
}
