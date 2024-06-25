# Filter SNVs

This workflow uses the
[`htsjdk-tools`](https://github.com/crukci-bioinformatics/htsjdk-tools) to
filter SNVs. It then annotates the variants (both SNVs and Indels) using the VEP
and creates tabular output files combining both SNVs and Indels.

The pipeline input is a csv file with the following columns:

* `id` - sample ID
* `vcf` - path to the VCF file
* `tumourBam` - path to the BAM file for the tumour sample
* `normalBam` - path to the BAM file for the normal sample (can be empty if
there is no normal sample, but the column must be present)

The paths to the vcf and bam files can be provided as either absolute or
relative paths. Alternatively, just the file names can be provided and the
relevant directories can be specified using the `--VCF_DIR` and `--BAM_DIR`
options.

You will also need to download the relevant VEP cache files. These can be
downloaded from the Ensembl FTP site. The cache files are required for the VEP
to run. 

If the vcf files have been generated using the NF-core Sarek pipeline, then
this workflow can be run using the `--sarek_output` option. If VCF_DIR is
provided and "--sarek_output" is provided, the pipeline will add a directory
based on the sample ID to the VCF_DIR as per the standard Sarek output directory
structure.  i.e. if the VCF_DIR is `/path/to/vcf` and the sample "id" is
`sample1` and the vcf file is "sample1.vcf.gz", the pipeline will look for the
VCF file in `/path/to/vcf/sample1/sample1.vcf.gz`.

In addition to the above input file you should also specify in a parameters yaml
file the following:

* REFERENCE_FASTA - path to the reference fasta file for the genome     
* vepCache - path to the VEP cache directory     
* vepFasta - path to the VEP fasta file     
* species - species to use for VEP, e.g. "mus_musculus"     
* assembly - species assembly to use for VEP, e.g. "GRCm38"     

Other optional parameters that can be specified in the parameters yaml file are:

BAM_DIR - directory containing the BAM files (default: null)     
VCF_DIR - directory containing the VCF files (default: null)     
INPUTS_CSV - path to the input csv file (default: "inputs.csv")    
sarek_output - flag to indicate that the VCF files are in the Sarek output format (default: false)    
OUTPUT_DIR - directory to write the output files to (default: "filtered_vcfs")   
INTERVALS - path to the intervals file to use for the GATK variant calling (default: null)        
SNV_FILTERS - filters to apply to the SNVs (default: see `nextflow.config`)
