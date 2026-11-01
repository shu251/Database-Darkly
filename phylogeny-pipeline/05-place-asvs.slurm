#!/bin/bash
##ENVIRONMENT SETTINGS; CHANGE WITH CAUTION
#SBATCH --export=NONE        #Do not propagate environment
#SBATCH --get-user-env       #Replicate login environment

##NECESSARY JOB SPECIFICATIONS
#SBATCH --job-name=phylo-05-place
#SBATCH --time=72:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=340GB
#SBATCH --output=phylo-05-place-log.%j

set -eo pipefail
source "${SLURM_SUBMIT_DIR}/config.sh"
load_phylo_env

THREADS=${SLURM_CPUS_PER_TASK}
mkdir -p "${PLACE_DIR}"
cd "${PLACE_DIR}"

echo "Screen ASVs against SILVA for non-eukaryotes"
vsearch --usearch_global "${ASV_FASTA}" \
  --db "${DB_DIR}/silva-138-99-seqs.fasta" \
  --id "${SILVA_SCREEN_ID}" \
  --strand both \
  --maxaccepts 8 --maxrejects 64 --top_hits_only \
  --threads "${THREADS}" \
  --blast6out silva-hits.tsv

# Best hit per ASV, with its SILVA taxonomy
awk -F'\t' 'FNR == NR { tax[$1] = $2; next } !seen[$1]++ { print $1 "\t" $2 "\t" $3 "\t" tax[$2] }' \
  "${DB_DIR}/silva-138-99-tax.tsv" silva-hits.tsv > silva-best-hit.tsv
# Top hits can tie, so only flag an ASV if none of its top hits is eukaryotic
awk -F'\t' 'FNR == NR { tax[$1] = $2; next }
    { asv[$1]; if (tax[$2] ~ /^d__Eukaryota/) euk[$1] }
    END { for (q in asv) if (!(q in euk)) print q }' \
  "${DB_DIR}/silva-138-99-tax.tsv" silva-hits.tsv > asvs-non-eukaryote.txt
echo "ASVs flagged as non-eukaryote: $(wc -l < asvs-non-eukaryote.txt)"

if [ -s asvs-non-eukaryote.txt ]; then
  seqkit grep -v -f asvs-non-eukaryote.txt "${ASV_FASTA}" | seqkit seq -u -w 0 > asvs-screened.fasta
else
  seqkit seq -u -w 0 "${ASV_FASTA}" > asvs-screened.fasta
fi

echo "Add ASVs to the reference alignment without changing its columns"
mafft --6merpair --thread "${THREADS}" --keeplength \
  --addfragments asvs-screened.fasta "${ALN_DIR}/reference-trimmed.fasta" \
  | seqkit seq -u -w 0 > reference-plus-asvs.afa

rm -f query.fasta.gz query.fasta reference.fasta
epa-ng --split "${ALN_DIR}/reference-trimmed.fasta" reference-plus-asvs.afa --outdir . --redo
[ -s query.fasta ] || { echo "epa-ng --split did not produce query.fasta"; exit 1; }

echo "Drop ASVs with fewer than ${MIN_ALIGNED_BP} aligned bases"
awk -v min="${MIN_ALIGNED_BP}" 'NR % 2 == 1 { h = $0; next }
    { s = $0; n = gsub(/[^-.]/, "", s); id = substr(h, 2); print id "\t" n > "asv-aligned-bases.tsv"
      if (n >= min) print h "\n" $0 }' \
  <(seqkit seq -w 0 query.fasta) > query-filtered.fasta
echo "ASVs in query: $(grep -c '>' query-filtered.fasta) of $(grep -c '>' asvs-screened.fasta)"

echo "Fit GTR+G on the fixed reference tree, the model EPA-ng places with"
raxml-ng --evaluate \
  --msa reference.fasta \
  --tree "${TREE_DIR}/reference.treefile" \
  --model GTR+G4+F \
  --prefix reference-model \
  --threads "${THREADS}" \
  --redo

# The bestModel line reads: model string, partition name = sites
MODEL=$(cut -d',' -f1 reference-model.raxml.bestModel)
echo "Model: ${MODEL}"

echo "Place ASVs"
mkdir -p epa
epa-ng \
  --ref-msa reference.fasta \
  --tree reference-model.raxml.bestTree \
  --query query-filtered.fasta \
  --model "${MODEL}" \
  --rate-scalers on \
  --threads "${THREADS}" \
  --outdir epa \
  --redo

echo "Summarize placements"
mkdir -p gappa
gappa examine graft \
  --jplace-path epa/epa_result.jplace \
  --threads "${THREADS}" \
  --out-dir gappa \
  --allow-file-overwriting

gappa examine edpl \
  --jplace-path epa/epa_result.jplace \
  --threads "${THREADS}" \
  --out-dir gappa \
  --allow-file-overwriting

# Taxonomic labels depend on the root, and the tree's own root is arbitrary, so root on Amorphea
awk -F'\t' '{ split($2, r, ";"); if (r[2] == "Obazoa" || r[2] == "Amoebozoa") print $1 }' \
  "${REF_DIR}/reference-taxonomy.tsv" > root-outgroup.txt
echo "Outgroup references: $(wc -l < root-outgroup.txt)"

gappa examine assign \
  --jplace-path epa/epa_result.jplace \
  --taxon-file "${REF_DIR}/reference-taxonomy.tsv" \
  --root-outgroup root-outgroup.txt \
  --per-query-results \
  --best-hit \
  --threads "${THREADS}" \
  --out-dir gappa \
  --allow-file-overwriting

echo "Done"
