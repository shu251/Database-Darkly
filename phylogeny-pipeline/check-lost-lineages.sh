#!/bin/bash
# Run after step 02, from this folder: bash check-lost-lineages.sh
# Writes 02-references/lost-lineages.tsv. n_passed_filters = 0 means every sequence in
# the lineage was too short, too long or too ambiguous; above 0 means its sequences
# passed but were absorbed into another lineage's cluster at 97% or removed by a cap.
set -eo pipefail
source ./config.sh
load_phylo_env

script_dir=$(pwd)
cd "${REF_DIR}"

seqkit seq -n -i pr2-euk-long.fasta > passed-ids.txt
seqkit fx2tab -n -i -l "${DB_DIR}/pr2-5.1.1-seqs.fasta" | cut -f1,2 > pr2-lengths.tsv

awk -f "${script_dir}/find-lost-lineages.awk" \
  reference-taxonomy.tsv passed-ids.txt pr2-lengths.tsv pr2-euk-tax.tsv \
  | { IFS= read -r header; echo "${header}"; sort -t$'\t' -k2,2; } > lost-lineages.tsv
rm passed-ids.txt pr2-lengths.tsv

echo "Lost lineages per rank"
tail -n +2 lost-lineages.tsv | cut -f1 | sort | uniq -c
echo "Written to ${REF_DIR}/lost-lineages.tsv"
