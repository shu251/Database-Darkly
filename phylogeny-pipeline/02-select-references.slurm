#!/bin/bash
##ENVIRONMENT SETTINGS; CHANGE WITH CAUTION
#SBATCH --export=NONE        #Do not propagate environment
#SBATCH --get-user-env=L     #Replicate login environment

##NECESSARY JOB SPECIFICATIONS
#SBATCH --job-name=phylo-02-refs
#SBATCH --time=12:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=90GB
#SBATCH --output=phylo-02-refs-log.%j

set -eo pipefail
source "${SLURM_SUBMIT_DIR}/config.sh"
load_phylo_env

mkdir -p "${REF_DIR}"
cd "${REF_DIR}"

echo "Keep nuclear eukaryote taxonomy (organellar entries are Eukaryota:plas, :mito, etc.)"
awk -F'\t' '$1 != "Feature ID" && $2 ~ /^Eukaryota;/ { gsub(/; /, ";", $2); print $1 "\t" $2 }' \
  "${PR2_TAX_TSV}" > pr2-euk-tax.tsv
[ -s pr2-euk-tax.tsv ] || { echo "No eukaryote taxonomy found: check the format of ${PR2_TAX_TSV}"; exit 1; }

echo "PR2 sequence lengths, all sequences"
seqkit stats -a "${DB_DIR}/pr2-5.1.1-seqs.fasta"

echo "Filter by taxonomy, length and ambiguous bases"
cut -f1 pr2-euk-tax.tsv > pr2-euk-ids.txt
seqkit grep -f pr2-euk-ids.txt "${DB_DIR}/pr2-5.1.1-seqs.fasta" \
  | seqkit seq -i -u --rna2dna -m "${REF_MIN_LEN}" -M "${REF_MAX_LEN}" -w 0 \
  | awk -v max="${REF_MAX_AMBIG}" 'NR % 2 == 1 { h = $0; next }
      { s = $0; n = gsub(/[^ACGT]/, "", s); if (n / length($0) <= max) print h "\n" $0 }' \
  > pr2-euk-long.fasta
seqkit stats -a pr2-euk-long.fasta
[ -s pr2-euk-long.fasta ] || { echo "No sequences passed: check that the PR2 ids match the taxonomy file"; exit 1; }

echo "Cluster at ${REF_CLUSTER_ID}"
vsearch --cluster_fast pr2-euk-long.fasta \
  --id "${REF_CLUSTER_ID}" \
  --strand plus \
  --qmask none \
  --threads "${SLURM_CPUS_PER_TASK}" \
  --fasta_width 0 \
  --centroids pr2-euk-centroids.fasta

echo "Cap sequences per taxonomic group"
awk 'NR % 2 == 1 { id = substr($1, 2); next } { print id "\t" length($0) }' pr2-euk-centroids.fasta \
  | sort -t$'\t' -k2,2nr -k1,1 > centroid-lengths.tsv
awk -v cap_named="${CAP_NAMED_GENUS}" -v cap_x="${CAP_X_GENUS}" -v cap_coarse="${CAP_COARSE_FAMILY}" \
  -f "${SLURM_SUBMIT_DIR}/select-references.awk" pr2-euk-tax.tsv centroid-lengths.tsv > reference-ids.txt

seqkit grep -f reference-ids.txt pr2-euk-centroids.fasta | seqkit seq -w 0 > reference.fasta
awk -F'\t' 'FNR == NR { keep[$1]; next } $1 in keep' reference-ids.txt pr2-euk-tax.tsv > reference-taxonomy.tsv

echo "Selected references"
seqkit stats -a reference.fasta
echo "References per division"
cut -f2 reference-taxonomy.tsv | cut -d';' -f3 | sort | uniq -c | sort -k1,1nr | tee references-per-division.txt

n_ref=$(wc -l < reference-ids.txt)
[ "${n_ref}" -le 6000 ] || echo "WARNING: ${n_ref} references. Consider lowering the caps before building the tree."

echo "Done"
