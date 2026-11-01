#!/bin/bash
##ENVIRONMENT SETTINGS; CHANGE WITH CAUTION
#SBATCH --export=NONE        #Do not propagate environment
#SBATCH --get-user-env       #Replicate login environment

##NECESSARY JOB SPECIFICATIONS
#SBATCH --job-name=phylo-check-aln
#SBATCH --time=12:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=90GB
#SBATCH --output=phylo-check-aln-log.%j

# Checks a trimmed reference alignment before the tree job, including how much of the
# ASVs (a sample of about 300) survives in its columns.
# Usage: sbatch check-alignment.slurm [trimmed alignment]

set -eo pipefail
source "${SLURM_SUBMIT_DIR}/config.sh"
load_phylo_env

ALN=${1:-${ALN_DIR}/reference-trimmed.fasta}
OUT=$(dirname "${ALN}")/check
mkdir -p "${OUT}"
cd "${OUT}"
echo "Checking ${ALN}"

quantiles() {
  sort -t$'\t' -k4,4n "$1" | awk -F'\t' '{ v[NR] = $4 } END {
    printf "n=%d min=%s p1=%s p5=%s p25=%s median=%s p75=%s max=%s\n", NR, v[1], v[int(NR * 0.01) + 1],
      v[int(NR * 0.05) + 1], v[int(NR * 0.25) + 1], v[int(NR * 0.5) + 1], v[int(NR * 0.75) + 1], v[NR] }'
}

echo "=== ALIGNMENT"
seqkit stats -a "${ALN}"
awk '/^>/ { next } { n++; s = $0; g += gsub(/-/, "", s); t += length($0) }
     END { printf "gaps: %.1f%% of %d columns x %d sequences\n", 100 * g / t, t / n, n }' "${ALN}"

echo "=== REFERENCES: FRACTION OF EACH SEQUENCE KEPT"
awk -f "${SLURM_SUBMIT_DIR}/alignment-coverage.awk" "${REF_DIR}/reference.fasta" "${ALN}" > reference-coverage.tsv
quantiles reference-coverage.tsv
echo "References below 50% kept: $(awk -F'\t' '$4 < 0.5' reference-coverage.tsv | wc -l)"
echo "Lowest 30: id, length, bases kept, fraction, taxonomy"
sort -t$'\t' -k4,4n reference-coverage.tsv \
  | awk -F'\t' 'FNR == NR { tax[$1] = $2; next } FNR <= 30 { print $0 "\t" tax[$1] }' "${REF_DIR}/reference-taxonomy.tsv" -

echo "=== REFERENCES WITH UNDER 1,000 BASES KEPT, BY SUBDIVISION"
awk -F'\t' 'FNR == NR { split($2, r, ";"); group[$1] = r[3] ";" r[4]; next }
            $3 < 1000 { n[group[$1]]++; total++ }
            END { print total + 0, "total"; for (g in n) print n[g], g }' \
  "${REF_DIR}/reference-taxonomy.tsv" reference-coverage.tsv | sort -k1,1nr

echo "=== ASV SAMPLE: FRACTION OF EACH ASV KEPT"
seqkit sample -s 11 -p 0.011 "${ASV_FASTA}" | seqkit seq -u -w 0 > asv-sample.fasta
seqkit seq -n -i "${ALN}" > aln-ids.txt
mafft --6merpair --thread "${SLURM_CPUS_PER_TASK}" --keeplength \
  --addfragments asv-sample.fasta "${ALN}" 2> /dev/null \
  | seqkit seq -u -w 0 | seqkit grep -w 0 -v -f aln-ids.txt > asv-sample-aligned.fasta
awk -f "${SLURM_SUBMIT_DIR}/alignment-coverage.awk" asv-sample.fasta asv-sample-aligned.fasta > asv-coverage.tsv
quantiles asv-coverage.tsv
echo "ASVs below ${MIN_ALIGNED_BP} bases kept: $(awk -F'\t' -v m="${MIN_ALIGNED_BP}" '$3 < m' asv-coverage.tsv | wc -l)"

echo "Done"
