#!/bin/bash

echo ${PATH}

VEP_VCF_to_tabular.R !{vcfs} !{variantsTab}
