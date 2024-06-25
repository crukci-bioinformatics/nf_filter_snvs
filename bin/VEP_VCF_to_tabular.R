#!/usr/bin/env Rscript

# Take two input VCFs (indels and snvs), converts them to tabular format and
# merges them into a single file

suppressPackageStartupMessages(library(tidyverse))

args <- commandArgs(trailingOnly = TRUE)
vcfOne <- args[1]
vcfTwo <- args[2]
outFil <- args[3]

vcfToTab <- function(vcf_file) {

    print(vcf_file)

    vep_annotation_types <- tibble(name = readLines(vcf_file)) %>%
        filter(str_detect(name, "INFO=<ID=CSQ")) %>%
        mutate(name = str_remove(name, "^.*Format: ")) %>%
        mutate(name = str_remove(name, "\">$")) %>%
        separate_rows(name, sep = "\\|") %>%
        mutate(across(name, ~str_replace(., "AF", "AF_VEP"))) %>%
        transmute(index = row_number(), name)

    variants <- read_tsv(vcf_file,
                         comment = "##",
                         col_types = cols(`#CHROM` = "f",
                                          POS = "i",
                                          ID = "c",
                                          REF = "c",
                                          ALT = "c",
                                          QUAL = "c",
                                          FILTER = "c",
                                          INFO = "c",
                                          .default = "c"))

    variants <- variants %>%
      rename(Chromosome = `#CHROM`,
            Position = POS,
            id = ID,
            Ref = REF,
            Alt = ALT,
            quality = QUAL,
            Filter = FILTER,
            info = INFO)

    colnames(variants)[10] <- "DETAILS"

    details <- variants %>%
        mutate(row_number = row_number()) %>%
        select(row_number, FORMAT, DETAILS) %>%
        separate_longer_delim(c(FORMAT, DETAILS), delim = ":") %>%
        pivot_wider(names_from = "FORMAT", values_from = "DETAILS") %>%
        select(row_number, GT, AD, AF, DP)

    vep_annotations <- variants %>%
        transmute(row_number = row_number(),
                  Chromosome,
                  Position,
                  Ref,
                  Alt,
                  Filter,
                  value = info) %>%
        left_join(details, by = "row_number") %>%
        mutate(value = str_remove(value, "^.*CSQ=")) %>%
        separate_rows(value, sep = ",") %>%
        mutate(vep_consequence_index = row_number(), .by = "row_number") %>%
        separate_rows(value, sep = "\\|") %>%
        mutate(index = row_number(),
               .by = c(vep_consequence_index, row_number)) %>%
        left_join(vep_annotation_types, by = "index") %>%
        select(-index) %>%
        pivot_wider(names_from = "name", values_from = "value") %>%
        select(Chromosome,
               Position,
               Ref,
               Alt,
               Genotype = GT,
               AlleleDepth = AD,
               AlleleFrequency = AF,
               Depth = DP,
               vep_consequence_index,
               Filter,
               `Variant type` = VARIANT_CLASS,
               Consequence,
               `Ensembl Gene ID` = Gene,
               `Gene symbol` = SYMBOL,
               Impact = IMPACT,
               Codons,
               `HGVS cDNA effect` = HGVSc,
               `HGVS protein effect` = HGVSp)

    vep_annotations
}

tabOne <- vcfToTab(vcfOne)
tabTwo <- vcfToTab(vcfTwo)

bind_rows(tabOne, tabTwo) %>%
    arrange(Chromosome, Position) %>%
    write_tsv(outFil)

sessionInfo()