# Database Darkly v2 — phylogenetic placement pipeline

Builds a eukaryote-wide 18S reference tree from PR2 5.1.1 and places the 27,559
deep-sea ASVs on it. The ASVs are about 380 bp, too short to resolve deep
relationships in a tree of their own, so the tree comes from near-full-length
references and stays fixed during placement.

All steps have run end to end on a small sample with `smoke-test.slurm` (147
references, 271 ASVs). The full-size run has not finished yet.

## Running on Grace

Copy this folder to Grace and submit every job from inside it. Check each step's
log, written to `logs/`, before starting the next. Slurm does not create that
folder, so run `mkdir -p logs` first if it is missing; otherwise the job fails with
no log.

| step | command | check before moving on |
|---|---|---|
| Setup | `bash 00-setup-env.sh` | every tool is found |
| Export | `sbatch 01-export-databases.slurm` | taxonomy format printed in the log |
| References | `sbatch 02-select-references.slurm` | reference count, `references-per-division.txt` |
| Alignment | `sbatch 03-align-trim.slurm` | trimmed alignment length |
| Tree searches | move any earlier `04-tree/` outputs aside, then `sbatch 04-reference-tree.slurm` (array of 6: 5 constrained seeds, 1 unconstrained) | every `search-N/reference.log` ends with a date |
| Choose tree | `sbatch --dependency=afterok:<array job id> 04b-compare-trees.slurm` | `compare/search-loglik.tsv`, RF distances, AU test; long branches and major groups in `reference.treefile` |
| Placement | `sbatch 05-place-asvs.slurm` | ASVs dropped at each filter |

Paths and thresholds are all in `config.sh`. Outputs go to
`/scratch/group/hu-lab/deepsea-18S-merged-outputs/phylo-placement/`.
If a tree search hits its time limit, resubmit that task alone
(`sbatch --array=N 04-reference-tree.slurm`): IQ-TREE resumes from its checkpoint.

## Reference selection

Nuclear eukaryote sequences of 1,200–3,000 bp are clustered at 97%, then capped:

| group | kept |
|---|---|
| named protist genus | 1 per genus |
| unnamed genus (`*_X`), to retain environmental clades | up to 5 per genus |
| Metazoa, Fungi, Streptophyta | 1 per family |

These three groups hold 18,839 of the 22,929 PR2 5.1.1 eukaryote genera with SSU
sequences, so sampling them per genus would swamp the protists. Lineages with
18S longer than 3,000 bp drop out unless `REF_MAX_LEN` is raised.

`force-references.tsv` adds sequences back regardless of these filters, one for each
lineage chosen from the report made by `check-lost-lineages.sh`. Its columns are id,
length, reason and lineage:

| reason | what it restores |
|---|---|
| `over_max_length` | lineages with no sequence short enough to pass, including deep-sea Foraminifera and Malawimonadidae |
| `absorbed_or_capped` | class, order and family lineages lost to clustering or a cap |
| `short_deep_lineage` | deep lineages known only from partial sequences; these carry less signal |

## Main outputs

In `05-placement/`:

| file | contents |
|---|---|
| `epa/epa_result.jplace` | all placements with likelihood weights |
| `gappa/epa_result.newick` | reference tree with ASVs grafted on, for iTOL or ggtree |
| `gappa/per_query.tsv` | taxonomy per ASV from its placement |
| `gappa/edpl_list.csv` | placement uncertainty per ASV |
| `silva-best-hit.tsv`, `asvs-non-eukaryote.txt` | SILVA screen results |
| `asv-aligned-bases.tsv` | aligned bases per ASV after trimming |

## Interpreting placements

- Placement can only attach an ASV to a lineage already in the tree. An ASV from
  an unsampled lineage lands near its closest reference, often on a long pendant
  branch or with high uncertainty.
- Those ASVs may be novel, but they may also be chimeras or non-target sequence.
  Check them before calling them novel.
- The tree is unrooted. Root between Amorphea and the other eukaryotes for display.
- `gappa examine assign` does not warn if the outgroup is not monophyletic: a smoke
  test with a deliberately split outgroup still exited 0. Check that Amorphea forms
  one clade in `reference.treefile` before trusting `per_query.tsv`.

## Interpreting the reference trees

This section describes how to review one reference tree, and then how to compare
versions to see which branches change between iterations. Results for each tree go
in `PROTOCOL.md`, section 6.

### Tree versions

All in `04-tree/` under the output folder:

| version | files | references | alignment columns | how it was built |
|---|---|---|---|---|
| tree 1 | `run1-unconstrained/reference.treefile` | 4,115 | 2,269 | unconstrained, one search |
| tree 2 | `run2-constrained/reference.treefile` | 4,246 | 2,243 | backbone constraint without Rhodophyta, one search |
| tree 3 | `search-1/` … `search-5/` | 4,245 | 2,206 | constraint with Rhodophyta, 5 seeds |
| tree 3, unconstrained | `search-6/` | 4,245 | 2,206 | no constraint, same alignment as searches 1–5 |
| chosen tree | `reference.treefile` (copied by 04b) | 4,245 | 2,206 | best-logL search of 1–5; placement uses this one |
| support | `reference-support.treefile` (04b) | 4,245 | 2,206 | chosen tree with unconstrained SH-aLRT on each branch |

### Which numbers can be compared

- **Log-likelihood** can only be compared between trees scored on the same alignment
  under the same model. Searches 1–6 of tree 3 can be compared with each other, but
  trees 1, 2 and 3 cannot, because each used a different alignment.
- **The AU test** (`compare/au-test.iqtree`) asks whether the data reject a tree
  compared with the best of the set. A tree with `p-AU` below 0.05 is rejected. If the
  constrained trees (1–5) are not rejected compared with the unconstrained one (6), the
  constraint costs no significant fit. If they are rejected, the data favour a
  backbone the constraint forbids, and `PROTOCOL.md` should say so (Shimodaira 2002).
- **RF distance** counts bipartitions found in one tree but not the other (Robinson &
  Foulds 1981). Normalized RF runs from 0 (identical) to 1 (nothing shared). With
  thousands of tips it can be large even between trees of similar likelihood, because
  shallow bipartitions among near-identical references are weakly determined. A single
  RF value therefore says how much changed, not where. Use the group table below
  to see where. Trees with different reference sets must be pruned to their shared
  references first; `compare-tree-versions.R` does this.
- **Support.** Report the SH-aLRT values from `reference-support.treefile`, computed
  without the constraint (Guindon et al. 2010). Values of 80 or more are commonly taken
  as well supported. Support values on enforced groups from a constrained search
  measure nothing and must not be reported. UFBoot is no longer run, because it did not
  converge in trees 1 or 2.

### Reviewing one tree

Open the tree in iTOL or FigTree, or in R with `ape`/`ggtree`, and root it between
Amorphea (Obazoa + Amoebozoa) and the other eukaryotes. The tree is unrooted, so this
root is a display choice, following the current view of the eukaryote tree (Burki et
al. 2020). Then check, in this order:

1. **Enforced groups.** Amorphea, Opisthokonta, Metazoa, Fungi, Amoebozoa, Rhizaria,
   Alveolata, Stramenopiles, Discoba and (from tree 3) Rhodophyta are monophyletic by
   construction, so their presence is not a result. Check only what sits next to and
   inside them. The relationships among these groups are not inferred either.
2. **Free groups.** Everything outside the enforced groups is placed by the data:
   Metamonada, Haptophyta, Cryptophyta, Chlorophyta, the orphan lineages
   (Malawimonadidae, Ancyromonadida, Picozoa, Telonemia and others) and the internal
   structure of every enforced group. For each, ask whether it forms one clade and what
   intrudes into it.
3. **Known problem branches** from the earlier trees (`PROTOCOL.md`, section 6):
   Cyanidiales inside Metamonada (tree 2), Malawimonadidae, the Foraminifera stem,
   *Bulbochaete* and Nephroselmidaceae out of place, and the long branches of
   `JX481311.1.1276_G` (*Reticularia*), `EF616484.1.1801_U` (*Bulbochaete*), and, new in
   the tree-3 alignment, `KJ522681.1.2893_U` (*Oocystis*, 24% of bases kept).
4. **Long branches.** A terminal branch many times the median length can be real fast
   evolution, a misalignment, a chimera or a contaminant. Long branches can also attract
   each other into false clades (long-branch attraction; Bergsten 2005), which is the
   likely cause of Cyanidiales joining Metamonada. Check the longest ones against BLAST
   or the PR2 record before trusting them. TreeShrink (Mai & Mirarab 2018) can flag
   them more formally if needed.
5. **Forced references.** Each should sit with its lineage in `force-references.tsv`.
   Short ones (`short_deep_lineage`) carry little signal and are the most likely to
   wander.
6. **Support on the free groups**, from `reference-support.treefile`.

### Comparing versions

`compare-tree-versions.R` takes any number of trees, prunes them to the references
they share, and reports, for every supergroup, division, subdivision, class and order
in PR2 with at least two shared references, whether each tree recovers it. It uses
`ape` and `phangorn` (Paradis & Schliep 2019; Schliep 2011) and takes about a minute
per two trees (0.4 GB). That is fine on a login node; use an interactive job for many
trees.

```
module load GCC/13.3.0 OpenMPI/5.0.3 R-bundle-CRAN/2024.11
T=/scratch/group/hu-lab/deepsea-18S-merged-outputs/phylo-placement/04-tree
Rscript compare-tree-versions.R ${T}/compare/versions \
  tree2=${T}/run2-constrained/reference.treefile \
  s1=${T}/search-1/reference.treefile s2=${T}/search-2/reference.treefile \
  s3=${T}/search-3/reference.treefile s4=${T}/search-4/reference.treefile \
  s5=${T}/search-5/reference.treefile unc=${T}/search-6/reference.treefile
```

Including tree 1 limits the comparison to its 4,115 references. Leave it out to keep
the forced references added since.

Outputs:

| file | contents |
|---|---|
| `group-monophyly.tsv` | one row per group: `<tree>_intruders`, `<tree>_outside`, `<tree>_intruded_by`, how many trees recover it, and whether trees disagree |
| `rf-normalized.tsv` | normalized RF between every pair of trees |
| `longest-branches.tsv` | 25 longest terminal branches per tree, with length as a multiple of the median and taxonomy |

How to read the two group measures:

- **intruders**: references from other groups inside the smallest clade that holds every
  member of the group. `<tree>_intruded_by` lists their lineages.
- **outside**: members of the group that are not in its largest clean clade.
- **0 / 0** means the tree recovers the group.

Read the two together, because one stray member makes the intruder count huge. In
tree 2, Rhodophyta has 1,183 intruders but only 7 members outside, the 7 Cyanidiales.
In the same tree, Metamonada has 8 intruders (the 7 Cyanidiales and *Paravannella*)
and 43 of its own members outside its largest clean clade. Tree 1 against tree 2 gives a normalized RF
of 0.363 on 4,115 shared references.

### What a change means

| pattern | likely meaning | what to do |
|---|---|---|
| group recovered in every search and version | robust to search, constraint and reference set | describe it as consistent |
| differs among seeds 1–5 (same alignment, model and constraint) | the data barely separate the alternatives, or the search is stuck | not a result in either form; check SH-aLRT, and compare placements on the two best trees (step 05) |
| differs between trees 2 and 3 but stable across seeds | caused by the change made between versions (Rhodophyta constraint, one reference dropped, new alignment) | record which change, in `PROTOCOL.md` |
| differs between constrained searches and search 6 | the constraint moves it | look at the AU test; if search 6 is not significantly better, the constrained form is acceptable |
| group pulled toward a long branch, or a long branch moves between versions | possible long-branch attraction or a bad sequence | check the sequence; consider removing or constraining it, as was done for Cyanidiales |

For placement, what matters is whether ASVs would land on a different lineage. A
rearrangement among closely related references changes RF but not the assignments.
That is why step 05 places the ASVs on the two best constrained trees and compares the
results.

### References

- Barbera P, et al. (2019) EPA-ng: massively parallel evolutionary placement of genetic
  sequences. *Systematic Biology* 68:365–369.
- Bergsten J (2005) A review of long-branch attraction. *Cladistics* 21:163–193.
- Burki F, Roger AJ, Brown MW, Simpson AGB (2020) The new tree of eukaryotes.
  *Trends in Ecology & Evolution* 35:43–55.
- Guindon S, et al. (2010) New algorithms and methods to estimate maximum-likelihood
  phylogenies: assessing the performance of PhyML 3.0. *Systematic Biology*
  59:307–321. (SH-aLRT)
- Kapli P, Yang Z, Telford MJ (2020) Phylogenetic tree building in the genomic age.
  *Nature Reviews Genetics* 21:428–444. (Readable overview of models, search and
  support.)
- Mai U, Mirarab S (2018) TreeShrink: fast and accurate detection of outlier long
  branches in collections of phylogenetic trees. *BMC Genomics* 19(Suppl 5):272.
- Minh BQ, et al. (2020) IQ-TREE 2: new models and efficient methods for phylogenetic
  inference in the genomic era. *Molecular Biology and Evolution* 37:1530–1534.
- Paradis E, Schliep K (2019) ape 5.0: an environment for modern phylogenetics and
  evolutionary analyses in R. *Bioinformatics* 35:526–528.
- Robinson DF, Foulds LR (1981) Comparison of phylogenetic trees. *Mathematical
  Biosciences* 53:131–147.
- Schliep KP (2011) phangorn: phylogenetic analysis in R. *Bioinformatics* 27:592–593.
- Shimodaira H (2002) An approximately unbiased test of phylogenetic tree selection.
  *Systematic Biology* 51:492–508.

The IQ-TREE documentation (iqtree.github.io/doc) covers the AU test (`-au`), constraint
trees (`-g`) and SH-aLRT (`-alrt`) with worked examples.
