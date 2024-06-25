
version ?= latest

build:
	docker build --tag filter_snvs_pipeline:${version} .

singularity: build
	singularity build filter_snvs_pipeline-${version}.sif docker-daemon://filter_snvs_pipeline:${version}
