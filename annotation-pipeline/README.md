# Database Darkly v2 — functional annotation pipeline

Aligns four external trait databases onto the **PR2 5.1.1** taxonomy, producing
one tidy long-format annotation table. This is pipeline 2 of v2; taxonomy
re-assignment (vsearch against PR2 then SILVA) runs separately on HPRC.

## Design: PR2 taxon as spine, name matching as the join

PR2 taxon is the central identifier (`pr2_taxon_id`, a sha1 of the 9-rank path).
But it cannot be the *join* key: only the Mixoplankton Database carries PR2
accession numbers, and only for 232 of its 435 species. The other three sources
have no PR2 identifiers at all.

So annotations attach at the **most specific rank that matches** —
species, then genus, then family — and every row records `matched_rank`.
Filter on it. A genus-rank row is a hypothesis propagated across congeners,
not an observation about that species.

## Files

| file | contents |
|---|---|
| `align-trait-databases.R` | the pipeline (tidyverse) |
| `dd-v2-annotation-long.csv.gz` | 170,624 rows: `pr2_taxon_id, matched_rank, join_key, source_db, source_record, trait, value` |
| `dd-v2-pr2-taxon-key.csv.gz` | spine: taxon id → 9 ranks + PR2's own annotations (`mixoplankton`, `HAB_species`, `ecological_function`, `worms_id`, `n_seq_SSU`) |
| `dd-v2-asv-coverage.csv.gz` | per-ASV annotation reachability for the May 2025 ASV set |
| `dd-v2-coverage-by-source.csv` | rows and taxa reached per source database |

Input `input-data/pr2_version_5.1.1_taxonomy.xlsx` is the PR2 release asset
from <https://github.com/pr2database/pr2database/releases/tag/v5.1.1>.

## Source records placed

| source | records | placed | at species | at genus |
|---|---|---|---|---|
| MDB | 435 | 375 (86%) | 232 | 143 |
| TMD (Jones) | 378 | 356 (94%) | 230 | 126 |
| Ramond | 2,007 | 1,221 (61%) | 830 | 391 |
| PIDA (both sides) | 4,896 | 3,843 (78%) | 1,989 | 1,854 |

Reaches 4,663 of 64,870 PR2 taxa (7.2%).

## Coverage of the deep-sea ASV set

Of 27,559 ASVs (May 2025 merge, taxonomy from PR2 5.0.0):

| class | ASVs | % |
|---|---|---|
| unassigned, no taxonomy | 9,565 | 34.7% |
| PR2 taxon matched, no functional annotation | 9,465 | 34.3% |
| taxonomy string does not resolve to a PR2 5.1.1 name | 5,903 | 21.4% |
| annotated, species-level evidence | 2,326 | 8.4% |
| annotated, genus-inferred | 300 | 1.1% |

**9.5% of ASVs carry any functional annotation.** Treat this as a floor: the
21.4% non-resolving bucket is inflated by PR2 5.0 → 5.1.1 name drift and will
shrink once taxonomy is re-assigned against 5.1.1.

By supergroup, % of assigned ASVs with species-level annotation:
Haptista 57.3, TSAR 11.9, Archaeplastida 10.2, Obazoa 3.9, PANNAM 0.0.

## Known limitations

- **Source bias.** None of the four databases is deep-sea. Ramond is coastal,
  MDB and TMD are largely surface plankton, PIDA is mixed. The annotation gap
  is therefore not random — it is concentrated in exactly the lineages this
  project exists to document.
- **AphiaID is a weaker key than the species name here.** PR2 5.1.1 has
  `worms_id` for only 16,117 unique taxa (26%); MDB's AphiaID reaches 184
  PR2 taxa versus 232 by name.
- **PR2's own `ecological_function` is coarse** — five bins (metazoans,
  phagotrophs, phototrophs, parasites, dinoflagellates). It is a cross-check,
  not a replacement for the external trait tables.
- **TMD has mojibake** in `Synonym/Basionym` (UTF-8 read as latin-1 upstream).
  Normalisation strips it, but synonym matching is weaker as a result.
- `DatabaseDarkly_taxa_06052024.csv` (v1 curation) is **not** yet joined in.
  It is keyed on PR2 4.x 8-rank strings and needs the 4.x → 5.x crosswalk first.

## Provenance note

The shipped CSVs were produced by a verified run of this logic in Python.
`align-trait-databases.R` is the lab-facing reimplementation and has **not been
executed** — no R was reachable from the session that wrote it. Run it once and
diff row counts against `dd-v2-coverage-by-source.csv` before trusting it.
Requires `digest` and `rprojroot` in addition to tidyverse and readxl.

---

# v1 curation crosswalk (PR2 4.x -> 5.x)

The crosswalk does **not** map ranks. ASV feature IDs are sequence hashes and all
17,934 v1 IDs persist into the v2 merge (verified, zero lost), so v1 curation
transfers along the sequence:

```
curated row -> v1 Taxon string -> v1 feature IDs -> (same IDs) -> v2 taxonomy -> pr2_taxon_id
```

All 1,095 curated Taxon strings join exactly to `input-data/taxonomy.tsv`
(whitespace trim only). 641 rows carry annotation, covering 8,226 ASVs; 6,833
land on an assigned v2 taxon, 1,393 (16.9%) fall to Unassigned under 5.x.

## Collision breakdown

201 of 547 curated taxa split across several v2 taxa. 145 v2 taxa receive more
than one curated record. Those 145 classify as:

| route | n | handling |
|---|---|---|
| no structured-field conflict | 107 | merge all; free text concatenated with ` \| ` |
| conflict, sources nested or mixed | 30 | deepest v1 record wins for structured fields |
| conflict, sources are siblings | 8 | `MANUAL_REVIEW_REQUIRED` |

Counting free-text fields (Notes, Other names, Resources, phylogenetic notes,
genes) there appear to be 62 conflicts; those fields are expected to differ and
are concatenated rather than resolved, which leaves 38 real ones and only 8
without a structural tiebreaker. See `dd-v2-crosswalk-collisions.csv`.

Structurally the 145 are 73 nested chains (50%), 46 mixed (32%), 26 siblings (18%).
Most collisions trace to **loss of assignment resolution** rather than taxonomic
reorganisation - the receiving v2 strings are often shallower than the v1 records
feeding them (e.g. `Dino-Group-II` at 6 ranks receiving 16 records that were 8
deep). That is partly a function of the vsearch thresholds (0.90 / 0.80), so it
is worth re-testing one group at higher identity before accepting the collapse.

## Two-level output

`dd-v2-annotation-by-asv.csv.gz` is primary - feature ID keyed, 248,713 rows
over 7,969 ASVs. `evidence_rank` is `asv_direct` for v1 curation (attached along
the sequence) and `species`/`genus`/`family` for the external databases
(propagated through the taxon). Keying on feature ID is what preserves the 1,393
curated ASVs that have no v2 taxonomy.

`dd-v2-annotation-by-taxon.csv.gz` is the rollup - 8,392 distinct
taxon/trait/value rows over 554 taxa, with `sources`, `n_asvs`,
`best_evidence_rank`, and `needs_review`.

## Coverage, with v1 curation included

| source | rows | ASVs reached |
|---|---|---|
| DD v1 curation | 94,047 | 6,833 |
| Ramond | 81,355 | 2,256 |
| PIDA | 49,347 | 1,190 |
| MDB | 21,613 | 690 |
| TMD | 2,351 | 320 |

**7,969 of 27,559 ASVs (28.9%) now carry annotation**, up from 9.5% with the
external databases alone. The hand curation reaches more of this dataset than
all four published databases combined - it was done on these deep-sea taxa,
which none of the published sources covers.

## Observed 4.x -> 5.x supergroup remap

Empirical, from the curated-covered ASVs - not a textbook mapping:

| 4.x | 5.x |
|---|---|
| Alveolata | TSAR (5,825) |
| Stramenopiles | TSAR (2,335) |
| Rhizaria | TSAR (1,432) |
| Opisthokonta | Obazoa (1,162) |
| Hacrobia | Haptista (682) + Cryptista (106) + Archaeplastida (69) + TSAR (97) |
| Apusozoa | Obazoa (42) + Eukaryota_X (26) + CRuMs (5) + Provora (2) |
| Archaeplastida | Archaeplastida (249) |
| Amoebozoa | Amoebozoa (109) |
| Excavata | Excavata (48) |

Hacrobia splitting and Apusozoa fragmenting break any naive mapping. Stragglers
(1 Alveolata -> Obazoa, 5 Opisthokonta -> Amoebozoa) are few enough to check by hand.

## Still to do

- Re-run with the PR2 5.1.1 assignment; the above uses the May 2025 5.0.0 output
  as a stand-in. The chain is version-independent, so it is a file swap.
- Adjudicate the 8 sibling conflicts.
- Re-save `DatabaseDarkly_taxa_06052024.csv` as UTF-8 (currently latin-1).
