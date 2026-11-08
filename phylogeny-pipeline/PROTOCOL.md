# Phylogenetic placement protocol — Database Darkly v2

How the eukaryote-wide reference tree and ASV placement are being built, in the
order the work was done. Parameters and counts are the ones actually used.
Companion files: `README.md` (how to run the pipeline), `config.sh` (all paths and
thresholds), `force-references.tsv` (references added by hand).

**Status on 2026-11-04:** the first reference tree (job 20367329, 4,115 references)
finished. On review, all 122 remaining lost lineages were added to
`force-references.tsv`, and 9 more on 2026-11-05 (179 forced in total), so steps
02–04 must be rerun before placement. ASV placement (step 7) has not been run.

Job logs are written to `logs/`.

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

The other 122 lost lineages, for example nine Dino-Group-II clades, OLIGO3 and short
Foraminifera, were at first left out. After the first tree (step 6), all of them were
added on 2026-11-04, so every lineage in `lost-lineages.tsv` now has a forced
reference. One sequence was taken from each lineage's row in `lost-lineages.tsv`:

| case | n | sequence used | reason |
|---|---|---|---|
| sequences passed the filters but were clustered away or capped | 51 family | longest passing sequence | `absorbed_or_capped` |
| no sequence passed, all under 1,200 bp | 12 order, 59 family | longest sequence (526–1,199 bp) | `short_deep_lineage` |

Six of these are under 800 bp: Euglenophyceae_X (637 bp), Gregarinomorphea_X_GRE2
(562), OLIGO10 (730), PHYLL_3 (553), Suessiales_X (526) and Nassellaria_4 (591).
After trimming they will carry little signal, and their positions need checking in
the rerun tree. The 51 `absorbed_or_capped` additions are each at least 97% identical
to a reference already in the set, so they restore the lineage label more than new
sequence diversity.

The 2026-11-05 rerun of step 02 with these 170 forced references still left 9 families
without a reference. These were not new losses. `check-lost-lineages.sh` reports only
the highest rank lost, so before three orders (Textulariida, Syracosphaerales and
Zygodiscales) were restored by single forced references, their other families were
hidden. They were forced by the same rule (3 of the Textulariida sequences are
3,119–3,475 bp, so `over_max_length`), giving 179 forced references. Family is the
lowest rank checked, so this cannot recur. The next rerun of step 02 should report
4,246 references (4,115 + 131), and `check-lost-lineages.sh` should report none.

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

**Second alignment, FFT-NS-i (job 20361432, checked in job 20367299).** The references
were realigned with `mafft --retree 2 --maxiterate 2` to refine the fast alignment. The
same 300 sampled ASVs were checked.

| measure | FFT-NS-2 | FFT-NS-i |
|---|---|---|
| Columns before trimming | 62,570 | 62,974 |
| Columns after trimming | 2,277 | 2,269 |
| Gaps after trimming | 27.9% | 27.9% |
| Reference bases kept, median | 98.1% | 98.1% |
| Reference bases kept, 5th percentile | 66.0% | 65.2% |
| Reference bases kept, minimum | 26.1% | 25.0% |
| References with under 50% kept | 55 | 72 |
| References with under 1,000 bases kept | 68 | 70 |
| ASV bases kept, median | 98.7% | 98.7% |
| ASV bases kept, 5th percentile | 90.4% | 91.2% |
| ASV bases kept, minimum | 76.9% | 68.9% |
| Sampled ASVs under 150 bases kept | 0 | 0 |

The FFT-NS-i alignment was chosen for the tree. It met the criteria set beforehand:
trimmed gaps and column count were the same or lower, and reference and ASV coverage
were similar.

The one clear difference is in Foraminifera. The 14 forced Foraminifera lost 7.8–11.6%
more bases under FFT-NS-i (mean 9.6%), while the other 34 forced references changed by
less than 1%. These logs cannot show which alignment places those bases correctly.

**Rerun with 179 forced references (step 02 job 20407183, step 03 job 20407384).**
Step 02 added all 179 forced references, giving 4,246 references (526–4,863 bp,
median 1,775), and `check-lost-lineages.sh` then reported no lost lineages. The FFT-NS-i
alignment had 65,417 columns, trimmed to 2,243 (27.4% gaps).

| forced references | n | bases kept after trimming |
|---|---|---|
| all | 179 | 443–1,798 (median 1,104; median 97.9% of the sequence) |
| over 3,000 bp (`over_max_length`, mostly Foraminifera) | 19 | 1,579–1,784 (37–58% lost, mostly Foraminifera insertions) |
| short Foraminifera keeping under 60% | 18 | 566–640 (50–60% kept) |
| lowest | 1 | Euglenophyceae_X `KC440730.1.637_U`, 443 of 637 bp |

## 6. Reference tree

`04-reference-tree.slurm` runs IQ-TREE on `03-alignment/reference-trimmed.fasta`:

```
iqtree2 -m MFP -mset GTR -mfreq F -mrate G,R -B 1000 -alrt 1000 -T 24 --mem 320G --seed 20261101
```

The job limit is 7 days. If it times out, resubmitting resumes from the checkpoint.

The tree is reviewed before placement for long branches (especially Foraminifera
and Euglenozoa), bootstrap convergence, recovery of major groups, and monophyly of
Amorphea (Obazoa + Amoebozoa).

**First tree (job 20367329, 4,115 references; superseded by the rerun).** It finished
in 28 hours. Output files are copied locally to `fromhprc/`.

| measure | result |
|---|---|
| Alignment | 2,269 columns, 2,268 parsimony-informative, 0 constant |
| Best-fit model (BIC) | GTR+F+R10 (AICc chose GTR+F+G4) |
| Log-likelihood | −1,581,984.45 |
| Total tree length | 602.9 (28.0% internal) |
| UFBoot convergence | not reached after 1,001 iterations; split correlation 0.937, 0.922, 0.911 (needs 0.99) |
| Nodes with SH-aLRT ≥ 80 / UFBoot ≥ 95 / both | 71.2% / 66.2% / 55.5% |
| References failing the composition test | 971 (p < 0.05) |
| References over 50% gaps | 128 |
| Identical references | `KM020045.1.2160_R` and `KM020045.1.2160_G` |

UFBoot non-convergence does not affect placement, because step 7 uses only the ML tree
and refits GTR+G4+F on it. It does affect any support values reported for the tree.

Terminal branches have a median length of 0.053 substitutions per site. 233 are longer
than 0.339 (Q3 + 3 IQR). The longest include fast-evolving lineages: the myxomycete
*Reticularia lycoperdon* (`JX481311.1.1276_G`, 4.97), *Bulbochaete* (3.07), *Creneis*
(2.78), *Netzelia* (2.19) and the metchnikovellid *Amphiacantha* (1.79). Of the 48
forced references, only the Kickxellomycotina reference (`KF848917.1.3736_U`, 1.20) is
among them. The forced short references have median terminal branches of 0.14.

Major groups were checked against `02-references/reference-taxonomy.tsv` (from the
first step 02 run). For each group, the clade that best matched it was found
(fewest group members outside plus fewest intruders inside).

**Amorphea is not monophyletic.** It splits into 66 clades containing only Amorphea
(31 of them single references). The largest, 232 references of Fungi,
Choanoflagellata and Ichthyosporea, has 100/100 support. Metazoa are scattered in
several clades, and Amoebozoa is split, with 146 of its 196 references outside its best
clade. Rooting `gappa examine assign` on Amorphea, as step 05 does now, would
therefore root on an arbitrary point.

Other groups that 18S alone is known to resolve poorly were also split:

| group | n | members outside the best clade | main cause |
|---|---|---|---|
| Rhizaria | 570 | 125 | Foraminifera and Polycystinea (Retaria) |
| Alveolata | 1,272 | 42 | Gregarinomorphea (31) |
| Discoba | 186 | 54 | Heterolobosea (40) |
| Metamonada | 122 | 43 | Fornicata, Preaxostyla |
| Stramenopiles | 669 | 4 | — |
| Chlorophyta | 297 | 2 | — |

Cryptophyta, Picozoa, Telonemia, Kathablepharidacea and Glaucophyta were monophyletic.

44 of the 48 forced references sit next to members of their own division. The other
four are Malawimonadidae (next to Breviatea, Rigifilida and Hemimastigophora, all
orphan lineages), Kickxellomycotina `KF848917.1.3736_U` (a long branch among Discoba
and Amoebozoa, misplaced), a short Ancyromonadida reference (next to Discosea) and a
short Breviatea reference (next to Opisthokonta, still within Obazoa).

**Decision (2026-11-04): constrain the backbone in the rerun.** 18S alone cannot
resolve the deepest splits, and long branches pull fast-evolving groups together. The
rerun therefore gives IQ-TREE a constraint tree (`-g constraint.tree`), written in step
04 from `reference-taxonomy.tsv` by `make-constraint.awk`. It enforces only groups with
strong phylogenomic support:

- Amorphea (Obazoa + Amoebozoa), and within it Opisthokonta (with Metazoa and Fungi
  each enforced) and Amoebozoa
- Rhizaria, Alveolata, Stramenopiles and Discoba

All relationships inside these groups, and the position of every other reference
(Archaeplastida, Haptista, Cryptista, Metamonada, the orphan lineages and others), are
left to the data. On the first run's taxonomy, the constraint covers 3,291 of the 4,115
references and leaves 824 free. Constraining makes rooting on Amorphea in step 05 valid.
The deep backbone comes from the constraint, not from 18S, and the methods must say so.

Before the rerun, the first tree's outputs must be moved out of `04-tree/` (for example
to `04-tree/run1-unconstrained/`), because IQ-TREE will not start over a finished run.
Step 04 now stops with a message if it finds one.

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

- Check Foraminifera in the finished tree, given the extra bases they lost to trimming
  under FFT-NS-i.
- Rerun 02 → `check-lost-lineages.sh` → 03 → `check-alignment.slurm` → 04 with the
  179 forced references and the backbone constraint.
- In the rerun tree, see where the free groups (Archaeplastida, Haptista, Cryptista,
  Metamonada, orphan lineages) land, and compare its log-likelihood with the first
  tree's (−1,581,984.45) to show what the constraint costs.
- Decide whether to rerun UFBoot with more iterations (`-nm`) or report SH-aLRT alongside it.
- Check whether the longest branches (for example `JX481311.1.1276_G`, `EF616484.1.1801_U`)
  are real fast evolution or misalignment or chimeras.

## Known limits

- Placement can only attach an ASV to a lineage in the tree. Lineages absent from PR2
  will appear as placements near their closest reference, and ASVs on long
  pendant branches or with high uncertainty could be novel, chimeric or non-target.
- Forced short references carry less signal, and their positions need checking in the
  finished tree.
- ASV coverage comes from a sample of 300 ASVs, not the full set. Step 7 reports the
  full count.
- References use PR2 5.1.1, while the ASV taxonomy in `annotation-pipeline/` was assigned
  against PR2 5.0.0 and crosswalked. Part of any disagreement between placement and
  assignment taxonomy may come from this version difference.
