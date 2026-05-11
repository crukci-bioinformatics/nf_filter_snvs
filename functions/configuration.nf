
// Characters that are not alphanumeric, dot, underscore or hyphen are replaced
// with underscores; spaces and tabs are removed.
def safeName(name) {
    def nameStr = name.toString()
    def safe = new StringBuilder(nameStr.length())
    for (int i = 0; i < nameStr.length(); i++) {
        def c = nameStr.charAt(i) as char
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.') {
            safe << c
        } else if (c == ' ' || c == '\t') {
            // skip
        } else {
            safe << '_'
        }
    }
    return safe.toString()
}

//  Trims whitespace from the given value and checks if it is null or empty and
// reports an error and throws and exception depending on whether either or both
// are acceptable.
def trimAndCheckValue(String name, String value, boolean canBeEmpty = false, boolean canBeNull = false) {
    value = value?.trim()

    if (!canBeEmpty && value?.empty) {
        message = "${name} is not defined (empty value)"
        log.error message
        throw new Exception(message)
    }

    if (!canBeNull && value == null) {
        message = "${name} is not defined"
        log.error message
        throw new Exception(message)
    }

    value
}

// Gets the value of the given parameter with whitespace trimmed.
// Checks whether the value is null, empty or all whitespace and reports an
// error and throws and exception depending on whether either or both are
// acceptable.
def getParameterValue(String name, boolean canBeEmpty = false, boolean canBeNull = false) {
    trimAndCheckValue(name, params[name], canBeEmpty, canBeNull)
}

// Gets the REFERENCE_FASTA parameter, trimming whitespace and checking it isn't
// empty or all whitespace.
def referenceFasta() {
    getParameterValue("REFERENCE_FASTA", false, false)

}

// Gets the INTERVALS parameter, trimming whitespace and checking it isn't empty
// or all whitespace.
// This is an optional parameter so can be set to null.
def intervals() {
    getParameterValue("INTERVALS", false, true)
}

// Gets the VCF_DIR parameter, trimming whitespace and checking it isn't empty
// or all whitespace.
// This is an optional parameter so can be set to null.
def vcfDirectory() {
    getParameterValue("VCF_DIR", false, true)
}

// Gets the BAM_DIR parameter, trimming whitespace and checking it isn't empty
// or all whitespace.
// This is an optional parameter so can be set to null.
def bamDirectory() {
    getParameterValue("BAM_DIR", false, true)
}

// Gets the OUTPUT_DIR parameter, trimming whitespace and checking it isn't
// null, empty or all whitespace.
def outputDirectory() {
    getParameterValue("OUTPUT_DIR", false, false)
}

// Gets the INPUTS_CSV parameter, trimming whitespace and checking it isn't
// null, empty or all whitespace.
def inputsCsv() {
    getParameterValue("INPUTS_CSV", false, false)
}

// Gets the SNV_FILTERS paramter, trimming whitespace and checking it isn't
// null, empty of all whitespace.
def snvFilters() {
    getParameterValue("SNV_FILTERS", false, false)
}

// Checks column exists in the input CSV file.
def checkInputColumnExists(row, column, inputCsv) {
    if (!row.containsKey(column)) {
        def message = "${column} column missing from input CSV file ${inputCsv}"
        log.error message
        throw new Exception(message)
    }
}

// Extract values for the required columns from the inputs CSV file, trimming
// and checking as appropriate.
// A tuple of the id, tumourBam and normalBam is returned.
// The normalBam value can be unset, e.g. if there is no normal_bam column in
// CSV file or if the value is empty, in which case a null is returned as part
// of the tuple.
def extractInputRowValues(row, inputCsv, rowNumber) {
    checkInputColumnExists(row, "id", inputCsv)
    checkInputColumnExists(row, "tumour_bam", inputCsv)

    def id = trimAndCheckValue("id in row ${rowNumber} of ${inputCsv}", row.id)

    def safeId = safeName(id)
    if (id != safeId) {
        log.warn("Renaming id in row ${rowNumber} of ${inputCsv} from '${id}' to '${safeId}'")
        id = safeId
    }

    def vcf = trimAndCheckValue("vcf in row ${rowNumber} of ${inputCsv}", row.vcf)

    def tumourBam = trimAndCheckValue("tumour_bam in row ${rowNumber} of ${inputCsv}", row.tumour_bam)

    def normalBam = trimAndCheckValue("normal_bam in row ${rowNumber} of ${inputCsv}", row.normal_bam, true, true)

    if (!normalBam) {
        log.warn("Normal BAM not specified for ${id}")
        // ensure that a non-specified normal BAM file is returned as null
        // not an empty string to ease with testing for this later in the
        // workflow
        normalBam = null
    }

    tuple(id, vcf, tumourBam, normalBam)
}

