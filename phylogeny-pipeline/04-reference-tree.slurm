#!/bin/bash
##ENVIRONMENT SETTINGS; CHANGE WITH CAUTION
#SBATCH --export=NONE        #Do not propagate environment
#SBATCH --get-user-env       #Replicate login environment
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=skhu@tamu.edu

##NECESSARY JOB SPECIFICATIONS
#SBATCH --job-name=phylo-04-tree
#SBATCH --array=1-6                # 1-5: constrained searches, 6: unconstrained search for the AU test
#SBATCH --time=168:00:00           # 7 days. If a task times out, resubmit it alone (--array=N): it resumes from its checkpoint
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=40GB                 # IQ-TREE needed about 3 GB on this alignment
#SBATCH --output=logs/phylo-04-tree-log.%A_%a

# Independent ML searches on the same alignment and model, differing only in seed.
# A single search did not reach the best tree (its own bootstrap consensus scored
# higher), so 04b-compare-trees.slurm picks the best constrained search for placement.
# Run outside an array (smoke test), this does search 1 only and uses it as the tree.

set -eo pipefail
source "${SLURM_SUBMIT_DIR}/config.sh"
load_phylo_env

N=${SLURM_ARRAY_TASK_ID:-1}
RUN_DIR=${TREE_DIR}/search-${N}
mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"

# A finished run makes IQ-TREE refuse to start. A timed-out run is fine: it resumes.
if [ -f reference.log ] && grep -q "^Date and Time:" reference.log; then
  echo "A finished search is already in ${RUN_DIR}. Move it aside, then resubmit."
  exit 1
fi

CONSTRAINT=()
if [ "${N}" -le 5 ]; then
  echo "Search ${N}: constrained. Backbone groups (references per group):"
  awk -f "${SLURM_SUBMIT_DIR}/make-constraint.awk" "${REF_DIR}/reference-taxonomy.tsv" > constraint.tree
  CONSTRAINT=(-g constraint.tree)
else
  echo "Search ${N}: unconstrained, for the AU test of the constraint"
fi

iqtree2 \
  -s "${ALN_DIR}/reference-trimmed.fasta" \
  "${CONSTRAINT[@]}" \
  --prefix reference \
  -m "${TREE_MODEL}" \
  -nstop "${TREE_NSTOP}" \
  -T "${SLURM_CPUS_PER_TASK}" \
  --seed $((TREE_SEED + N))

if [ -z "${SLURM_ARRAY_TASK_ID}" ]; then
  cp reference.treefile "${TREE_DIR}/reference.treefile"
  echo "Not an array job: search 1 copied to ${TREE_DIR}/reference.treefile"
fi

echo "Done"
