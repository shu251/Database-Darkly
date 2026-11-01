#!/bin/bash
# Run once on a Grace login node, from this folder: bash 00-setup-env.sh
set -eo pipefail
source ./config.sh

mkdir -p "${WORKDIR}"
export CONDA_PKGS_DIRS=${WORKDIR}/conda-pkgs   # keeps the package cache out of the home quota

module purge
module load "${CONDA_MODULE}"
conda env create --prefix "${CONDA_ENV}" --file environment.yml

source activate "${CONDA_ENV}"
conda env export > "${WORKDIR}/conda-env-versions.yml"
for tool in seqkit vsearch mafft trimal iqtree2 raxml-ng epa-ng gappa; do
  command -v "${tool}" || { echo "MISSING: ${tool}"; exit 1; }
done
echo "Environment ready: ${CONDA_ENV}"
