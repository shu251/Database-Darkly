# Curation protocol — Database Darkly v2

How the version 2 database was built, in the order it was done. Parameters and
counts are the ones actually used. Companion files: `VERSIONS.md` (version
pinning and caveats), `README.md` (method detail), `ZENODO-v3-manifest.md`
(release contents).

## 1. Sequence set

Axial Seamount 2022 and 2023 libraries were denoised with DADA2 per sequencing
run (`--p-trunc-len-f 260`, `--p-trunc-len-r 225`, pooled chimera removal) and
merged with the version 1 ASV table. **27,559 ASVs across 176 samples,
16,638,540 reads.**

ASV identifiers are sequence hashes, so all 17,934 version 1 identifiers persist
unchanged in version 2. This invariant is what makes step 4 possible.

## 2. Taxonomy assignment

`qiime feature-classifier classify-consensus-vsearch` against PR2 5.0.0, at 90%
identity and 0.80 minimum consensus, `--p-maxaccepts 10`. SILVA 138 was run with
identical settings as a parallel comparison. 9,565 ASVs (34.7%) returned
Unassigned.

## 3. PR2 version migration

A taxon crosswalk was built from the official PR2 5.0.0 and 5.1.1 taxonomy
tables: exact nine-rank path, then species name, then genus name. 50,677 of
53,594 taxa (94.6%) have an identical path; 99.7% map; one taxon changed
supergroup.

Each ASV was then carried onto 5.1.1 by matching its 5.0.0 taxonomy string to the
longest 5.0.0 lineage prefix, crosswalking every matching taxon, and taking the
lowest common ancestor of the targets. A `pr2_taxon_id` is assigned only where
the LCA reaches species; otherwise `lineage_511` carries the resolution the
assignment actually supports and `lca_depth` records it. **17,994 ASVs (65.3%)
received a 5.1.1 lineage; 11,068 resolved to species; 56 could not be resolved
(`UNRESOLVED_LCA`).**

Taxonomy was *not* re-assigned against 5.1.1 by vsearch. The crosswalk moves
names, not hits, so assignment depth may shift when that run completes.

## 4. Transfer of the version 1 hand curation

Transferred along the sequence, not by name matching:

```
curated taxon -> v1 taxonomy string -> v1 feature IDs -> identical v2 IDs -> 5.1.1 lineage
```

All 1,095 curated taxon strings join exactly to the version 1 taxonomy table
(whitespace trim only). 641 rows carry at least one annotation, covering 8,226
ASVs; **6,833 land on an assigned lineage**, 1,393 (16.9%) fall to Unassigned
under 5.x and are retained at ASV level rather than discarded.

## 5. Collision resolution

201 of 547 curated taxa split across several 5.1.1 lineages; 145 lineages receive
more than one curated record. Collisions are classified and resolved as:

| class | n | rule |
|---|---|---|
| no structured-field conflict | 107 | merge all; free-text fields concatenated with ` \| ` |
| conflict, sources nested or mixed | 30 | source whose 4.x lineage overlaps the target most wins |
| conflict, sources are siblings | 8 | values kept multi-valued, flagged `MANUAL_REVIEW_REQUIRED` |

Free-text fields (`Notes`, `Other names`, `Resources`, phylogenetic notes, genes)
are expected to differ and are concatenated, not adjudicated. Most collisions
trace to loss of assignment resolution rather than taxonomic reorganisation — the
receiving lineage is often shallower than the records feeding it.

## 6. Value canonicalisation

Every trait value passes one canonicaliser: integral numerics collapse to integer
form (`1`, `1.0`, ` 1 ` are one value), NFKC normalisation unifies compatibility
characters, and known typos are corrected. Controlled-vocabulary collapse then
runs within each source. 19 mappings over 104 cells remain after canonicalisation.

Numeric detection uses a strict regular expression, never `float()` — see the
caution in `VERSIONS.md`.

## 7. External trait database alignment

Four published sources were aligned onto the PR2 5.1.1 taxonomy: the Mixoplankton
Database (Mitra et al. 2023), TMD v1.1, the Ramond et al. (2019) trait database,
and PIDA v1.11 (Bjorbækmo et al. 2020).

Each source record attaches at the **most specific rank that matches** — species,
then genus, then family — and `evidence_rank` records which. Only MDB carries PR2
accessions, and only for 232 of its 435 species, so the join is name-based for
the rest. PIDA is an edge list and is emitted from both partners' perspectives
with `interaction_role` set to host or symbiont.

| source | records | placed | at species | at genus | taxa reached |
|---|---|---|---|---|---|
| MDB | 435 | 375 (86%) | 232 | 143 | 547 |
| TMD | 378 | 356 (94%) | 230 | 126 | 499 |
| Ramond | 2,007 | 1,221 (61%) | 830 | 391 | 3,121 |
| PIDA (both sides) | 4,896 | 3,843 (78%) | 1,989 | 1,854 | 2,614 |

PIDA observations are retained for all habitats; `interaction_habitat` is carried
per row so marine-only filtering is a downstream choice.

## 8. Trophic reconciliation

MDB and TMD overlap on 209 species and share a functional-type vocabulary. Where
they disagree, **TMD takes priority** (set 2026-11-01); MDB values are retained
in their own columns and `resolution_note` records why each call was chosen. 25 of
209 shared species were overridden, of which 8 are asterisk-only differences and
5 are parasite overlays where both sources are plausibly correct.

## 9. WoRMS layer

AphiaIDs are taken from MDB where present, otherwise inherited from PR2's own
`worms_id` by species-name match. 434 of 604 trophic species (72%) carry an
AphiaID. Live WoRMS resolution of the remaining 170, and accepted-versus-synonym
status for all of them, is a local step — see the commented `worrms` block in
`merge-mdb-tmd-trophic.R`.

WoRMS registers formally described species, so only 4.4% of the ASV set can ever
carry an AphiaID. It is used for synonym resolution, not as the spine.

## 10. Compilation

Build scripts `build/01`–`03` produce the ASV-level table (primary), the
taxon-level rollup, and `Database-Darkly-v2-compiled.xlsx`, whose README sheet is
the data dictionary.

**Coverage: 7,910 of 27,559 ASVs (28.7%) and 47.1% of reads carry any functional
annotation.** By supergroup, species-level annotation ranges from 57.3%
(Haptista) to 11.9% (TSAR) to 0% (PANNAM).

## 11. Prioritisation of further curation

Uncurated taxa are ranked by read abundance, not taxonomic order, and tagged by
effort tier: **full effort on protists** (678 taxa, 23.8% of reads, all 41 fields),
**medium effort on metazoa, fungi and plants** (144 taxa, 15.3% of reads, reduced
9-field set). The protist top 50 records reach 19.2% of reads; metazoan effort
saturates by about 25 records.

`seed_ecological_function` pre-fills a coarse first-pass trophic call for 394 of
822 worklist taxa from PR2's own column. It has five bins and is a starting value
to refine, not an answer.

## Known limits

- None of the four published trait databases is deep-sea in origin. The
  annotation gap is concentrated in the lineages this project exists to document.
- Two source pairs are not independent: MDB with TMD, and the hand curation with
  Ramond (97% identical where both speak). See `VERSIONS.md`.
- Annotation attached at genus or family rank is a hypothesis propagated across
  congeners, not an observation.
- 41 lineages carry unresolved multi-valued curation; 8 sibling collisions await
  adjudication.
