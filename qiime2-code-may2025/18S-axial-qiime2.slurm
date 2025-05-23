#!/bin/bash
##ENVIRONMENT SETTINGS; CHANGE WITH CAUTION
#SBATCH --export=NONE        #Do not propagate environment
#SBATCH --get-user-env=L     #Replicate login environment

##NECESSARY JOB SPECIFICATIONS
#SBATCH --job-name=18S-qiime2
#SBATCH --time=72:00:00            # 72 hours
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24        # 32 threads
#SBATCH --mem=340GB               # lots of memory, but never the maximum (which is 384G)
#SBATCH --output=18S-qiime2-log.%j

# Load qiime2
module load QIIME2/2024.10-Amplicon

echo "import sequences"

qiime tools import \
 --type 'SampleData[PairedEndSequencesWithQuality]' \
 --input-path /scratch/group/hu-lab/qiime-axial-2023_18S_16S/manifest-axial-euk \
 --output-path /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/pe-input-18s.qza \
 --input-format PairedEndFastqManifestPhred33V2

qiime demux summarize \
 --i-data /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/pe-input-18s.qza \
 --o-visualization /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/pe-input-18s.qzv

echo "Use cutadapt to remove primer sequences"

qiime cutadapt trim-paired \
 --i-demultiplexed-sequences /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/pe-input-18s.qza \
 --p-cores $SLURM_CPUS_PER_TASK \
 --p-front-f CCAGCASCYGCGGTAATTCC \
 --p-front-r ACTTTCGTTCTTGATYRA \
 --p-error-rate 0.1 \
 --p-overlap 3 \
 --p-match-adapter-wildcards \
 --o-trimmed-sequences /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/pe-trimmed-18s.qza

qiime demux summarize \
  --i-data /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/pe-trimmed-18s.qza \
  --o-visualization /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/pe-trimmed-18s.qzv

echo "Starting DADA2 denoising, error prediction, chimera removal, and ASV determination..."

qiime dada2 denoise-paired \
        --i-demultiplexed-seqs /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/pe-trimmed-18s.qza \
        --p-trunc-len-f 260 \
        --p-trunc-len-r 225 \
        --p-max-ee-f 2 \
        --p-max-ee-r 2 \
        --p-min-overlap 10 \
        --p-pooling-method independent \
        --p-n-reads-learn 1000000 \
        --p-n-threads $SLURM_CPUS_PER_TASK \
        --p-chimera-method pooled \
        --o-table /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/pe-trimmed-asv-table-18s.qza \
        --o-representative-sequences /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/pe-trimmed-asv-refseq-18s.qza \
        --o-denoising-stats /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/pe-trimmed-asv-dada2stats-18s.qza

echo "dada2 step completed"

qiime tools export \
	--input-path /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/pe-trimmed-asv-table-18s.qza \
	--output-path /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/

biom convert \
	-i /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/feature-table.biom \
	-o /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/axial-2023-18s-asv-table.tsv \
	--to-tsv

echo "asv table is prepped"

qiime metadata tabulate \
	--m-input-file /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/pe-trimmed-asv-dada2stats-18s.qza \
	--o-visualization /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/pe-trimmed-asv-dada2stats-18s.qzv


qiime feature-table merge \
        --i-tables /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/pe-trimmed-asv-table-18s.qza \
        --i-tables /scratch/group/hu-lab/microeuk-survey-18S/tag-seq-analysis/microeuk-merged-output/microeuk-merged-asv-table.qza \
        --o-merged-table /scratch/group/hu-lab/deepsea-18S-merged-outputs/deepsea-18s-merged-asv-table-05022025.qza

qiime tools export \
        --input-path /scratch/group/hu-lab/deepsea-18S-merged-outputs/deepsea-18s-merged-asv-table-05022025.qza \
        --output-path /scratch/group/hu-lab/deepsea-18S-merged-outputs/

biom convert \
        -i /scratch/group/hu-lab/deepsea-18S-merged-outputs/feature-table.biom \
        -o /scratch/group/hu-lab/deepsea-18S-merged-outputs/deepsea-18s-merged-asv-table-05022025.tsv \
        --to-tsv

echo "merged asv table prepped"


qiime feature-table merge-seqs \
        --i-data /scratch/group/hu-lab/qiime-axial-2023_18S_16S/18S_output_axial_2023/pe-trimmed-asv-refseq-18s.qza \
        --i-data /scratch/group/hu-lab/microeuk-survey-18S/tag-seq-analysis/microeuk-merged-output/microeuk-merged-ref-seqs.qza \
        --o-merged-data /scratch/group/hu-lab/deepsea-18S-merged-outputs/deepsea-18s-merged-seqs-05022025.qza

echo "assign taxonomy"

qiime feature-classifier classify-consensus-vsearch \
        --i-query /scratch/group/hu-lab/deepsea-18S-merged-outputs/deepsea-18s-merged-seqs-05022025.qza \
        --i-reference-reads /scratch/group/hu-lab/databases/PR2/pr2_version_5.0.0_seqs.qza \
        --i-reference-taxonomy /scratch/group/hu-lab/databases/PR2/pr2_version_5.0.0_tax.qza \
        --output-dir /scratch/group/hu-lab/deepsea-18S-merged-outputs/merged-taxonomy-0.9_0.8_PR2-5.0.0 \
        --p-threads $SLURM_CPUS_PER_TASK \
        --p-maxaccepts 10 \
        --p-perc-identity 0.90 \
        --p-min-consensus 0.80

echo "taxonomy assigned, convert output"

qiime tools export \
        --input-path /scratch/group/hu-lab/deepsea-18S-merged-outputs/merged-taxonomy-0.9_0.8_PR2-5.0.0/classification.qza \
        --output-path /scratch/group/hu-lab/deepsea-18S-merged-outputs/merged-taxonomy-0.9_0.8_PR2-5.0.0/taxonomy-merged-05022025

echo "assign taxonomy - for SILVA"

qiime feature-classifier classify-consensus-vsearch \
        --i-query /scratch/group/hu-lab/deepsea-18S-merged-outputs/deepsea-18s-merged-seqs-05022025.qza \
        --i-reference-reads /scratch/group/hu-lab/databases/silva/silva-138-99-seqs.qza \
        --i-reference-taxonomy /scratch/group/hu-lab/databases/silva/silva-138-99-tax.qza \
        --output-dir /scratch/group/hu-lab/deepsea-18S-merged-outputs/merged-taxonomy-0.9_0.8_SILVA-138 \
        --p-threads $SLURM_CPUS_PER_TASK \
        --p-maxaccepts 10 \
        --p-perc-identity 0.90 \
        --p-min-consensus 0.80

echo "taxonomy assigned, convert output - for SILVA"

qiime tools export \
        --input-path /scratch/group/hu-lab/deepsea-18S-merged-outputs/merged-taxonomy-0.9_0.8_SILVA-138/classification.qza \
        --output-path /scratch/group/hu-lab/deepsea-18S-merged-outputs/merged-taxonomy-0.9_0.8_SILVA-138/taxonomy-merged-SILVA-05032025
