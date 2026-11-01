# ---------------------------------------------------------------------------
# Database Darkly v2 - align external trait databases onto the PR2 taxonomy
#
# Purpose
#   Build one tidy, long-format annotation table in which every row is:
#       "source database X says trait T has value V for PR2 taxon Y,
#        and the match was made at rank R"
#
#   The PR2 taxon is the central identifier. Annotations attach at the most
#   specific rank that matches (species > genus > family) and every row
#   records which rank was used, so downstream users can filter on confidence.
#
# Inputs   input-data/DATABASE_*.{csv,xlsx}
#          pr2_version_5.1.1_taxonomy.xlsx  (PR2 release asset, see README)
# Outputs  annotation-pipeline/dd-v2-annotation-long.csv.gz
#          annotation-pipeline/dd-v2-pr2-taxon-key.csv.gz
# ---------------------------------------------------------------------------

library(tidyverse)
library(readxl)
library(digest)   # only for the stable taxon id hash

here_root  <- rprojroot::find_rstudio_root_file()
path_input <- file.path(here_root, "input-data")
path_out   <- file.path(here_root, "annotation-pipeline")
path_pr2   <- file.path(path_input, "pr2_version_5.1.1_taxonomy.xlsx")

dd_ranks <- c("domain", "supergroup", "division", "subdivision",
              "class", "order", "family", "genus", "species")

# --- helpers ---------------------------------------------------------------
# Normalisation must be identical across every source or the joins silently
# under-match. NFKD + latin-ascii strips accents; underscores and runs of
# whitespace collapse to a single space.
normalize_name <- function(x) {
  x %>%
    as.character() %>%
    stringi::stri_trans_nfkd() %>%
    stringi::stri_trans_general("latin-ascii") %>%
    str_replace_all("[\\s_]+", " ") %>%
    str_trim() %>%
    str_to_lower() %>%
    na_if("")
}

# PR2 writes binomials with underscores (Pelagomonas_calceolata)
species_key <- function(x) str_replace_all(normalize_name(x), " ", "_")

first_word <- function(x) normalize_name(word(as.character(x), 1))

# Values that mean "no data" in one or more of the source files
is_blank_value <- function(x) {
  is.na(x) | str_to_lower(str_trim(as.character(x))) %in%
    c("", "na", "nan", "none", "unknown", "not recorded", "not registered")
}

# --- 1. spine: PR2 taxonomy ------------------------------------------------
pr2_taxonomy <- read_excel(path_pr2) %>%
  mutate(
    pr2_taxon_path = pmap_chr(across(all_of(dd_ranks)),
                              ~ paste(replace_na(c(...), "NA"), collapse = "|")),
    pr2_taxon_id   = paste0("PR2T", map_chr(pr2_taxon_path,
                                            ~ str_sub(digest(.x, algo = "sha1"), 1, 12)))
  )

stopifnot(!any(duplicated(pr2_taxonomy$pr2_taxon_id)))

pr2_keys <- pr2_taxonomy %>%
  transmute(pr2_taxon_id,
            k_species = species_key(species),
            k_genus   = normalize_name(genus),
            k_family  = normalize_name(family))

# --- 2. tiered matcher -----------------------------------------------------
# src must carry: source_record, and any of k_species / k_genus / k_family.
# A source record is placed at the FIRST rank that finds a PR2 taxon; it is
# never counted twice.
match_tiered <- function(src) {
  tiers <- c(species = "k_species", genus = "k_genus", family = "k_family")
  placed <- tibble()
  remaining <- src

  for (rank_name in names(tiers)) {
    col <- tiers[[rank_name]]
    if (!col %in% names(remaining) || nrow(remaining) == 0) next

    lookup <- pr2_keys %>%
      select(pr2_taxon_id, all_of(col)) %>%
      drop_na(all_of(col))

    hit <- remaining %>%
      drop_na(all_of(col)) %>%
      inner_join(lookup, by = col, relationship = "many-to-many") %>%
      mutate(matched_rank = rank_name, join_key = .data[[col]])

    placed    <- bind_rows(placed, hit)
    remaining <- anti_join(remaining, hit, by = "source_record")
  }
  placed
}

# Melt a wide source table's trait columns to long, drop empties
melt_traits <- function(df, trait_cols) {
  df %>%
    pivot_longer(all_of(intersect(trait_cols, names(df))),
                 names_to = "trait", values_to = "value",
                 values_transform = as.character) %>%
    filter(!is_blank_value(value)) %>%
    mutate(value = str_trim(value))
}

# --- 3. Mixoplankton Database (MDB) ---------------------------------------
# Header sits on row 4 of the sheet; rows 1-3 are merged banner labels.
mdb_traits <- c("MFT", "HABs", "Mode of feeding", "prey taxonomic group",
                "Plastid source", "Symbiont source", "can form colonies",
                "has benthic stages", "has parasitic stages", "size class",
                "L (µm)", "ability to use NO3 ",
                "Evidence of mixoplankton activity")

trait_mdb <- read_excel(
    file.path(path_input, "DATABASE_The Mixoplankton Database - MDB (20230418).xlsx"),
    sheet = "MDB - 3Dec2022 ", skip = 3) %>%
  filter(!if_all(everything(), is.na)) %>%
  mutate(source_db     = "MDB",
         source_record = as.character(`Species Name`),
         k_species     = species_key(`Species Name`),
         k_genus       = first_word(`Species Name`)) %>%
  melt_traits(mdb_traits) %>%
  match_tiered()

# --- 4. TMD (Jones) -------------------------------------------------------
# Has a Synonym/Basionym column - use it as a second species-name pass.
tmd_prey <- c("Bacteria", "Detritus", "Diatoms", "Haptophytes", "Chlorophytes",
              "Cryptophytes", "Raphidophytes", "Pelagophytes", "Dinoflagellates",
              "Ciliates", "Copepods", "Metazoan Host")

tmd_raw <- read_csv(file.path(path_input, "DATABASE_TMDv1.1_Jones.csv"),
                    show_col_types = FALSE) %>%
  mutate(source_db     = "TMD",
         source_record = as.character(`Grazer Taxonomic ID`),
         prey_recorded = pmap_chr(across(all_of(intersect(tmd_prey, names(.)))),
                                  ~ paste(names(tmd_prey)[!is_blank_value(c(...))],
                                          collapse = "; ")))

# primary name, then each synonym, then genus
tmd_keys <- bind_rows(
  tmd_raw %>% mutate(k_species = species_key(`Grazer Taxonomic ID`)),
  tmd_raw %>%
    separate_longer_delim(`Synonym/Basionym`, delim = ",") %>%
    filter(!is_blank_value(`Synonym/Basionym`)) %>%
    mutate(k_species = species_key(`Synonym/Basionym`))
) %>%
  mutate(k_genus = first_word(`Grazer Taxonomic ID`))

trait_tmd <- tmd_keys %>%
  melt_traits(c("Feeding Mode", "Morphotype", "ESD", "prey_recorded")) %>%
  match_tiered()

# --- 5. Ramond functional traits ------------------------------------------
# Semicolon-delimited; Lineage is pipe-delimited UniEuk-style, and its
# terminal token uses Genus+species (Flamella_1+sp.).
ramond_raw <- read_delim(file.path(path_input, "DATABASE_functional-traits-ramond.csv"),
                         delim = ";", show_col_types = FALSE,
                         locale = locale(encoding = "latin1"))

ramond_traits <- setdiff(names(ramond_raw),
                         c("Lineage", "Fam", "Taxogroup", "Taxo1", "Last"))

trait_ramond <- ramond_raw %>%
  mutate(source_db     = "Ramond",
         source_record = Lineage,
         k_species     = species_key(str_replace_all(
                           str_extract(Lineage, "[^|]+$"), fixed("+"), "_")),
         k_genus       = normalize_name(Last),
         k_family      = normalize_name(Fam)) %>%
  melt_traits(ramond_traits) %>%
  match_tiered()

# --- 6. PIDA interactions -------------------------------------------------
# An edge list, not a node table: each row is emitted twice, once from each
# partner's point of view, so both organisms get annotated.
pida_raw <- read_csv(file.path(path_input, "DATABASE_PIDA_v_1.11_FORMATTED.csv"),
                     show_col_types = FALSE,
                     locale = locale(encoding = "latin1")) %>%
  rename_with(~ str_trim(str_remove(.x, "﻿")))

pida_side <- function(df, me, other, role) {
  df %>%
    transmute(
      source_db            = "PIDA",
      source_record        = paste(.data[[paste0("Genus ", me)]],
                                   .data[[paste0("Species ", me)]], "<->",
                                   .data[[paste0("Genus ", other)]],
                                   .data[[paste0("Species ", other)]]),
      k_species            = species_key(paste(.data[[paste0("Genus ", me)]],
                                               .data[[paste0("Species ", me)]])),
      k_genus              = normalize_name(.data[[paste0("Genus ", me)]]),
      interaction_partner  = str_squish(paste(.data[[paste0("Genus ", other)]],
                                              .data[[paste0("Species ", other)]])),
      ecological_interaction = `Ecological interaction`,
      interaction_type       = Interaction,
      interaction_habitat    = normalize_name(Habitat),
      interaction_role       = role)
}

trait_pida <- bind_rows(
    pida_side(pida_raw, "org1", "org2", "host"),
    pida_side(pida_raw, "org2", "org1", "symbiont")) %>%
  # a binomial built from a missing species reads as "genus na" - drop those
  mutate(k_species = if_else(str_detect(k_species, "_na$|^na_"),
                             NA_character_, k_species)) %>%
  melt_traits(c("interaction_partner", "ecological_interaction",
                "interaction_type", "interaction_habitat", "interaction_role")) %>%
  match_tiered()

# --- 7. combine and write -------------------------------------------------
annotation_long <- bind_rows(trait_mdb, trait_tmd, trait_ramond, trait_pida) %>%
  select(pr2_taxon_id, matched_rank, join_key, source_db,
         source_record, trait, value) %>%
  distinct()

pr2_taxon_key <- pr2_taxonomy %>%
  select(pr2_taxon_id, all_of(dd_ranks), mixoplankton, HAB_species,
         ecological_function, worms_id, worms_marine, gbif_id,
         n_seq_SSU, n_seq_operon, n_seq_coi)

write_csv(annotation_long, file.path(path_out, "dd-v2-annotation-long.csv.gz"))
write_csv(pr2_taxon_key,   file.path(path_out, "dd-v2-pr2-taxon-key.csv.gz"))

# --- 8. coverage report ---------------------------------------------------
coverage_by_source <- annotation_long %>%
  group_by(source_db) %>%
  summarise(annotation_rows   = n(),
            pr2_taxa_reached  = n_distinct(pr2_taxon_id),
            rows_species_rank = sum(matched_rank == "species"),
            rows_genus_rank   = sum(matched_rank == "genus"),
            rows_family_rank  = sum(matched_rank == "family"),
            distinct_traits   = n_distinct(trait),
            .groups = "drop")

write_csv(coverage_by_source, file.path(path_out, "dd-v2-coverage-by-source.csv"))
print(coverage_by_source)

message("annotation rows: ", nrow(annotation_long),
        " | PR2 taxa reached: ", n_distinct(annotation_long$pr2_taxon_id),
        " of ", nrow(pr2_taxonomy))
