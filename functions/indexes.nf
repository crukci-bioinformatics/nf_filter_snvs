
// Find the index file(s) for the given reference sequence FASTA file.
// The referenceFastaFile should be a Path object created using the file()
// method or using Channel.fromPath().
def referenceFastaIndex(referenceFastaFile) {
    def extension = referenceFastaFile.extension
    def compressed = extension == "gz"
    if (compressed) {
        extension = file(referenceFastaFile.baseName).extension
    }

    if (extension != "fa" && extension != "fasta") {
        log.error("Reference FASTA file must have a .fa or .fasta suffix (${referenceFastaFile.name})")
        throw new Exception("Reference FASTA file must have a .fa or .fasta suffix")
    }

    def referenceFastaPath = referenceFastaFile.toString()

    def faiFile = file(referenceFastaPath + ".fai")
    if (!faiFile.exists()) {
        log.error("Could not locate .fai index for reference FASTA file ${referenceFastaFile.name}")
        throw new Exception("Could not locate .fai index for reference FASTA file")
    }

    // check for gzi file if the reference FASTA file is compressed in which
    // return a tuple of the two index files
    if (compressed) {
        def gziFile = file(referenceFastaPath + ".gzi")
        if (!gziFile.exists()) {
            log.error("Could not locate .gzi index for reference FASTA file ${referenceFastaFile.name}")
            throw new Exception("Could not locate .gzi index for reference FASTA file")
        }
        return tuple(faiFile, gziFile)
    }

    faiFile
}

// Find the sequence dictionary for the given reference sequence FASTA file.
// The referenceFastaFile should be a Path object created using the file()
// method or using Channel.fromPath().
def referenceFastaDictionary(referenceFastaFile) {
    def referenceFastaPath = referenceFastaFile.toString()

    if (!(referenceFastaPath ==~ /.*(fa|fasta)(\.gz)?/)) {
        log.error("Reference FASTA file must have a .fa or .fasta suffix (${referenceFastaFile.name})")
        throw new Exception("Reference FASTA file must have a .fa or .fasta suffix")
    }

    def dictPath = referenceFastaFile.toString().replaceFirst(/(fa|fasta)(\.gz)?$/, "dict")

    def dictFile = file(dictPath)
    if (!dictFile.exists()) {
        log.error("Could not locate .dict sequence dictionary (${dictPath}) for reference FASTA file ${referenceFastaFile.name}")
        throw new Exception("Could not locate .dict sequence dictionary for reference FASTA file")
    }

    dictFile
}

// find the index file for the given VCF 
// The vcfFile should be a Path object created using the file()
// method or using Channel.fromPath().
def vcfIndex(vcfFile) {
    if (!vcfFile.name.endsWith(".vcf.gz")) {
        log.error("VCF files must have a .vcf.gz suffix (${vcfFile.name})")
        throw new Exception("VCF files must have a .vcf.gz suffix")
    }

    def vcfPath = vcfFile.toString()

    tbiFile = file(vcfPath + ".tbi")
    if (tbiFile.exists()) return tbiFile

    log.error("Could not locate .tbi index for VCF file ${vcfFile.name}")
    throw new Exception("Could not locate .tbi index for VCF file " + vcfFile.name)
}


// find the index file for the given BAM
// The bamFile should be a Path object created using the file()
// method or using Channel.fromPath().
def bamIndex(bamFile) {
    if (!bamFile.name.endsWith(".bam")) {
        log.error("BAM files must have a .bam suffix (${bamFile.name})")
        throw new Exception("BAM files must have a .bam suffix")
    }

    def bamPath = bamFile.toString()

    def baiFile = file(bamPath.replaceFirst(/bam$/, "bai"))
    if (baiFile.exists()) return baiFile

    baiFile = file(bamPath + ".bai")
    if (baiFile.exists()) return baiFile

    log.error("Could not locate .bai index for BAM file ${bamFile.name}")
    throw new Exception("Could not locate .bai index for BAM file " + bamFile.name)
}
