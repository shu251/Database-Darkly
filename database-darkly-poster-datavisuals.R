library(tidyverse)

# Import database:
db_raw <- read.csv("/Users/skhu/Desktop/Projects/Database-Darkly/input-data/taxonomic-assignments.csv")

# Outline of code
glimpse(db_raw)

# Supergroup and Phylum summary - WHO is present?
pre_process_df <- db_raw %>% 
  add_column(COUNT = 1) %>% 
  filter(!(Supergroup == ""))


## Plot supergroup summary
pre_process_df %>% 
  group_by(Supergroup) %>% # Try Filtering and using phylum here!
    summarise(SUM_SUPERGROUP = sum(COUNT)) %>% 
  ggplot(aes(y = SUM_SUPERGROUP, x = 1, fill = Supergroup)) +
  geom_bar(stat = "identity", color = "black") +
  theme_minimal()

pre_process_df %>%  #Try filtering by a specific supergroup!
  mutate(Species_IDed = case_when(
    is.na(Species) ~ "No species assigned",
    # Symbiotic == "longsentence" ~ "New sentence"
    !is.na(Species) ~ "Species level assigned"
  )) %>% 
  group_by(Species_IDed) %>% 
  summarise(SUM_SPP = sum(COUNT)) %>% 
  ggplot(aes(y = SUM_SPP, x = 1, fill = Species_IDed)) +
  geom_bar(stat = "identity", color = "black") +
  theme_minimal()


##

#Filter ciliates
Cils <- pre_process_df %>%
  filter(Phylum == "Ciliophora") %>%
  filter(!(Genus == "NA"))
#Make SYMBIOTIC uniform
revised_Cils <- Cils %>%
  mutate(SYMBIOSIS = case_when(
    `Symbiotic` == "Some species photosymbiotic with green algae (Chlorella)" ~ "Photosymbiotic",
    `Symbiotic` == "Photosymbiosis" ~ "Photosymbiotic",
    `Symbiotic` == "" ~ "No",
    `Symbiotic` == "Some species have photosymbiotic interactions with green algea. The parasite microsporidia have been observed in stentor. " ~ "Photosymbiotic",
    `Symbiotic` == "Yes" ~ "Symbiotic",
    `Symbiotic` == "Unknown symbiotic relationship with alpha/gamma proteobacteria, Oceanospirillaceae" ~ "Unresolved symbiotic relationship",
    `Symbiotic` == "Unknown symbiotic relationship with alpha/gamma proteobacteria" ~ "Unresolved symbiotic relationship",
    `Symbiotic` == "Some species have unknown symbiotic relationships with bacteriodetes, proteobacteria, and planctomycetes" ~ "Unresolved symbiotic relationship",
    `Symbiotic` == "Some species (flava and carnea) have an unknown symbiotic relationship with alpha and gamma proteobacteria" ~ "Unresolved symbiotic relationship",
    `Symbiotic` == "Salpingella attenuata has an unresolved symbiotic relationship with the diatom Synedra" ~ "Unresolved symbiotic relationship",
    .default = `Symbiotic`
  ))

symbiosis_order <- c("No", "Commensalist", "Parasite", "Photosymbiotic", "Symbiotic", "Unresolved symbiotic relationship")

#Plot
revised_Cils %>%
  group_by(SYMBIOSIS) %>%
  summarise(SUM_SYMB = sum(COUNT)) %>%
  mutate(SYMBIOSIS_ORDER = factor(SYMBIOSIS, levels = symbiosis_order)) %>% 
  ggplot(aes(y = SUM_SYMB, x = 1, fill = SYMBIOSIS_ORDER)) +
  geom_bar(stat = "identity", color = "black") +
  labs(x = "", y = "Distribution", fill = "Symbiotic Activity", title = "Symbiotic Activity of Recovered Ciliates") +
  # scale_fill_manual(values = c("#1f78b4", "#fb9a99")) +
  theme_minimal()
