#!/bin/bash
##ENVIRONMENT SETTINGS; CHANGE WITH CAUTION
#SBATCH --export=NONE        #Do not propagate environment
#SBATCH --get-user-env       #Replicate login environment

##NECESSARY JOB SPECIFICATIONS
#SBATCH --job-name=phylo-smoke-test
#SBATCH --time=06:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=90GB
#SBATCH --output=logs/phylo-smoke-test-log.%j

# Runs the real steps 02-05 on a small random sample, in phylo-placement/smoke-test/.
# Submit after step 01 has finished. The results test the commands, not the biology.

set -eo pipefail
source "${SLURM_SUBMIT_DIR}/config.sh"
load_phylo_env

for f in pr2-5.1.1-seqs.fasta silva-138-99-seqs.fasta silva-138-99-tax.tsv; do
  [ -s "${DB_DIR}/${f}" ] || { echo "Missing ${DB_DIR}/${f}: run step 01 first"; exit 1; }
done

TEST=${WORKDIR}/smoke-test
rm -rf "${TEST}"
mkdir -p "${TEST}/01-databases"

echo "Sample about 0.2% of PR2 and 1% of the ASVs"
seqkit sample -s 11 -p 0.002 "${DB_DIR}/pr2-5.1.1-seqs.fasta" > "${TEST}/01-databases/pr2-5.1.1-seqs.fasta"
seqkit sample -s 11 -p 0.01 "${ASV_FASTA}" > "${TEST}/asvs.fasta"
ln -s "${DB_DIR}/silva-138-99-seqs.fasta" "${DB_DIR}/silva-138-99-tax.tsv" "${TEST}/01-databases/"

export TEST_WORKDIR=${TEST}
export TEST_ASV_FASTA=${TEST}/asvs.fasta
source "${SLURM_SUBMIT_DIR}/config.sh"

for step in 02-select-references 03-align-trim 04-reference-tree 05-place-asvs; do
  echo "=== RUNNING ${step}"
  bash "${SLURM_SUBMIT_DIR}/${step}.slurm"
  load_phylo_env
done

echo "=== SUMMARY"
seqkit stats -a "${REF_DIR}/reference.fasta" "${ALN_DIR}/reference-trimmed.fasta" "${PLACE_DIR}/query-filtered.fasta"
grep -m1 'Best-fit model' "${TREE_DIR}/reference.iqtree"
ls -la "${PLACE_DIR}" "${PLACE_DIR}/epa" "${PLACE_DIR}/gappa"
head -n 5 "${PLACE_DIR}/gappa/"*per_query.tsv

echo "=== GAPPA ASSIGN WITH A DELIBERATELY SPLIT OUTGROUP"
cd "${PLACE_DIR}"
{
  awk -F'\t' '{ split($2, r, ";"); if (r[2] == "Obazoa") print $1 }' "${REF_DIR}/reference-taxonomy.tsv" | head -n 2
  awk -F'\t' '{ split($2, r, ";"); if (r[2] == "TSAR") print $1 }' "${REF_DIR}/reference-taxonomy.tsv" | head -n 2
} > split-outgroup.txt
cat split-outgroup.txt

mkdir -p gappa-split-outgroup
set +e
gappa examine assign \
  --jplace-path epa/epa_result.jplace \
  --taxon-file "${REF_DIR}/reference-taxonomy.tsv" \
  --root-outgroup split-outgroup.txt \
  --per-query-results \
  --best-hit \
  --threads "${SLURM_CPUS_PER_TASK}" \
  --out-dir gappa-split-outgroup \
  --allow-file-overwriting
echo "Exit code with split outgroup: $?"
set -e

echo "Done"
