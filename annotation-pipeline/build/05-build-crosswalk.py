import pandas as pd, sys
sys.path.insert(0,'/home/claude')
from concepts import CONCEPT_OF, CORE_28, DETAIL, PROVENANCE
O='/mnt/user-data/outputs/'

SOURCE = {
 'DD_v1_curation':dict(
   source_file='DatabaseDarkly_taxa_06052024.csv', source_version='2024-06-05',
   join_method='sequence hash (ASV feature ID) - no name matching',
   precedence_rank=0,
   citation='Hu Lab, Texas A&M University. Database Darkly hand curation (this work).',
   doi='pending - Zenodo v3'),
 'MDB':dict(
   source_file='DATABASE_The Mixoplankton Database - MDB (20230418).xlsx',
   source_version='MDB 2023-04-18',
   join_method='species name, then genus', precedence_rank=1,
   citation='Mitra A, Caron DA, Faure E, Flynn KJ, Leles SG, Hansen PJ, McManus GB, Not F, do Rosario Gomes H, Santoferrara LF, Stoecker DK, Tillmann U (2023). The Mixoplankton Database (MDB): Diversity of photo-phago-trophic plankton in form, function, and distribution across the global ocean. Journal of Eukaryotic Microbiology 70(4):e12972.',
   doi='10.1111/jeu.12972'),
 'TMD':dict(
   source_file='DATABASE_TMDv1.1_Jones.csv',
   source_version='TMD v1.1 - current; Zenodo v2/v3 add references only, data table unchanged',
   join_method='species name, then synonym/basionym, then genus', precedence_rank=2,
   citation='Jones EL, Menden-Deuer S, Rynearson TA (2025). Dinoflagellate and ciliate trophic modes database. Microbiology Resource Announcements 14(7):e0015425. Data set: Jones EL, Menden-Deuer S, Rynearson T (2025). Trophic Mode Database (TMD) for Dinoflagellate and Ciliate Species. Zenodo.',
   doi='10.1128/mra.00154-25 (paper); 10.5281/zenodo.15149504 (data set)'),
 'Ramond':dict(
   source_file='DATABASE_functional-traits-ramond.csv', source_version='as distributed',
   join_method='lineage terminal name, then Last as genus, then Fam as family',
   precedence_rank=3,
   citation='Ramond P, Sourisseau M, Simon N, Romac S, Schmitt S, Rigaut-Jalabert F, Henry N, de Vargas C, Siano R (2019). Coupling between taxonomic and functional diversity in protistan coastal communities. Environmental Microbiology 21(2):730-749.',
   doi='10.1111/1462-2920.14537'),
 'PIDA':dict(
   source_file='DATABASE_PIDA_v_1.11_FORMATTED.csv', source_version='v1.11 FORMATTED',
   join_method='genus+species binomial, then genus; emitted from both partners',
   precedence_rank=4,
   citation='Bjorbaekmo MFM, Evenstad A, Rosaeg LL, Krabberod AK, Logares R (2020). The planktonic protist interactome: where do we stand after a century of research? ISME Journal 14(2):544-559.',
   doi='10.1038/s41396-019-0542-5'),
 'PR2':dict(
   source_file='pr2_version_5.1.1_taxonomy.xlsx', source_version='PR2 5.1.1 (2025-10-27)',
   join_method='taxon path - this is the spine; also last-resort filler for trophic_mode',
   precedence_rank=5,
   citation='Guillou L, Bachar D, Audic S, Bass D, Berney C, Bittner L, et al. (2013). The Protist Ribosomal Reference database (PR2): a catalog of unicellular eukaryote small sub-unit rRNA sequences with curated taxonomy. Nucleic Acids Research 41:D597-D604.',
   doi='10.1093/nar/gks1160'),
}
# which source each field belongs to
FIELD_SOURCE={}
import pandas as _pd
ba=_pd.read_csv(O+'dd-v2-annotation-by-asv.csv.gz',low_memory=False)
for tr,g in ba.groupby('trait'):
    FIELD_SOURCE[tr]=sorted(set(g.source_db))
counts=ba.groupby(['trait','source_db']).size().to_dict()

PR2_FIELDS={'pr2_ecological_function':'trophic_mode (last resort) / standalone column',
            'pr2_mixoplankton':'standalone column','pr2_HAB_species':'standalone column',
            'pr2_worms_id':'standalone column','pr2_gbif_id':'standalone column',
            'pr2_n_seq_SSU':'standalone column'}
def block(c): return 'core_28' if c in CORE_28 else ('detail' if c in DETAIL else 'provenance')

rows=[]
for field,concept in CONCEPT_OF.items():
    for db in FIELD_SOURCE.get(field,['(not present in this build)']):
        m=SOURCE.get(db,{})
        rows.append(dict(concept=concept, block=block(concept), source_field=field,
            source_db=db, n_asv_rows=counts.get((field,db),0), **m))
for f,note in PR2_FIELDS.items():
    m=SOURCE['PR2']
    rows.append(dict(concept=note, block='pr2_native', source_field=f, source_db='PR2',
                     n_asv_rows=0, **m))
X=pd.DataFrame(rows)
order={'core_28':0,'detail':1,'provenance':2,'pr2_native':3}
X=X.sort_values(['block','concept','precedence_rank'],
                key=lambda s: s.map(order) if s.name=='block' else s)
X=X[['concept','block','source_field','source_db','n_asv_rows','precedence_rank',
     'join_method','source_file','source_version','citation','doi']]
X.to_csv(O+'dd-v2-crosswalk.csv',index=False)
print(f"crosswalk rows: {len(X)}  (one per source_field x source_db)")
print(f"  concepts: {X[X.block!='pr2_native'].concept.nunique()} | source fields: {X.source_field.nunique()} | sources: {X.source_db.nunique()}")
print()
print("rows contributed per source:")
print(X.groupby('source_db').n_asv_rows.sum().sort_values(ascending=False).to_string())
print()
print("UNVERIFIED provenance:")
print(X[X.doi=='UNKNOWN'][['concept','source_field','source_db']].to_string(index=False))
X.to_pickle('/home/claude/XWALK.pkl')
