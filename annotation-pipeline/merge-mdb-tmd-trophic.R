# ---------------------------------------------------------------------------
# Database Darkly v2 - reconcile the two trophic databases (MDB + TMD)
#
# MDB = Mixoplankton Database (Mitra et al. 2023); classifies mixoplankton by
#       mixoplankton functional type (MFT) and carries WoRMS AphiaIDs.
# TMD = trophic/grazer trait compilation (TMDv1.1, "Jones"); its Morphotype
#       column uses the SAME MFT vocabulary and extends it with heterotroph
#       morphotypes (SH, GH, CV, PA) and finer NCM codes (pGNCM, eGNCM).
#
# Because the vocabularies are shared, these two sources are NOT independent.
# Agreement between them is not corroboration. The `concordance` column is
# for triage, not for weighting evidence.
#
# WoRMS is the unifying taxonomy layer: AphiaID from MDB where present,
# otherwise inherited from PR2's own worms_id via a species-name match.
# Species with no AphiaID need a live WoRMS lookup (see bottom of file).
# ---------------------------------------------------------------------------

library(tidyverse)
library(readxl)
library(digest)

here_root  <- rprojroot::find_rstudio_root_file()
path_input <- file.path(here_root, "input-data")
path_out   <- file.path(here_root, "annotation-pipeline")

dd_ranks <- c("domain", "supergroup", "division", "subdivision",
              "class", "order", "family", "genus", "species")

normalize_name <- function(x) {
  x %>% as.character() %>%
    stringi::stri_trans_nfkd() %>%
    stringi::stri_trans_general("latin-ascii") %>%
    str_replace_all("[\\s_]+", " ") %>%
    str_trim() %>% str_to_lower() %>% na_if("")
}
species_key <- function(x) str_replace_all(normalize_name(x), " ", "_")

# --- PR2 spine, carrying its own WoRMS ids --------------------------------
pr2_taxonomy <- read_excel(file.path(path_input, "pr2_version_5.1.1_taxonomy.xlsx")) %>%
  mutate(pr2_taxon_path = pmap_chr(across(all_of(dd_ranks)),
                                   ~ paste(replace_na(c(...), "NA"), collapse = "|")),
         pr2_taxon_id   = paste0("PR2T", map_chr(pr2_taxon_path,
                                   ~ str_sub(digest(.x, algo = "sha1"), 1, 12))),
         k_species = species_key(species),
         k_genus   = normalize_name(genus))

pr2_by_species <- pr2_taxonomy %>%
  filter(!is.na(k_species)) %>% distinct(k_species, .keep_all = TRUE) %>%
  select(k_species, pr2_taxon_id, pr2_worms_id = worms_id)

pr2_by_genus <- pr2_taxonomy %>%
  filter(!is.na(k_genus)) %>% distinct(k_genus, .keep_all = TRUE) %>%
  select(k_genus, pr2_taxon_id_genus = pr2_taxon_id)

# --- MDB ------------------------------------------------------------------
trophic_mdb <- read_excel(
    file.path(path_input, "DATABASE_The Mixoplankton Database - MDB (20230418).xlsx"),
    sheet = "MDB - 3Dec2022 ", skip = 3) %>%
  filter(!if_all(everything(), is.na)) %>%
  transmute(species_key   = normalize_name(`Species Name`),
            mdb_name      = as.character(`Species Name`),
            mdb_aphia_id  = suppressWarnings(as.integer(as.numeric(AphiaID))),
            mdb_group_adl = `Taxonomic Group`,
            mdb_mft       = MFT,
            mdb_mode_of_feeding = `Mode of feeding`,
            mdb_hab        = HABs,
            mdb_size_class = `size class`,
            mdb_pr2_accessions = `PR2 Accession Number`) %>%
  filter(!is.na(species_key)) %>% distinct(species_key, .keep_all = TRUE)

# --- TMD ------------------------------------------------------------------
trophic_tmd <- read_csv(file.path(path_input, "DATABASE_TMDv1.1_Jones.csv"),
                        show_col_types = FALSE) %>%
  transmute(species_key = normalize_name(`Grazer Taxonomic ID`),
            tmd_name    = as.character(`Grazer Taxonomic ID`),
            tmd_phylum  = Phylum,
            tmd_feeding_mode = `Feeding Mode`,
            tmd_morphotype   = Morphotype,
            tmd_esd          = ESD,
            tmd_synonym      = `Synonym/Basionym`) %>%
  filter(!is.na(species_key)) %>% distinct(species_key, .keep_all = TRUE)

# --- union, WoRMS layer, PR2 spine, concordance ---------------------------
trophic_merged <- full_join(trophic_mdb, trophic_tmd, by = "species_key") %>%
  mutate(species_name = coalesce(mdb_name, tmd_name),
         in_mdb = !is.na(mdb_name),
         in_tmd = !is.na(tmd_name),
         k_species = str_replace_all(species_key, " ", "_"),
         k_genus   = normalize_name(word(species_key, 1))) %>%
  left_join(pr2_by_species, by = "k_species") %>%
  left_join(pr2_by_genus,   by = "k_genus") %>%
  mutate(
    # WoRMS: MDB's AphiaID first, then PR2's worms_id
    aphia_id = coalesce(mdb_aphia_id,
                        suppressWarnings(as.integer(as.numeric(pr2_worms_id)))),
    aphia_source = case_when(!is.na(mdb_aphia_id) ~ "MDB",
                             !is.na(pr2_worms_id) ~ "PR2",
                             TRUE                 ~ NA_character_),
    # PR2 spine: species match preferred, else genus
    pr2_matched_rank = case_when(!is.na(pr2_taxon_id)       ~ "species",
                                 !is.na(pr2_taxon_id_genus) ~ "genus",
                                 TRUE                       ~ NA_character_),
    pr2_taxon_id = coalesce(pr2_taxon_id, pr2_taxon_id_genus),
    # concordance is triage only - the two sources share a vocabulary
    concordance = case_when(
      in_mdb & in_tmd & tmd_feeding_mode %in% c("Heterotroph", "Autotroph") ~ "conflict",
      in_mdb & in_tmd & str_trim(mdb_mft) == str_trim(tmd_morphotype)       ~ "agree",
      in_mdb & in_tmd                                                      ~ "differ",
      in_mdb                                                               ~ "mdb_only",
      in_tmd                                                               ~ "tmd_only")) %>%
  # ---- conflict resolution: TMD takes priority ---------------------------
  # Rule set by Sarah: where MDB and TMD disagree, TMD wins. MDB values are
  # retained in their own columns so nothing is discarded, and
  # `resolution_note` records exactly why each call was chosen.
  #
  # Two notes flag places where TMD-priority LOSES information:
  #   asterisk_only_difference         - drops MDB's uncertainty flag
  #   tmd_parasite_overlay_mdb_plastid - drops MDB's plastid status in favour
  #                                      of a parasite call; both can be true
  mutate(
    mft_base = str_remove_all(str_trim(mdb_mft), fixed("*")),
    mor_base = str_remove_all(str_trim(tmd_morphotype), fixed("*")),
    resolution_note = case_when(
      !in_mdb ~ "tmd_only",
      !in_tmd ~ "mdb_only",
      str_trim(mdb_mft) == str_trim(tmd_morphotype) ~ "identical",
      tmd_feeding_mode %in% c("Heterotroph", "Autotroph") ~ "tmd_overrides_conflict",
      mft_base == mor_base ~ "asterisk_only_difference",
      str_detect(mor_base, "(^|/)PA($|/)") &
        mft_base %in% c("CM","GNCM","pSNCM","eSNCM","pGNCM","eGNCM") ~
          "tmd_parasite_overlay_mdb_plastid",
      !is.na(mft_base) & !is.na(mor_base) ~ "tmd_overrides_differ",
      TRUE ~ "partial"),
    trophic_call_resolved = case_when(
      resolution_note == "mdb_only" ~ mdb_mft,
      resolution_note == "tmd_only" ~ coalesce(tmd_morphotype, tmd_feeding_mode),
      TRUE ~ coalesce(tmd_morphotype, tmd_feeding_mode, mdb_mft)),
    trophic_call_source = case_when(
      resolution_note == "identical" ~ "both_agree",
      resolution_note == "mdb_only"  ~ "MDB",
      TRUE ~ "TMD")) %>%
  select(species_name, species_key, aphia_id, aphia_source,
         pr2_taxon_id, pr2_matched_rank, in_mdb, in_tmd,
         trophic_call_resolved, trophic_call_source, resolution_note,
         mdb_group_adl, tmd_phylum, mdb_mft, tmd_feeding_mode, tmd_morphotype,
         concordance, mdb_mode_of_feeding, mdb_hab, mdb_size_class, tmd_esd,
         mdb_pr2_accessions, tmd_synonym)

write_csv(trophic_merged, file.path(path_out, "dd-v2-trophic-mdb-tmd.csv"))

count(trophic_merged, resolution_note)
count(trophic_merged, trophic_call_source)
message("unique species: ", nrow(trophic_merged),
        " | with AphiaID: ", sum(!is.na(trophic_merged$aphia_id)))

# --- WoRMS: run locally, this session's shells cannot reach the API -------
# Route 1 (quick): batch-resolve names to accepted AphiaIDs.
#   library(worrms)
#   name_batches <- trophic_merged$species_name %>% unique() %>% split(ceiling(seq_along(.)/50))
#   worms_resolved <- map_dfr(name_batches, possibly(~ wm_records_names(.x, fuzzy = FALSE) %>%
#       bind_rows() %>% select(scientificname, AphiaID, status, valid_name,
#                              valid_AphiaID, isMarine, isExtinct), otherwise = tibble()))
#   write_csv(worms_resolved, file.path(path_out, "dd-v2-worms-resolved.csv"))
#
# Route 2 (for the Zenodo release): use the dated WoRMS DwC-A export from
#   marinespecies.org/download instead of the API, so the published database
#   pins one taxonomy version rather than drifting with live queries.
