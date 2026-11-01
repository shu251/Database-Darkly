#!/bin/bash
##ENVIRONMENT SETTINGS; CHANGE WITH CAUTION
#SBATCH --export=NONE        #Do not propagate environment
#SBATCH --get-user-env       #Replicate login environment

##NECESSARY JOB SPECIFICATIONS
#SBATCH --job-name=phylo-03-align
#SBATCH --time=96:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=180GB
#SBATCH --output=phylo-03-align-log.%j

set -eo pipefail
source "${SLURM_SUBMIT_DIR}/config.sh"
load_phylo_env

mkdir -p "${ALN_DIR}"
cd "${ALN_DIR}"

echo "Align references"
# FFT-NS-i. --auto picks the rougher FFT-NS-2 at this many sequences
mafft --retree 2 --maxiterate 2 --thread "${SLURM_CPUS_PER_TASK}" "${REF_DIR}/reference.fasta" > reference-aligned.fasta

echo "Trim columns that are mostly gaps"
trimal -in reference-aligned.fasta -out trimmed-raw.fasta -gt "${TRIM_GT}" -fasta
seqkit seq -u -w 0 trimmed-raw.fasta > reference-trimmed.fasta
rm trimmed-raw.fasta

echo "Alignment length before and after trimming"
seqkit stats -a reference-aligned.fasta reference-trimmed.fasta

echo "Bases left after trimming in force-added references"
for id in ${FORCE_REFERENCES}; do
  seqkit grep -p "${id}" reference-trimmed.fasta | seqkit seq -g | seqkit fx2tab -n -i -l
done

echo "Done"
