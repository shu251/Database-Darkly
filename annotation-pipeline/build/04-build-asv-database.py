import pandas as pd, numpy as np, sys
sys.path.insert(0,'/home/claude')
from concepts import CONCEPT_OF, CONCEPT_ORDER, SOURCE_RANK
U='/mnt/user-data/uploads/Database-Darkly/'; O='/mnt/user-data/outputs/'
R=['domain','supergroup','division','subdivision','class','order','family','genus','species']

by_asv=pd.read_csv(O+'dd-v2-annotation-by-asv.csv.gz',low_memory=False)
by_asv['concept']=by_asv.trait.map(CONCEPT_OF)
assert by_asv.concept.notna().all(), "unmapped trait"
by_asv['_rank']=by_asv.source_db.map(SOURCE_RANK).fillna(9)

# primary value per (asv, concept) by source precedence; alternates kept
by_asv=by_asv.sort_values(['feature_id','concept','_rank'])
g=by_asv.groupby(['feature_id','concept'],sort=False)
prim=g.first().reset_index()[['feature_id','concept','value','source_db','evidence_rank']]
nval=g.value.nunique().rename('n_val').reset_index()
prim=prim.merge(nval,on=['feature_id','concept'])

wide=prim.pivot(index='feature_id',columns='concept',values='value')
for c in CONCEPT_ORDER:
    if c not in wide.columns: wide[c]=None
wide=wide[CONCEPT_ORDER]

# lossless: anything the precedence rule did not promote
conf=by_asv.merge(prim[['feature_id','concept','value']].rename(columns={'value':'_primary'}),
                  on=['feature_id','concept'])
conf=conf[conf.value!=conf._primary]
alt=(conf.groupby('feature_id')
     .apply(lambda d:'; '.join(f"{r.concept}={r.value} ({r.source_db})" for _,r in d.iterrows()),
            include_groups=False).rename('alternate_values'))
srcs=by_asv.groupby('feature_id').source_db.apply(lambda s:'; '.join(sorted(set(s)))).rename('annotation_sources')
nann=by_asv.groupby('feature_id').size().rename('n_annotations')
best=by_asv.groupby('feature_id').evidence_rank.apply(
    lambda s: 'asv_direct' if 'asv_direct' in set(s) else
              ('species' if 'species' in set(s) else
               ('genus' if 'genus' in set(s) else 'family'))).rename('best_evidence_rank')

# taxonomy + occurrence spine
v2=pd.read_pickle('/home/claude/v2remap.pkl'); p51=pd.read_pickle('/home/claude/p51.pkl')
asv=v2.rename(columns={'Feature ID':'feature_id'})[
    ['feature_id','lineage_511','pr2_taxon_id_511','lca_depth','remap_status']].set_index('feature_id')
t=pd.read_csv(U+'db-update-may_2025/deepsea-18s-merged-asv-table-05022025.tsv',sep='\t',skiprows=1,index_col=0)
tot=t.sum().sum(); cols=pd.Series(t.columns)
vent=cols[cols.str.contains('vent',case=False)].tolist()
occ=pd.DataFrame({'total_reads':t.sum(axis=1),'n_samples':(t>0).sum(axis=1),
                  'vent_read_frac':(t[vent].sum(axis=1)/t.sum(axis=1).replace(0,np.nan)).round(3)})
occ['pct_total_reads']=(100*occ.total_reads/tot).round(5)

DB=asv.join(occ).join(wide).join(alt).join(srcs).join(nann).join(best)
ranks=pd.DataFrame([ (l+'|NA'*(9-len(str(l).split('|')))).split('|') if isinstance(l,str) else ['NA']*9
                     for l in DB.lineage_511],columns=R,index=DB.index)
DB=DB.join(ranks)
pk=p51.drop_duplicates('path').set_index('path')
for s,d in [('ecological_function','pr2_ecological_function'),('mixoplankton','pr2_mixoplankton'),
            ('HAB_species','pr2_HAB_species'),('worms_id','pr2_worms_id'),
            ('gbif_id','pr2_gbif_id'),('n_seq_SSU','pr2_n_seq_SSU')]:
    DB[d]=DB.lineage_511.map(pk[s].to_dict())
# --- trophic ladder: finest available, PR2's coarse bins as last resort ---
DB['trophic_resolution']=np.where(DB.trophic_mode.notna(),'fine_source',
    np.where(DB.pr2_ecological_function.notna(),'coarse_pr2',None))
DB['trophic_mode']=DB.trophic_mode.fillna(DB.pr2_ecological_function)
DB['n_annotations']=DB.n_annotations.fillna(0).astype(int)
DB['annotation_status']=np.where(DB.n_annotations>0,
    np.where(DB.annotation_sources.fillna('').str.contains('DD_v1_curation'),
             'curated','external_only'),
    np.where(DB.remap_status.eq('unassigned'),'unassigned_no_taxonomy','no_annotation'))
META=['Metazoa','Fungi','Embryophyceae','Streptophyta']
DB['kingdom_class']=np.where(DB.lineage_511.fillna('').str.contains('|'.join(META)),
                             'metazoa_fungi_plant','protist')
front=(['lineage_511','pr2_taxon_id_511','lca_depth','remap_status']+R+
       ['kingdom_class','total_reads','pct_total_reads','n_samples','vent_read_frac',
        'annotation_status','n_annotations','best_evidence_rank','annotation_sources',
        'pr2_ecological_function','pr2_mixoplankton','pr2_HAB_species',
        'pr2_worms_id','pr2_gbif_id','pr2_n_seq_SSU','trophic_resolution']
       +CONCEPT_ORDER+['alternate_values'])
DB=DB.reset_index()[['feature_id']+front].sort_values('total_reads',ascending=False)
print(f"ASV_Database: {len(DB):,} rows x {len(DB.columns)} cols")
print(DB.annotation_status.value_counts().to_string())
filled=DB[CONCEPT_ORDER].notna().sum().sort_values(ascending=False)
print(f"\nconcepts populated (top 15 of {len(CONCEPT_ORDER)}):")
print(filled.head(15).to_string())
print(f"\nconcepts with zero values: {list(filled[filled==0].index)}")
print(f"ASVs with >=1 concept filled: {(DB[CONCEPT_ORDER].notna().any(axis=1)).sum():,}")
print(f"ASVs with alternate_values  : {DB.alternate_values.notna().sum():,}")
DB.to_pickle('/home/claude/ASVDB.pkl')
DB.to_csv(O+'dd-v2-asv-database.csv.gz',index=False,compression='gzip')
import os; print(f"\ncsv.gz size: {os.path.getsize(O+'dd-v2-asv-database.csv.gz')/1e6:.2f} MB")
