
version ?= latest

build:
	docker build --tag crukcibioinformatics/filter-snvs:${version} .

release: build
	docker push crukcibioinformatics/filter-snvs:${version}

singularity: build
	singularity build crukcibioinformatics/filter-snvs-${version}.sif docker-daemon://crukcibioinformatics/filter-snvs:${version}

