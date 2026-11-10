#!/bin/bash
##ENVIRONMENT SETTINGS; CHANGE WITH CAUTION
#SBATCH --export=NONE        #Do not propagate environment
#SBATCH --get-user-env       #Replicate login environment
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=skhu@tamu.edu

##NECESSARY JOB SPECIFICATIONS
#SBATCH --job-name=phylo-04b-compare
#SBATCH --time=72:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=40GB
#SBATCH --output=logs/phylo-04b-compare-log.%j

# After every task of 04-reference-tree.slurm has finished:
#   1. log-likelihood of each search; the best constrained search becomes
#      04-tree/reference.treefile, the tree step 05 places on
#   2. RF distances among the 5 constrained searches (how stable the topology is)
#   3. AU test of all 6 trees (does the data reject the constrained trees?)
#   4. SH-aLRT on the chosen tree, without the constraint, as the support to report

set -eo pipefail
source "${SLURM_SUBMIT_DIR}/config.sh"
load_phylo_env

cd "${TREE_DIR}"
for n in 1 2 3 4 5 6; do
  grep -q "^Date and Time:" "search-${n}/reference.log" 2>/dev/null \
    || { echo "search-${n} has not finished"; exit 1; }
done
mkdir -p compare
cd compare

echo "=== LOG-LIKELIHOOD PER SEARCH (1-5 constrained, 6 unconstrained)"
for n in 1 2 3 4 5 6; do
  ll=$(awk '/^Log-likelihood of the tree:/ { print $5 }' "../search-${n}/reference.iqtree")
  echo -e "${n}\t${ll}"
done | tee search-loglik.tsv

BEST=$(awk '$1 <= 5' search-loglik.tsv | sort -t$'\t' -k2,2 -g -r | head -n 1 | cut -f1)
echo "Best constrained search: ${BEST}"
echo "${BEST}" > chosen-search.txt
cp "../search-${BEST}/reference.treefile" ../reference.treefile
echo "Copied to ${TREE_DIR}/reference.treefile"

echo "=== RF DISTANCES AMONG CONSTRAINED SEARCHES"
cat ../search-{1..5}/reference.treefile > constrained-searches.trees
iqtree2 -t constrained-searches.trees -rf_all --prefix rf > rf.out 2>&1 || { cat rf.out; exit 1; }
[ -s rf.rfdist ] || { echo "rf.rfdist not written"; cat rf.out; exit 1; }
NTIPS=$(grep -c '>' "${ALN_DIR}/reference-trimmed.fasta")
echo "Raw RF, then normalized by the maximum 2(n-3) = $((2 * (NTIPS - 3)))"
cat rf.rfdist
awk -v max=$((2 * (NTIPS - 3))) 'NR > 1 { printf "%s", $1; for (i = 2; i <= NF; i++) printf "\t%.3f", $i / max; print "" }' rf.rfdist

echo "=== AU TEST, ALL SIX TREES IN SEARCH ORDER"
cat ../search-{1..6}/reference.treefile > all-searches.trees
iqtree2 \
  -s "${ALN_DIR}/reference-trimmed.fasta" \
  -m "${TREE_MODEL}" \
  -z all-searches.trees -n 0 -zb 10000 -au \
  -T "${SLURM_CPUS_PER_TASK}" \
  --prefix au-test \
  --seed "${TREE_SEED}"
sed -n '/^USER TREES/,/^deltaL/p' au-test.iqtree

echo "=== SH-aLRT ON THE CHOSEN TREE, WITHOUT THE CONSTRAINT"
iqtree2 \
  -s "${ALN_DIR}/reference-trimmed.fasta" \
  -te ../reference.treefile \
  -m "${TREE_MODEL}" \
  -alrt 1000 \
  -T "${SLURM_CPUS_PER_TASK}" \
  --prefix support \
  --seed "${TREE_SEED}"
cp support.treefile ../reference-support.treefile
echo "Support tree: ${TREE_DIR}/reference-support.treefile"

echo "Done"
