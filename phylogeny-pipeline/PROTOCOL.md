# Phylogenetic placement protocol — Database Darkly v2

How the eukaryote-wide reference tree and ASV placement are being built, in the
order the work was done. Parameters and counts are the ones actually used.
Companion files: `README.md` (how to run the pipeline), `config.sh` (all paths and
thresholds), `force-references.tsv` (references added by hand).

**Status on 2026-11-08:** the constrained rerun tree (job 20421447, 4,246 references,
179 forced) finished on 2026-11-08 and was reviewed against the first tree (step 6).
It satisfies the backbone constraint and recovers most free groups. After review,
Rhodophyta was added to the constraint and one misplaced forced reference was dropped,
so steps 02–04 must be rerun again (step 6, decisions). ASV placement (step 7) has not
been run.

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

`check-alignment.slurm` on this alignment (job 20421398):

| measure | 4,115 references (job 20367299) | 4,246 references (job 20421398) |
|---|---|---|
| Reference bases kept, median | 98.1% | 98.0% |
| Reference bases kept, 5th percentile | 65.2% | 64.4% |
| Reference bases kept, minimum | 25.0% | 36.4% |
| References with under 50% kept | 72 | 42 |
| References with under 1,000 bases kept | 70 | 113 (62 Foraminifera) |
| ASV bases kept, median | 98.7% | 99.0% |
| ASV bases kept, 5th / minimum | 91.2% / 68.9% | 89.1% / 71.4% |
| Sampled ASVs under 150 bases kept | 0 | 0 |

The rise in references under 1,000 bases comes from the 90 forced references that
were under 1,200 bp to begin with.

`check-alignment.slurm` (job 20421398) on the rerun alignment:

| measure | first FFT-NS-i (4,115) | rerun (4,246) |
|---|---|---|
| Columns after trimming, gaps | 2,269, 27.9% | 2,243, 27.4% |
| Reference bases kept, median | 98.1% | 98.0% |
| Reference bases kept, 5th percentile | 65.2% | 64.4% |
| Reference bases kept, minimum | 25.0% | 36.4% |
| References with under 50% kept | 72 | 42 |
| References with under 1,000 bases kept | 70 | 113 (62 Foraminifera) |
| ASV bases kept, median | 98.7% | 99.0% |
| ASV bases kept, 5th percentile | 91.2% | 89.1% |
| ASV bases kept, minimum | 68.9% | 71.4% |
| Sampled ASVs under 150 bases kept | 0 | 0 |

The increase in references under 1,000 bases comes from the short forced references.
ASV coverage is unchanged, so the tree (step 04) went ahead on this alignment.

**Third alignment, for the multi-seed trees (step 02 job 20437164, step 03 job 20452011,
checked in job 20452012).** Same as the rerun except `HM103458.1.1000_U` was dropped
(178 forced references, 4,245 in total). FFT-NS-i took 15.5 h and peaked at 77 GB of memory.

| measure | rerun (4,246, job 20421398) | third (4,245, job 20452012) |
|---|---|---|
| Columns before trimming | 65,417 | 64,510 |
| Columns after trimming, gaps | 2,243, 27.4% | 2,206, 26.5% |
| Reference bases kept, median | 98.0% | 98.1% |
| Reference bases kept, 5th percentile | 64.4% | 64.2% |
| Reference bases kept, minimum | 36.4% | 24.1% |
| References with under 50% kept | 42 | 46 |
| References with under 1,000 bases kept | 113 (62 Foraminifera) | 123 (62 Foraminifera) |
| ASV bases kept, median | 99.0% | 98.7% |
| ASV bases kept, 5th percentile | 89.1% | 88.2% |
| ASV bases kept, minimum | 71.4% | 71.7% |
| Sampled ASVs under 150 bases kept | 0 | 0 |

Forced references changed little: all 178 are present, with a mean change of −4.6 bases
from the rerun. The largest losses were in long Foraminifera (`FR821694.1.3331_U` −62,
`HE965431.1.4863_U` −58, `DQ440527.1.3473_U` −50), all of which keep over 1,500 bases.
`KC440730.1.637_U` is still the only one under 500 (438 bases).

The new minimum is *Oocystis lacustris* `KJ522681.1.2893_U` (Chlorophyta, not forced),
which dropped from 1,080 bases kept (37%) to 697 (24%), even though only one sequence
was removed from the input. The cause is not known; the sequence is 2,893 bp, probably
intron-containing. It should be checked for a long branch in the new trees. ASV coverage is unchanged, so step 04 went
ahead on this alignment (array job 20466180, then 04b job 20466186 after it succeeds).

## 6. Reference tree

For the first two trees, `04-reference-tree.slurm` ran IQ-TREE on `03-alignment/reference-trimmed.fasta` (replaced after the second tree; see decisions below):

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
Step 04 now stops with a message if it finds one. The first tree is in
`04-tree/run1-unconstrained/`.

**Second tree, constrained (job 20421447, 4,246 references; current).** It started
2026-11-06 and finished 2026-11-08 in 41 hours. The constraint
(`04-tree/constraint.tree`) covered 3,413 references and left 833 free.

Both trees were reviewed with the same script, which first reproduced every first-tree
number above (support, branch lengths, group splits, forced-reference neighbours).
Groups were checked against the current `reference-taxonomy.tsv`.

| measure | first tree (unconstrained) | second tree (constrained) |
|---|---|---|
| References / columns | 4,115 / 2,269 | 4,246 / 2,243 |
| Best-fit model (BIC) | GTR+F+R10 | GTR+F+R10 |
| Log-likelihood | −1,581,984.45 | −1,621,964.75 |
| Total tree length | 602.9 (28.0% internal) | 610.4 (28.0% internal) |
| UFBoot convergence | not reached; last correlations 0.937, 0.922, 0.911 | not reached; last correlations 0.908, 0.914, 0.931 |
| Nodes with SH-aLRT ≥ 80 / UFBoot ≥ 95 / both | 71.2% / 66.2% / 55.5% | 72.4% / 69.7% / 58.8% |
| References failing the composition test | 971 | 1,027 |
| References over 50% gaps | 128 | 184 |
| Terminal branches, median | 0.053 | 0.052 |
| Terminal branches over Q3 + 3 IQR | 233 (> 0.339) | 252 (> 0.329) |

The two log-likelihoods are not comparable, because the alignments differ (131 more
references, 26 fewer columns). The difference therefore does not show what the
constraint costs (open items).

*The constraint held.* All 9 enforced groups are clades in the ML tree. Their 100/100
support is set by the constraint, not measured: IQ-TREE warned 9 times that a branch
whose both NNIs violate the constraint shows 100% SH-aLRT. These are the only 9 such
branches, so the support rates above barely change without them. Several enforced stems
have length near zero (Amorphea, Alveolata, Rhizaria and Metazoa 0.000, Fungi 0.001,
Amoebozoa 0.006), so the data give these groups almost no length of their own. Rooting
`gappa examine assign` on Amorphea is now valid, because Amorphea is a clade by
construction.

*Groups inside the constraint* (members outside the best clade / intruders inside it):

| group | n (second tree) | first tree | second tree |
|---|---|---|---|
| Foraminifera | 102 | 0 / 0 | 0 / 0 |
| Heterolobosea | 42 | 15 / 0 | 0 / 0 |
| Euglenozoa | 133 | 0 / 3 | 0 / 0 |
| Gregarinomorphea | 98 | 55 / 3 | 21 / 17 |
| Apicomplexa | 215 | 66 / 1 | 18 / 5 |
| Radiolaria | 188 | 38 / 4 | 43 / 0 |
| Evosea | 110 | 60 / 0 | 58 / 0 |
| Discosea | 46 | 33 / 1 | 18 / 9 (Evosea) |
| Bigyra | 184 | 88 / 2 | 92 / 2 |

*Free groups.* Metamonada improved (43 outside in the first tree, now 0 outside),
except that 7 of the 8 Cyanidiales red algae and *Paravannella* (`KF895375.1.2066_U`,
`Eukaryota_XX`) now sit inside it. Cyanidiales are fast-evolving extremophiles, and
`FN546176.1.1551_U` (1.42) sits next to Fornicata, so this is most likely long-branch
attraction. Discoba and Metamonada do not form Excavata, which phylogenomics does not
support either.

| group | n | first tree | second tree |
|---|---|---|---|
| Metamonada | 122 | 43 / 1 | 0 / 8 (7 Cyanidiales, *Paravannella*) |
| Archaeplastida | 567 | 255 / 3 | 9 / 141 (see below) |
| Chlorophyta | 299 | 2 / 3 | 2 / 2 |
| Rhodophyta | 235 | 8 / 0 | 7 / 0 (the Cyanidiales) |
| Haptista | 73 | 24 / 0 | 1 / 0 |
| Haptophyta | 50 | 1 / 0 | 0 / 0 |
| Cryptista | 37 | 1 / 0 | 1 / 0 |
| Cryptophyta, Kathablepharidacea, Picozoa, Telonemia, Glaucophyta | | monophyletic | monophyletic |

The best Archaeplastida clade also holds Haptista, Cryptista, Telonemia, Provora and the
CRuMs, so the free groups gather in one "Archaeplastida + Haptista + Cryptista"
assemblage rather than inside Amorphea or TSAR. Within it, Rhodelphidia is sister to the
red algae, as expected, and Provora is sister to Telonemia. Two Chlorophyta are
misplaced: *Bulbochaete* (`EF616484.1.1801_U`, branch 1.65) on its own branch next to
TSAR, and a Nephroselmidaceae (`GU825178.1.1416_U`) next to Rhizaria.

*Forced references.* 177 of 179 sit next to members of their own division (44 of 48 in
the first tree). The six under 800 bp all sit within their own division, on terminal
branches of 0.00–0.15. The 90 forced references under 1,200 bp have median terminal
branches of 0.058, close to the tree median. The two exceptions:

- Malawimonadidae (`PP680531.1.3998_U`) is now sister to Metamonada (with the
  Cyanidiales), supported 90.8 / 44. Some phylogenomic analyses place malawimonads
  near Metamonada, so this is plausible but weakly supported.
- The short Ancyromonadida reference (`HM103458.1.1000_U`, 1,000 bp) sits alone at
  the base of Stramenopiles + Rhizaria with 0 / 48 support. The other 7 Ancyromonadida
  group with Mantamonadidea. It is misplaced and is a candidate for removal.

10 forced references are among the long branches (1 in the first tree), most of them
short sequences at 0.33–0.90. The longest are a forced short Foraminifera,
*Turborotalita* (`AY453127.1.1196_U`, 1.74), and the Kickxellomycotina reference
(`KF848917.1.3736_U`, 1.30), which the Fungi constraint now keeps in place.

*Foraminifera.* They are monophyletic, with median terminal branches the same as the
rest of the tree (0.051 against 0.052; 0.050 for the 43 forced). The extra bases they
lost to trimming did not lengthen terminal branches. Their stem branch is long, however
(1.00 substitutions per site, 100 / 100), which can attract ASVs that are poorly
aligned or long-branched.

*Long branches.* The longest are still fast-evolving lineages: *Reticularia*
(`JX481311.1.1276_G`, 4.60), *Creneis* (3.25), a Trebouxiophyceae (`EF526893.1.1778_U`,
1.93), *Neozygites* (1.83) and *Turborotalita* (1.74).

**Decisions (2026-11-08) after the second tree.**

- *Rhodophyta added to the constraint.* The Cyanidiales inside Metamonada were judged
  long-branch attraction, and red algal monophyly, Cyanidiophyceae included, has strong
  phylogenomic support. `make-constraint.awk` now enforces Rhodophyta (235 references)
  as one more group among the free references. Nothing else about Archaeplastida is
  enforced.
- *`HM103458.1.1000_U` removed from `force-references.tsv`* (178 forced). It was the only
  reference for Ancyromonadida_XXXX (Planomonadidae_XXXXX), and every PR2 sequence of
  that lineage is shorter, so no replacement exists. `check-lost-lineages.sh` will now
  report this one lineage, by design. Ancyromonadida stays represented by its other 7
  references, and ASVs from the lost lineage will place near them.

With both changes, the constraint covers 3,648 of 4,245 references and leaves 597 free.
Steps 02 → 03 → `check-alignment.slurm` → 04 must be rerun, and the second tree's
outputs moved to `04-tree/run2-constrained/` first.

- *Step 04 becomes several independent searches.* A single search did not reach the
  best tree. In both earlier trees the bootstrap consensus scored a higher
  log-likelihood than the ML tree (by 152 and 183 units), and the best tree was found
  late (iteration 999 of 1,001 in the first tree, 752 in the second). For placing
  difficult deep-sea ASVs, the topology matters more than bootstrap values, which
  EPA-ng does not use. `04-reference-tree.slurm` is now a Slurm array:

  | task | search |
  |---|---|
  | 1–5 | constrained, seeds 20261102–20261106 |
  | 6 | unconstrained, seed 20261107, for the AU test |

  ```
  iqtree2 [-g constraint.tree] -m GTR+F+R10 -nstop 500 -T 24 --seed <TREE_SEED + task>
  ```

  The model is fixed (BIC chose GTR+F+R10 in both earlier trees), so every search is
  scored under the same model. There are no UFBoot or SH-aLRT runs during the searches.
  Since IQ-TREE's default stop rule (100 iterations without improvement) would have
  ended both earlier searches too soon, `-nstop 500` is used instead. Each task asks for
  40 GB, since IQ-TREE needed about 3 GB.

  `04b-compare-trees.slurm` then:
  1. picks the constrained search with the highest log-likelihood and copies it to
     `04-tree/reference.treefile`, the tree step 05 places on;
  2. reports RF distances among the 5 constrained searches, to show how stable the
     topology is;
  3. runs an AU test of all 6 trees (`-z`, `-zb 10000 -au`), which measures what the
     constraint costs;
  4. computes SH-aLRT on the chosen tree without the constraint (`-te`, `-alrt 1000`),
     written to `reference-support.treefile`. These are the supports to report.

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

- Done 2026-11-08: reran 02 → `check-lost-lineages.sh` → 03 → `check-alignment.slurm`
  → 04 with 179 forced references and the constraint, and checked Foraminifera and the
  free groups (step 6).
- Done 2026-11-08: Rhodophyta constrained, `HM103458.1.1000_U` dropped, and step 04
  changed to 5 constrained searches plus 1 unconstrained, followed by
  `04b-compare-trees.slurm` (step 6, decisions).
- Done 2026-11-08/09: second tree moved to `04-tree/run2-constrained/` (with a copy of
  its alignment), 02 rerun (job 20437164: 4,245 references; constraint 3,648, free 597),
  `check-lost-lineages.sh` reports only Ancyromonadida_XXXX, as expected.
- Done 2026-11-10: 03 (job 20452011) → `check-alignment.slurm` (job 20452012) reviewed
  (section 5, third alignment).
- In progress 2026-11-10: 04 array job 20466180 (searches 1–5 constrained, 6
  unconstrained), and after it succeeds, 04b job 20466186.
- Once 04b finishes, rerun the tree review on the chosen tree: Cyanidiales placed with
  the red algae, Malawimonadidae, forced references, Foraminifera stem. Also record the
  RF spread and the AU result, which says whether the data reject the constrained trees.
- After placement, check whether ASVs pile up on the long Foraminifera stem (1.00) or on
  the misplaced *Bulbochaete* and Nephroselmidaceae branches.
- Support: report the unconstrained SH-aLRT from 04b. UFBoot is no longer run; it did not
  converge in either earlier tree. Supports on the enforced groups from a constrained run
  are not measurements and must not be reported.
- Later, in step 05: place the ASVs on the two best constrained trees and compare
  their assignments, to test how robust the placements are.
- Check whether the longest branches (for example `JX481311.1.1276_G`, `EF616484.1.1801_U`)
  are real fast evolution or misalignment or chimeras.

## Known limits

- Placement can only attach an ASV to a lineage in the tree. Lineages absent from PR2
  will appear as placements near their closest reference, and ASVs on long
  pendant branches or with high uncertainty could be novel, chimeric or non-target.
- Forced short references carry less signal. In the second tree, 178 of 179 forced
  references sat in a reasonable position; the exception, `HM103458.1.1000_U`, was
  dropped.
- The deep backbone (Amorphea, Opisthokonta, Rhizaria, Alveolata, Stramenopiles,
  Discoba, Rhodophyta) is enforced, not inferred from 18S. Several enforced stems have
  length near zero.
- ASV coverage comes from a sample of 300 ASVs, not the full set. Step 7 reports the
  full count.
- References use PR2 5.1.1, while the ASV taxonomy in `annotation-pipeline/` was assigned
  against PR2 5.0.0 and crosswalked. Part of any disagreement between placement and
  assignment taxonomy may come from this version difference.
