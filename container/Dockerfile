FROM debian:11.7-slim

LABEL authors="Matt Eldridge" \
      authors="Ash Sawle" \
      version="0.1-snapshot" \
      description="Software package/tool dependencies for the filter SNVs pipeline."

RUN apt-get update && \
    apt-get install -y build-essential curl git procps && \
    apt-get clean

RUN curl -L -O https://github.com/conda-forge/miniforge/releases/download/24.3.0-0/miniforge3-linux-x86_64.sh && \
    mkdir -p /opt && \
    sh miniforge3-linux-x86_64.sh -b -p /opt/miniforge3 && \
    rm miniforge3-linux-x86_64.sh

COPY conda.yml .

RUN /opt/miniforge3/bin/mamba env create -f conda.yml && /opt/miniforge3/bin/mamba clean -a

COPY conda_R.yaml .

RUN /opt/miniforge3/bin/mamba env create -f conda_R.yaml && /opt/miniforge3/bin/mamba clean -a

ARG HTSJDK_TOOLS_VERSION=1.0

RUN curl -L https://github.com/crukci-bioinformatics/htsjdk-tools/releases/download/${HTSJDK_TOOLS_VERSION}/htsjdk-tools-${HTSJDK_TOOLS_VERSION}-distribution.tar.gz -o /opt/htsjdk-tools-${HTSJDK_TOOLS_VERSION}-distribution.tar.gz && \
    tar zxf /opt/htsjdk-tools-${HTSJDK_TOOLS_VERSION}-distribution.tar.gz -C /opt && \
    rm /opt/htsjdk-tools-${HTSJDK_TOOLS_VERSION}-distribution.tar.gz

ENV PATH /opt/miniforge3/envs/filter_snvs_env_R/bin:/opt/miniforge3/envs/filter-snvs-pipeline/bin:/opt/htsjdk-tools-${HTSJDK_TOOLS_VERSION}/bin:$PATH

