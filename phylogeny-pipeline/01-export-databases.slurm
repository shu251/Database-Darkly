#!/bin/bash
##ENVIRONMENT SETTINGS; CHANGE WITH CAUTION
#SBATCH --export=NONE        #Do not propagate environment
#SBATCH --get-user-env       #Replicate login environment

##NECESSARY JOB SPECIFICATIONS
#SBATCH --job-name=phylo-01-export
#SBATCH --time=04:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16GB
#SBATCH --output=phylo-01-export-log.%j

set -eo pipefail
source "${SLURM_SUBMIT_DIR}/config.sh"

module purge
module load "${QIIME_MODULE}"

mkdir -p "${DB_DIR}/tmp"
export TMPDIR=${DB_DIR}/tmp

echo "Export PR2 sequences"
qiime tools export --input-path "${PR2_SEQS_QZA}" --output-path "${DB_DIR}/pr2-seqs"
mv "${DB_DIR}/pr2-seqs/dna-sequences.fasta" "${DB_DIR}/pr2-5.1.1-seqs.fasta"

echo "Export SILVA sequences and taxonomy"
qiime tools export --input-path "${SILVA_SEQS_QZA}" --output-path "${DB_DIR}/silva-seqs"
mv "${DB_DIR}/silva-seqs/dna-sequences.fasta" "${DB_DIR}/silva-138-99-seqs.fasta"

qiime tools export --input-path "${SILVA_TAX_QZA}" --output-path "${DB_DIR}/silva-tax"
mv "${DB_DIR}/silva-tax/taxonomy.tsv" "${DB_DIR}/silva-138-99-tax.tsv"

rmdir "${DB_DIR}/pr2-seqs" "${DB_DIR}/silva-seqs" "${DB_DIR}/silva-tax" "${DB_DIR}/tmp"

echo "Check the formats"
head -c 300 "${DB_DIR}/pr2-5.1.1-seqs.fasta"; echo
head -n 3 "${PR2_TAX_TSV}"
head -n 3 "${DB_DIR}/silva-138-99-tax.tsv"

echo "Done"
