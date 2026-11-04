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
| Tree | move any finished `04-tree/reference.*` aside, then `sbatch 04-reference-tree.slurm` | `reference.iqtree`, long branches, major groups recovered |
| Placement | `sbatch 05-place-asvs.slurm` | ASVs dropped at each filter |

Paths and thresholds are all in `config.sh`. Outputs go to
`/scratch/group/hu-lab/deepsea-18S-merged-outputs/phylo-placement/`.
If the tree job hits its time limit, resubmit it: IQ-TREE resumes from its
checkpoint.

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
