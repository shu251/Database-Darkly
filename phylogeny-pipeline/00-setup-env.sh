#!/bin/bash
# Run once on a Grace login node, from this folder: bash 00-setup-env.sh
set -eo pipefail
source ./config.sh

mkdir -p "${WORKDIR}"
export CONDA_PKGS_DIRS=${WORKDIR}/conda-pkgs   # keeps the package cache out of the home quota

module purge
module load "${ANACONDA_MODULE}"
[ -n "${PHYLO_ENV}" ] || { echo "PHYLO_ENV is empty: check config.sh"; exit 1; }
echo "Creating environment at: ${PHYLO_ENV}"
conda --version
conda env create --prefix="${PHYLO_ENV}" --file=environment.yml

source activate "${PHYLO_ENV}"
conda env export > "${WORKDIR}/conda-env-versions.yml"
for tool in seqkit vsearch mafft trimal iqtree2 raxml-ng epa-ng gappa; do
  command -v "${tool}" || { echo "MISSING: ${tool}"; exit 1; }
done

rm -rf "${CONDA_PKGS_DIRS}"   # the group scratch quota limits file counts
echo "Environment ready: ${PHYLO_ENV}"
