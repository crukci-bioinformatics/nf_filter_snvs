// Functions for resolving the index files that accompany the reference FASTA,
// VCF and BAM files given in the pipeline parameters and inputs CSV file.
//
// These are called when the channels are built so that a missing index aborts
// the run at startup rather than part way through.
//
// Each function takes a Path object created using the file() method or by
// channel.fromPath().

// Find the index file(s) for the given reference sequence FASTA file.
// Returns the .fai file, or a tuple of the .fai and .gzi files if the reference
// FASTA file is compressed.
def resolveFastaIndex(Path referenceFastaFile) {
    def extension = referenceFastaFile.extension
    def compressed = extension == 'gz'
    if( compressed )
        extension = file(referenceFastaFile.baseName).extension

    if( extension != 'fa' && extension != 'fasta' )
        error("Reference FASTA file must have a .fa or .fasta suffix (${referenceFastaFile.name})")

    def faiFile = file("${referenceFastaFile}.fai")
    if( !faiFile.exists() )
        error("Could not locate .fai index for reference FASTA file ${referenceFastaFile.name}")

    if( !compressed )
        return faiFile

    def gziFile = file("${referenceFastaFile}.gzi")
    if( !gziFile.exists() )
        error("Could not locate .gzi index for reference FASTA file ${referenceFastaFile.name}")

    return tuple(faiFile, gziFile)
}

// Find the sequence dictionary for the given reference sequence FASTA file.
def resolveFastaDict(Path referenceFastaFile) -> Path {
    def referenceFastaPath = referenceFastaFile.toString()

    if( !(referenceFastaPath ==~ /.*(fa|fasta)(\.gz)?/) )
        error("Reference FASTA file must have a .fa or .fasta suffix (${referenceFastaFile.name})")

    def dictPath = referenceFastaPath.replaceFirst(/(fa|fasta)(\.gz)?$/, 'dict')

    def dictFile = file(dictPath)
    if( !dictFile.exists() )
        error("Could not locate .dict sequence dictionary (${dictPath}) for reference FASTA file ${referenceFastaFile.name}")

    return dictFile
}

// Find the .tbi index file for the given VCF.
def resolveVcfIndex(Path vcfFile) -> Path {
    if( !vcfFile.name.endsWith('.vcf.gz') )
        error("VCF files must have a .vcf.gz suffix (${vcfFile.name})")

    def tbiFile = file("${vcfFile}.tbi")
    if( !tbiFile.exists() )
        error("Could not locate .tbi index for VCF file ${vcfFile.name}")

    return tbiFile
}

// Find the .bai index file for the given BAM, which may be named either
// <file>.bai or <file>.bam.bai.
def resolveBamIndex(Path bamFile) -> Path {
    if( !bamFile.name.endsWith('.bam') )
        error("BAM files must have a .bam suffix (${bamFile.name})")

    def bamPath = bamFile.toString()

    def baiFile = file(bamPath.replaceFirst(/bam$/, 'bai'))
    if( baiFile.exists() )
        return baiFile

    def bamBaiFile = file("${bamPath}.bai")
    if( bamBaiFile.exists() )
        return bamBaiFile

    error("Could not locate .bai index for BAM file ${bamFile.name}")
}
