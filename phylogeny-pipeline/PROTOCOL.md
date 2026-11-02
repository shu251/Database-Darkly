# Phylogenetic placement protocol — Database Darkly v2

How the eukaryote-wide reference tree and ASV placement are being built, in the
order the work was done. Parameters and counts are the ones actually used.
Companion files: `README.md` (how to run the pipeline), `config.sh` (all paths and
thresholds), `force-references.tsv` (references added by hand).

**Status on 2026-11-01:** steps 1–4 are complete and the first alignment has been
checked. The FFT-NS-i alignment in step 5 was submitted and its result has not been
reviewed. The reference tree and ASV placement (steps 6–7) have not been run.

## 1. Approach

The 27,559 deep-sea ASVs (median 381 bp, V4-like) are too short to resolve deep
relationships in a tree of their own. A reference tree is therefore built from
near-full-length PR2 18S sequences, and the ASVs are placed on it with its topology
fixed. The reference set spans all eukaryotes and deliberately retains deeply
branching lineages.

| input | source |
|---|---|
| ASVs | `ref-seqs-deepsea-DB_052025.fasta` (27,559 sequences) |
| Reference sequences and taxonomy | PR2 5.1.1, whole database, 240,201 sequences |
| Non-eukaryote screen | SILVA 138 99% |

All jobs run on the TAMU HPRC Grace cluster. Outputs are in
`/scratch/group/hu-lab/deepsea-18S-merged-outputs/phylo-placement/`.

## 2. Software and database export

Tools are in a conda environment created from `environment.yml` (`00-setup-env.sh`,
module `Anaconda3/2026.07-1`), with versions recorded in
`phylo-placement/conda-env-versions.yml`.

| tool | version | used for |
|---|---|---|
| QIIME 2 | 2024.10-Amplicon (module) | exporting `.qza` files |
| SeqKit | 2.14.0 | sequence handling |
| VSEARCH | 2.32.0 | clustering, SILVA screen |
| MAFFT | 7.526 | reference alignment, adding ASVs |
| trimAl | 1.5.1 | column trimming |
| IQ-TREE | 2.4.0 | reference tree |
| RAxML-NG | 2.0.4 | model fit on the fixed tree |
| EPA-ng | 0.3.8 | placement |
| gappa | 0.9.0 | placement summaries and taxonomy |

`01-export-databases.slurm` exported the PR2 sequences and the SILVA sequences and
taxonomy to FASTA and TSV. The exported PR2 file holds all 240,201 sequences. PR2
taxonomy comes from the existing `pr2-tax_5.1.1.tsv`.

## 3. End-to-end test

`smoke-test.slurm` ran the real step scripts on a random sample (0.2% of PR2, 1% of
ASVs, seed 11) before the full run (job 20360633). All steps completed: 147
references, 271 ASVs placed, and 5 ASVs flagged as non-eukaryote. The tree took about
17 minutes on 24 threads, and the best-fit model was GTR+F+R7. UFBoot did not converge
on this small tree.

The test also showed that `gappa examine assign` exits 0 with no warning when the
root outgroup is split, so outgroup monophyly must be checked by hand (step 7).

This test used MAFFT `--auto`. The FFT-NS-i setting from step 5 was not part of it.

## 4. Reference selection

`02-select-references.slurm` with `select-references.awk`:

| stage | rule | sequences left |
|---|---|---|
| PR2 5.1.1 | all | 240,201 |
| Nuclear eukaryotes | taxonomy begins `Eukaryota;`, which excludes organellar entries | 223,210 |
| Length and quality | 1,200–3,000 bp, at most 1% non-ACGT | 133,691 |
| Clustering | `vsearch --cluster_fast`, 97% identity, plus strand | 24,000 |
| Taxonomic caps | see below, longest sequences kept first | 4,067 |
| Forced references | see below | **4,115** |

| group | kept |
|---|---|
| named protist genus | 1 per genus |
| unnamed genus (`*_X`), to retain environmental clades | up to 5 per genus |
| Metazoa, Fungi, Streptophyta | 1 per family |

### Retaining deeply branching lineages

`check-lost-lineages.sh` compared the 4,067 selected references with PR2 and listed
every lineage left with no reference (`lost-lineages.tsv`): 170 lineages. Foraminifera
was the largest group, with 36 lineages and 3,324 sequences that were too long or
partial. Malawimonadidae was missing entirely because its only PR2 sequence is 3,998
bp.

48 sequences were chosen by hand from this report and added regardless of the filters,
each listed with its reason in `force-references.tsv`:

| reason | n | what it restores |
|---|---|---|
| `over_max_length` | 16 | lineages with no sequence short enough to pass, including deep-sea Foraminifera and Malawimonadidae |
| `absorbed_or_capped` | 18 | class and order lineages lost to clustering or a cap |
| `short_deep_lineage` | 14 | deep lineages known only from partial sequences; these carry less signal |

The rerun (job 20361336) added all 48. The final set has 804–4,863 bp sequences (median
1,776 bp) and represents 34 divisions, from Alveolata (1,272 references) to single
references for Hemimastigophora, Malawimonadidae, Rhodelphidia and Cryptista_X.

About 120 lost lineages were deliberately left out, for example nine Dino-Group-II
clades, OLIGO3 and short Foraminifera. These still await review (see Open items).

## 5. Alignment and trimming

`03-align-trim.slurm` aligns the references with MAFFT, then removes columns with
sequence in fewer than 10% of references (`trimal -gt 0.1`). `check-alignment.slurm`
then reports gaps and the fraction of each reference and of a sample of about 300 ASVs
that survives trimming.

**First alignment, FFT-NS-2 (job 20361354).** `mafft --auto` chose this fast strategy
because of the number of sequences. The alignment is kept in
`03-alignment/fft-ns-2/`.

| measure | result |
|---|---|
| Columns, before and after trimming | 62,570 (97.1% gaps) to 2,277 (27.9% gaps) |
| Reference bases kept, median | 98.1% (5th percentile 66%, minimum 26.1%) |
| References with under 50% kept | 55 |
| References with under 1,000 bases kept | 68: 37 Foraminifera, 11 forced short sequences, 20 others |
| ASV bases kept, median | 373 bases, 98.7% |
| ASV bases kept, minimum | 251 bases, 76.9% |

Most of the 30 references that lost the largest fraction are Foraminifera. They include
both very long sequences (for example 4,863 bp, 35.9% kept) and sequences of about
1,300 bp that lost more than half their bases, so length alone does not explain the
loss. Because few references fell below 1,000 bases, step 4 was not changed.

V4 survives trimming well, and every sampled ASV exceeds the 150-base minimum used in
step 7, so `TRIM_GT=0.1` was kept. This shows that ASV bases land in retained columns,
not that they are aligned correctly within V4's hypervariable regions.

**Second alignment, FFT-NS-i (submitted, not yet reviewed).** The references were
realigned with `mafft --retree 2 --maxiterate 2` to refine the fast alignment. The same
checks will be run on it. It will be used for the tree if its gap percentage and column
count are the same or lower and its reference and ASV coverage are similar. Otherwise,
the FFT-NS-2 alignment will be reconsidered.

## 6. Reference tree (not yet run)

`04-reference-tree.slurm` will run IQ-TREE on `03-alignment/reference-trimmed.fasta`:

```
iqtree2 -m MFP -mset GTR -mfreq F -mrate G,R -B 1000 -alrt 1000 -T 24 --mem 320G --seed 20261101
```

The job limit is 7 days. If it times out, resubmitting resumes from the checkpoint.

The tree will be reviewed before placement for long branches (especially Foraminifera
and Euglenozoa), bootstrap convergence, recovery of major groups, and monophyly of
Amorphea (Obazoa + Amoebozoa).

## 7. ASV placement (not yet run)

`05-place-asvs.slurm` will:

1. Screen ASVs against SILVA with VSEARCH at 90% identity. An ASV is flagged as
   non-eukaryote only if none of its top hits is eukaryotic.
2. Add ASVs to the trimmed alignment without changing its columns
   (`mafft --6merpair --keeplength --addfragments`).
3. Drop ASVs with fewer than 150 aligned bases.
4. Fit GTR+G4+F on the fixed tree with `raxml-ng --evaluate`.
5. Place ASVs with EPA-ng, using that model and `--rate-scalers on`.
6. Summarize with `gappa examine graft`, `edpl` and `assign`, rooting on Amorphea.

## Corrections made along the way

None of these affected a final output.

| problem | fix |
|---|---|
| Trailing `;` in the PR2 taxonomy would have rejected every sequence for having 10 ranks | Stripped in step 4; caught before running |
| IQ-TREE version was not pinned | Pinned to `iqtree=2` |
| `.bestModel` file is not the input EPA-ng expects | Passed as a model string |
| `rmdir` stopped the export job on QIIME's non-empty `tmp` folder after files had moved | Replaced with `rm -rf`; rerun not needed, count confirmed at 240,201 |
| `check-alignment.slurm` crashed from `head` under `pipefail` | Replaced with an `awk` limit |
| `seqkit grep` rewrapped sequences at 60 columns, giving a false ASV coverage result (n = 11,400) | Added `-w 0` and recomputed the result |

## Open items

- Review the FFT-NS-i alignment and choose the alignment for the tree.
- Review the roughly 120 lineages left out of `force-references.tsv`, especially
  Syndiniales and short Foraminifera.

## Known limits

- Placement can only attach an ASV to a lineage in the tree. The lineages left out in
  step 4 will appear as placements near their closest reference, and ASVs on long
  pendant branches or with high uncertainty could be novel, chimeric or non-target.
- Forced short references carry less signal, and their positions need checking in the
  finished tree.
- ASV coverage comes from a sample of about 300 and from the FFT-NS-2 alignment only.
  The run's sample count was not captured in the output reviewed.
- References use PR2 5.1.1, while the ASV taxonomy in `annotation-pipeline/` was assigned
  against PR2 5.0.0 and crosswalked. Part of any disagreement between placement and
  assignment taxonomy may come from this version difference.
