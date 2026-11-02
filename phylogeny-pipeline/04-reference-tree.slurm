#!/bin/bash
##ENVIRONMENT SETTINGS; CHANGE WITH CAUTION
#SBATCH --export=NONE        #Do not propagate environment
#SBATCH --get-user-env       #Replicate login environment
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=skhu@tamu.edu

##NECESSARY JOB SPECIFICATIONS
#SBATCH --job-name=phylo-04-tree
#SBATCH --time=168:00:00           # 7 days. If it times out, resubmit: IQ-TREE resumes from its checkpoint
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=340GB
#SBATCH --output=phylo-04-tree-log.%j

set -eo pipefail
source "${SLURM_SUBMIT_DIR}/config.sh"
load_phylo_env

mkdir -p "${TREE_DIR}"
cd "${TREE_DIR}"

echo "Build the reference tree"
iqtree2 \
  -s "${ALN_DIR}/reference-trimmed.fasta" \
  --prefix reference \
  -m MFP -mset GTR -mfreq F -mrate G,R \
  -B 1000 -alrt 1000 \
  -T "${SLURM_CPUS_PER_TASK}" \
  --mem 320G \
  --seed 20261101

echo "Done"
