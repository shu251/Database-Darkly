# Shared settings, sourced by every step. Edit here, not in the job scripts.

# Inputs
ASV_FASTA=/scratch/group/hu-lab/deepsea-18S-merged-outputs/ref-seqs/ref-seqs-deepsea-DB_052025.fasta
PR2_SEQS_QZA=/scratch/group/hu-lab/databases/PR2/pr2_version_5.1.1_seqs.qza
PR2_TAX_TSV=/scratch/group/hu-lab/databases/PR2/pr2-tax_5.1.1.tsv
SILVA_SEQS_QZA=/scratch/group/hu-lab/databases/silva/silva-138-99-seqs.qza
SILVA_TAX_QZA=/scratch/group/hu-lab/databases/silva/silva-138-99-tax.qza

# All outputs go here
WORKDIR=/scratch/group/hu-lab/deepsea-18S-merged-outputs/phylo-placement
DB_DIR=${WORKDIR}/01-databases
REF_DIR=${WORKDIR}/02-references
ALN_DIR=${WORKDIR}/03-alignment
TREE_DIR=${WORKDIR}/04-tree
PLACE_DIR=${WORKDIR}/05-placement

# Software
QIIME_MODULE=QIIME2/2024.10-Amplicon
ANACONDA_MODULE=Anaconda3/2026.07-1
PHYLO_ENV=${WORKDIR}/conda-env

# Reference selection (02)
REF_MIN_LEN=1200       # near-full-length 18S only
REF_MAX_LEN=3000       # raise this if lineages with long 18S insertions drop out
REF_MAX_AMBIG=0.01     # maximum fraction of non-ACGT bases
REF_CLUSTER_ID=0.97
CAP_NAMED_GENUS=1      # sequences kept per named genus
CAP_X_GENUS=5          # sequences kept per unnamed genus (e.g. Family_X), to retain environmental clades
CAP_COARSE_FAMILY=1    # sequences kept per family in Metazoa, Fungi and Streptophyta

# Alignment trimming (03)
TRIM_GT=0.1            # keep columns with sequence in at least this fraction of references

# ASV screening (05)
SILVA_SCREEN_ID=0.90   # drop ASVs whose best SILVA hit at this identity is not eukaryotic
MIN_ALIGNED_BP=150     # drop ASVs with fewer aligned bases than this after trimming

load_phylo_env() {
  module purge
  module load "${ANACONDA_MODULE}"
  source activate "${PHYLO_ENV}"
}
