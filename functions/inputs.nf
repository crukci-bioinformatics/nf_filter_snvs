// Functions for parsing and validating rows of the inputs CSV file.
//
// Validation of the pipeline parameters themselves is handled by the typed
// `params` block in main.nf, which reports missing required parameters and
// rejects parameters that are not declared.

// Characters that are not alphanumeric, dot, underscore or hyphen are replaced
// with underscores; spaces and tabs are removed.
def safeName(String name) -> String {
    return name
        .replaceAll(/[ \t]+/, '')
        .replaceAll(/[^A-Za-z0-9._-]/, '_')
}

// Trims whitespace from the given value and checks whether it is null or empty,
// raising an error depending on whether either or both are acceptable.
def trimAndCheckValue(String name, String value, boolean canBeEmpty = false, boolean canBeNull = false) {
    def trimmed = value?.trim()

    if( !canBeEmpty && trimmed?.empty )
        error("${name} is not defined (empty value)")

    if( !canBeNull && trimmed == null )
        error("${name} is not defined")

    return trimmed
}

// Checks that the given column exists in the inputs CSV file.
def checkInputColumnExists(Map row, String column, String inputCsv) {
    if( !row.containsKey(column) )
        error("${column} column missing from input CSV file ${inputCsv}")
}

// Extract values for the required columns from a row of the inputs CSV file,
// trimming and checking as appropriate.
// A tuple of the id, vcf, tumourBam and normalBam is returned.
// The normalBam value can be unset, e.g. if there is no normal_bam column in
// the CSV file or if the value is empty, in which case a null is returned as
// part of the tuple.
def extractInputRowValues(Map row, String inputCsv, int rowNumber) {
    checkInputColumnExists(row, 'id', inputCsv)
    checkInputColumnExists(row, 'tumour_bam', inputCsv)

    def id = trimAndCheckValue("id in row ${rowNumber} of ${inputCsv}", row.id)

    def safeId = safeName(id)
    if( id != safeId ) {
        log.warn("Renaming id in row ${rowNumber} of ${inputCsv} from '${id}' to '${safeId}'")
        id = safeId
    }

    def vcf = trimAndCheckValue("vcf in row ${rowNumber} of ${inputCsv}", row.vcf)

    def tumourBam = trimAndCheckValue("tumour_bam in row ${rowNumber} of ${inputCsv}", row.tumour_bam)

    def normalBam = trimAndCheckValue("normal_bam in row ${rowNumber} of ${inputCsv}", row.normal_bam, true, true)

    if( !normalBam ) {
        log.warn("Normal BAM not specified for ${id}")
        // ensure that a non-specified normal BAM file is returned as null
        // not an empty string to ease with testing for this later in the
        // workflow
        normalBam = null
    }

    return tuple(id, vcf, tumourBam, normalBam)
}
