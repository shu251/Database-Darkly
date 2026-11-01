# Version manifest — Database Darkly v2 annotation pipeline

Last rebuilt: 2026-11-01

## Reference versions

| component | version | source |
|---|---|---|
| PR2 taxonomy spine | **5.1.1** | `input-data/pr2_version_5.1.1_taxonomy.xlsx` (release asset, 64,870 species-level taxa) |
| PR2 previous release | 5.0.0 | `input-data/pr2_version_5.0.0_taxonomy.xlsx` (53,594 taxa) — used only to build the crosswalk |
| ASV taxonomy assignment | **5.0.0, re-mapped to 5.1.1** | see caveat below |
| Mixoplankton Database | MDB 20230418 | Mitra et al. 2023 |
| TMD | v1.1 (Jones) | — |
| Ramond functional traits | as distributed | Ramond et al. 2019 |
| PIDA | v1.11 FORMATTED | Bjorbækmo et al. 2020 |
| v1 curation | 2024-06-05 | `DatabaseDarkly_taxa_06052024.csv` |

## The one remaining version caveat

Every artifact here is keyed on **PR2 5.1.1**. But the underlying ASV taxonomy
was assigned by vsearch against **PR2 5.0.0** (May 2025 HPRC run). ASVs were
carried onto 5.1.1 by the official taxon crosswalk, not by re-running vsearch.

This is sound because 5.0.0 → 5.1.1 is close to an identity mapping:

- 50,677 of 53,594 taxa (94.6%) have an **identical** 9-rank path
- 99.7% map overall (1,340 by species name, 1,404 by genus name)
- exactly **1** taxon changed supergroup
- subdivision changed for 840 taxa (1.6%), class for 291 (0.5%)
- 173 taxa unmatched

What re-running vsearch against 5.1.1 *can* still change: which reference
sequence each ASV hits, and therefore its assignment depth. The crosswalk cannot
model that. Expect the 13.7% unassigned fraction to move, and some ASVs to gain
or lose resolution. The taxon names themselves will barely shift.

**Replace, don't re-derive:** when the 5.1.1 HPRC run lands, swap the taxonomy
file and re-run. Nothing else in the pipeline is version-bound.

## Mapping method

ASV 5.0.0 taxonomy string → longest matching 5.0.0 lineage prefix → crosswalk
each matching 5.0.0 taxon to 5.1.1 → take the LCA of the targets. A
`pr2_taxon_id_511` is assigned only where the LCA reaches species (depth 9);
otherwise `lineage_511` carries the resolution the assignment actually supports,
and `lca_depth` records it.

This replaced an earlier terminal-name shortcut that mapped 12,091 ASVs but
assigned species-level IDs off genus-only matches. The crosswalk assigns 11,068
species-level IDs — fewer but correct — and gives **17,994 ASVs (65.3%) a 5.1.1
lineage at some rank**, which the old method could not do. 1,215 ASVs got a
different taxon under the two methods; the crosswalk result is the correct one.

## Coverage after the rebuild

| metric | value |
|---|---|
| ASVs annotated | 7,910 / 27,559 (28.7%) |
| **Reads annotated** | **47.1%** of 16,638,540 |
| Reads unassigned taxonomy | 13.7% |
| Reads assigned but unannotated | 39.1% |

Essentially unchanged from the 5.0.0-keyed build (28.9% / 47.2%), as the
crosswalk statistics predict.

## Curation effort policy

Set 2026-11-01: **full effort on protists, medium effort on metazoa.**

| tier | taxa | ASVs | % reads | field set |
|---|---|---|---|---|
| protist — full | 678 | 9,142 | 23.8% | `protist_full_41` (all 41 annotation columns) |
| metazoa/fungi/plant — medium | 144 | 942 | 15.3% | `metazoa_reduced_9` |

`metazoa_reduced_9`: Other names, Notes, Trophic strategy, Depth, Benthic_Phase,
Behavior, Resources, plus two project fields — whether the taxon is a vent
endemic, and whether the 18S signal is plausibly larval/tissue rather than
resident. The other 32 columns (Cell Cover, Spicule, Chloroplast, Symbiont
location, Ploidy, Genome Size …) are protist-specific and stay empty for metazoa.

Leverage: protist top 50 records → 19.2% of reads. Metazoan top 10 → 13.2%
(top 25 → 15.0%, after which it is flat; 8.07% sits in Vetigastropoda alone).

`seed_ecological_function` pre-fills a coarse first-pass trophic call for 394 of
822 worklist taxa (48%) from PR2's own column — phagotrophs 231, parasites 70,
phototrophs 50, metazoans 38. Treat it as a starting value to refine, not an
answer: it has five bins total.

## Files

| file | keyed on | rows |
|---|---|---|
| `dd-v2-annotation-by-asv.csv.gz` | feature_id (primary) | 242,897 |
| `dd-v2-annotation-by-taxon.csv.gz` | 5.1.1 lineage (rollup) | 9,519 over 724 lineages |
| `dd-v2-asv-taxonomy-511.csv.gz` | feature_id | 27,559 — the re-mapped taxonomy |
| `dd-v2-pr2-500-to-511-crosswalk.csv.gz` | 5.0.0 path | 53,594 |
| `dd-v2-curation-worklist.csv` | 5.1.1 lineage | 822, effort-tagged |
| `dd-v2-curation-worklist-protist.csv` | 5.1.1 lineage | 678 |
| `dd-v2-annotation-long.csv.gz` | pr2_taxon_id | 170,624 — taxon-level, external DBs |
| `dd-v2-pr2-taxon-key.csv.gz` | pr2_taxon_id | 64,870 — the spine |
| `dd-v2-trophic-mdb-tmd.csv` | species + AphiaID | 604 |
| `dd-v2-crosswalk-collisions.csv` | v2 taxon | 145 |

## Source independence — read before weighting evidence

Two pairs of sources in this database are **not independent**. Agreement
between either pair is shared provenance, not corroboration.

**MDB and TMD.** TMD's `Morphotype` column uses MDB's mixoplankton functional
type vocabulary, asterisk convention included, and extends it with heterotroph
morphotypes (SH, GH, CV, PA) and finer NCM codes (pGNCM, eGNCM). 184 of 209
shared species agree exactly.

**The hand curation and Ramond.** 20 of Ramond's 30 trait fields share names
with the 41 curated fields — `Cover`, `Shape`, `Spicule`, `Symmetry`,
`Polarity`, `Colony`, `Motility`, `Chloroplast`, `Ingestion`,
`Symbiont_Location`, `Oxygen_Tolerance`, `Depth`, `Ploidy` and others. The
curation schema was evidently modelled on Ramond's. Where both speak — 936
lineage x trait pairs across 123 lineages — **97% of values are identical**,
which is far too high for independent derivation.

This does not diminish the curation. It relocates its value: the curation
earns its keep in the ~3,000 lineages Ramond cannot reach, not in the 123
where the two overlap. The 25 genuine disagreements that remain are listed in
`dd-v2-annotation-by-taxon.csv.gz` wherever `sources` names both.

## PIDA habitat scope

PIDA observations are retained **for all habitats**, not filtered to marine.
Of the habitat-tagged rows reaching our taxa: marine 12,254, freshwater 3,568,
brackish 595, saline water 6. A freshwater interaction record still says
something about what a genus is capable of, and discarding it would throw away
evidence rather than qualify it.

`interaction_habitat` is carried on every PIDA row, so filtering is a one-line
operation downstream for anyone who wants marine only. The scope decision is
deliberately the user's, not baked into the release.

Note separately that 91% of PIDA's annotation rows (78,314 of 86,089) attach at
genus rank. PIDA is the largest contributor by volume and the least specific by
evidence; filter on `evidence_rank` before treating any of it as a statement
about a species.

## Value canonicalisation (applied 2026-11-01)

All trait values pass through a single canonicaliser before storage:

- Integral numerics collapse to integer form, so `1`, `1.0` and ` 1 ` are one
  value. This alone removed 57 of 87 apparent curation-vs-Ramond conflicts,
  which were numeric formatting rather than disagreement.
- NFKC normalisation unifies compatibility characters, notably the micro sign
  (U+00B5) with Greek mu (U+03BC) in size ranges.
- Known typos corrected: `Heterpolar` to `Heteropolar`, `Phagptrophic` to
  `Phagotrophic`, `Elonagted` to `Elongated`, `asymmetric` and `Asymetrical`
  to `Asymmetrical`.
- Controlled-vocabulary collapse then runs on the text fields; 19 mappings
  over 104 cells remain after the steps above.

**Implementation caution.** Numeric detection uses a strict regular expression,
not `float()`. Python's `float()` accepts underscores as digit separators, so
`float("0_100")` returns 100.0 — values such as `0_100` and `02_25` in the
trait tables would be silently rewritten. Any future change to this step must
keep the strict pattern.

One cross-source variant is knowingly left in place: `HAB hemolysin` (curation)
against `HAB_hemolysin` (Ramond). The vocabulary collapse runs within a source,
not across sources.

## TMD provenance and version currency (resolved 2026-11-01)

TMD is now fully citable:

- Jones EL, Menden-Deuer S, Rynearson TA (2025). Dinoflagellate and ciliate
  trophic modes database. *Microbiology Resource Announcements* 14(7):e0015425.
  doi:10.1128/mra.00154-25
- Jones EL, Menden-Deuer S, Rynearson T (2025). Trophic Mode Database (TMD) for
  Dinoflagellate and Ciliate Species [Data set]. Zenodo.
  doi:10.5281/zenodo.15149504

This also justifies the TMD-priority rule in the MDB/TMD reconciliation: TMD is a
purpose-built trophic-mode database for exactly the two groups it covers
(262 Dinoflagellata, 116 Ciliophora), whereas MDB is a broader mixoplankton
compilation. Within TMD's scope it is the more specific authority. That is
consistent with its 94% placement rate, the highest of any external source.

**Version currency: resolved.** Our data table is TMD v1.1 and is current. The
Zenodo record increments (v2, v3) add only references to `Jones_TMD_References.docx`;
the trophic-mode data table itself is unchanged. So v1.1 is not a superseded copy.

One note for readers of the release: Zenodo record 15149504 as published contains
only the references document, not the data table, so the DOI alone does not
retrieve our input. Cite both the paper and the data set, and state that the data
table is TMD v1.1.
