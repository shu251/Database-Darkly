# Maps all 72 source field names onto one canonical concept each.
# Nothing is dropped: every source field lands somewhere.
CONCEPT_OF = {
 # --- trophy -------------------------------------------------------------
 'Trophic strategy':'trophic_mode','Feeding Mode':'trophic_mode',
 'Ingestion':'ingestion_mode','Mode of feeding':'ingestion_mode',
 'Behavior':'feeding_behavior','Behaviour':'feeding_behavior',
 'MFT':'mixoplankton_type','Morphotype':'mixoplankton_type',
 'Prey Specialization':'prey','Prey_Specialisation':'prey',
 'prey taxonomic group':'prey','prey_recorded':'prey',
 'ability to use NO3 ':'nitrate_use',
 # --- phototrophy --------------------------------------------------------
 'Chloroplast':'plastid_status',
 'Plastid source':'plastid_source','Plast_Origin':'plastid_source',
 # --- symbiosis / interaction -------------------------------------------
 'Symbiotic':'symbiosis_type','Symbiontic':'symbiosis_type',
 'ecological_interaction':'symbiosis_type',
 'Mutualistic Host':'symbiosis_partner','Mutualistic_Host':'symbiosis_partner',
 'Symbiont source':'symbiosis_partner','interaction_partner':'symbiosis_partner',
 'Symbiont location':'symbiosis_location','Symbiont_Location':'symbiosis_location',
 'Host Specialization':'host_specialisation','Host_Specialisation':'host_specialisation',
 'Symbiont Specialization':'symbiont_specialisation','Symbiont_Specialisation':'symbiont_specialisation',
 'interaction_type':'interaction_type','interaction_habitat':'interaction_habitat',
 'interaction_role':'interaction_role','has parasitic stages':'parasitic_stage',
 # --- morphology ---------------------------------------------------------
 'Cell Cover':'cell_cover','Cover':'cell_cover',
 'Shape':'cell_shape','Symmetry':'symmetry','Polarity':'polarity','Spicule':'spicule',
 'Motility':'motility','Colony':'colony','can form colonies':'colony',
 'SizeMin':'cell_size','SizeMax':'cell_size','ESD':'cell_size',
 'L (μm)':'cell_size','size class':'cell_size',
 'Mucilage':'mucilage','Chemical Signal':'chemical_signal','Chemical_Signal':'chemical_signal',
 # --- environment --------------------------------------------------------
 'Nutrient Affinity':'nutrient_affinity','Nutrient_Afinity':'nutrient_affinity',
 'Oxygen Tolerance':'oxygen_tolerance','Oxygen_Tolerance':'oxygen_tolerance',
 'Salinity':'salinity','Temperature':'temperature','Depth':'depth',
 'Benthic Phase':'benthic_phase','Benthic_Phase':'benthic_phase',
 'has benthic stages':'benthic_phase',
 'Presence in other subeuphotic regions?':'subeuphotic_presence',
 'Presence in extreme environment?':'extreme_environment_presence',
 # --- life history -------------------------------------------------------
 'Cyst Spore':'cyst_spore','Cyst_Spore':'cyst_spore',
 'Sexual reproduction or division':'sexual_reproduction',
 'Ploidy':'ploidy','Genome Size':'genome_size',
 # --- hazard -------------------------------------------------------------
 'HABs':'hab_status','Toxygenity':'toxigenicity',
 # --- evidence and notes -------------------------------------------------
 'Evidence of mixoplankton activity':'evidence_mixoplankton',
 'Lab-based studies':'evidence_lab','Field-based studies':'evidence_field',
 'Sequencing':'evidence_sequencing','Gene expression':'evidence_gene_expression',
 'Genes of note':'genes_of_note','Other names':'other_names',
 'Notes':'notes','Notes on phylogenetic placement':'notes_phylogeny',
 'Resources':'references',
}
# order concepts appear in the sheet
CONCEPT_ORDER = [
 'trophic_mode','ingestion_mode','feeding_behavior','mixoplankton_type','prey','nitrate_use',
 'plastid_status','plastid_source',
 'symbiosis_type','symbiosis_partner','symbiosis_location','host_specialisation',
 'symbiont_specialisation','parasitic_stage','interaction_type','interaction_role','interaction_habitat',
 'cell_cover','cell_shape','symmetry','polarity','spicule','motility','colony','cell_size',
 'mucilage','chemical_signal',
 'nutrient_affinity','oxygen_tolerance','salinity','temperature','depth','benthic_phase',
 'subeuphotic_presence','extreme_environment_presence',
 'cyst_spore','sexual_reproduction','ploidy','genome_size',
 'hab_status','toxigenicity',
 'evidence_mixoplankton','evidence_lab','evidence_field','evidence_sequencing',
 'evidence_gene_expression','genes_of_note','other_names','notes','notes_phylogeny','references',
]
# precedence for the primary value. Own curation first (deep-sea specific),
# then Mitra, then Jones, then Ramond, then PIDA.
SOURCE_RANK = {'DD_v1_curation':0,'MDB':1,'TMD':2,'Ramond':3,'PIDA':4}

# --- presentation blocks -------------------------------------------------
# The 28 core biological concepts lead the sheet; detail and provenance
# follow. Every one of the 51 is still a column - this is ordering, not
# selection.
CORE_28 = ['trophic_mode','mixoplankton_type','feeding_behavior','prey',
 'plastid_status','plastid_source','symbiosis_type','symbiosis_partner',
 'symbiosis_location','cell_cover','cell_shape','symmetry','polarity','spicule',
 'motility','colony','cell_size','oxygen_tolerance','salinity','temperature',
 'depth','benthic_phase','cyst_spore','ploidy','genome_size',
 'sexual_reproduction','hab_status','toxigenicity']
DETAIL = ['ingestion_mode','nitrate_use','host_specialisation',
 'symbiont_specialisation','parasitic_stage','interaction_type','interaction_role',
 'interaction_habitat','mucilage','chemical_signal','nutrient_affinity',
 'subeuphotic_presence','extreme_environment_presence']
PROVENANCE = ['evidence_mixoplankton','evidence_lab','evidence_field',
 'evidence_sequencing','evidence_gene_expression','genes_of_note','other_names',
 'notes','notes_phylogeny','references']
CONCEPT_ORDER = CORE_28 + DETAIL + PROVENANCE
