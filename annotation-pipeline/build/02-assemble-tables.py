import pandas as pd, numpy as np
U='/mnt/user-data/uploads/Database-Darkly/'; O='/mnt/user-data/outputs/'
R=['domain','supergroup','division','subdivision','class','order','family','genus','species']
CUR=pd.read_pickle('/home/claude/CUR.pkl'); p51=pd.read_pickle('/home/claude/p51.pkl')
v2r=pd.read_pickle('/home/claude/v2remap.pkl')
cur_src=pd.read_csv(U+'DatabaseDarkly_taxa_06052024.csv',low_memory=False)
ANN=[c for c in cur_src.columns[9:]]

# occurrence
t=pd.read_csv(U+'db-update-may_2025/deepsea-18s-merged-asv-table-05022025.tsv',sep='\t',skiprows=1,index_col=0)
reads=t.sum(axis=1); tot=reads.sum(); prev=(t>0).sum(axis=1)
cols=pd.Series(t.columns); vent=cols[cols.str.contains('vent',case=False)].tolist()
vfrac=(t[vent].sum(axis=1)/reads.replace(0,np.nan))
occ=pd.DataFrame({'total_reads':reads,'max_prevalence':prev,'vent_read_frac':vfrac})
asv=v2r.rename(columns={'Feature ID':'feature_id','Taxon':'taxon_500'})[
    ['feature_id','taxon_500','lineage_511','pr2_taxon_id_511','lca_depth','remap_status']]
asv=asv.merge(occ,left_on='feature_id',right_index=True,how='left')
asv['pct_total_reads']=100*asv.total_reads/tot

ext=pd.read_csv(O+'dd-v2-annotation-by-taxon.csv.gz')
extw=(ext[ext.sources.str.contains('MDB|TMD|Ramond|PIDA',na=False)]
      .groupby('lineage_511').agg(
        ext_sources=('sources',lambda s:'; '.join(sorted({x.strip() for v in s for x in str(v).split(';')}))),
        ext_n_annotations=('trait','size'),
        ext_best_evidence=('best_evidence_rank','first')).reset_index())
troph=(ext[ext.trait.isin(['MFT','Feeding Mode','Morphotype','Trophic strategy'])]
       .groupby('lineage_511').apply(lambda g:'; '.join(f"{r.trait}={r.value}" for _,r in g.iterrows()),
                                      include_groups=False)
       .rename('ext_trophic_calls').reset_index())

# curated wide
curw=CUR.pivot_table(index='lineage_511',columns='trait',values='value',aggfunc='first')
curw.columns=[f'cur_{c}' for c in curw.columns]
prov=CUR.groupby('lineage_511').agg(cur_sources=('sources',lambda s:'; '.join(sorted(set(s)))),
    cur_resolution_kind=('resolution_kind','first'),
    cur_n_fields=('trait','nunique'),
    cur_needs_review=('needs_review','any')).reset_index()

# observed lineages
obs=(asv[asv.lineage_511.notna()].groupby('lineage_511').agg(
    n_asvs=('feature_id','size'), total_reads=('total_reads','sum'),
    max_prevalence=('max_prevalence','max'), vent_read_frac=('vent_read_frac','mean'),
    lca_depth=('lca_depth','max'), pr2_taxon_id_511=('pr2_taxon_id_511','first')).reset_index())
obs['pct_total_reads']=(100*obs.total_reads/tot).round(4)
ranks=pd.DataFrame([ (l+'|NA'*(9-len(l.split('|')))).split('|') for l in obs.lineage_511],columns=R)
obs=pd.concat([obs,ranks],axis=1)
pk=p51.drop_duplicates('path').set_index('path')
for src,dst in [('ecological_function','pr2_ecological_function'),('mixoplankton','pr2_mixoplankton'),
                ('HAB_species','pr2_HAB_species'),('worms_id','pr2_worms_id'),
                ('gbif_id','pr2_gbif_id'),('n_seq_SSU','pr2_n_seq_SSU')]:
    obs[dst]=obs.lineage_511.map(pk[src].to_dict())

DB=(obs.merge(prov,on='lineage_511',how='left').merge(curw,on='lineage_511',how='left')
       .merge(extw,on='lineage_511',how='left').merge(troph,on='lineage_511',how='left'))
META=['Metazoa','Fungi','Embryophyceae','Streptophyta']
DB['kingdom_class']=np.where(DB.lineage_511.str.contains('|'.join(META)),'metazoa_fungi_plant','protist')
DB['effort_tier']=np.where(DB.kingdom_class=='protist','full','medium')
DB['annotation_status']=np.select(
    [DB.cur_n_fields.notna()&DB.ext_n_annotations.notna(), DB.cur_n_fields.notna(),
     DB.ext_n_annotations.notna()],
    ['curated_and_external','curated_only','external_only'],default='unannotated')
front=['lineage_511','pr2_taxon_id_511','lca_depth']+R+[
    'n_asvs','total_reads','pct_total_reads','max_prevalence','vent_read_frac',
    'kingdom_class','effort_tier','annotation_status',
    'pr2_ecological_function','pr2_mixoplankton','pr2_HAB_species','pr2_worms_id','pr2_gbif_id','pr2_n_seq_SSU',
    'ext_sources','ext_n_annotations','ext_best_evidence','ext_trophic_calls',
    'cur_sources','cur_n_fields','cur_resolution_kind','cur_needs_review']
DB=DB[front+[c for c in DB.columns if c not in front]]
DB=DB.sort_values('total_reads',ascending=False)
print(f"Taxon_Database: {len(DB)} lineages x {len(DB.columns)} cols")
print(DB.annotation_status.value_counts().to_string())
print(f"  reads covered by annotated lineages: {DB.loc[DB.annotation_status!='unannotated','pct_total_reads'].sum():.1f}%")
DB.to_pickle('/home/claude/DB.pkl'); asv.to_pickle('/home/claude/ASVIDX.pkl')
print(f"ASV_Index: {len(asv)} x {len(asv.columns)}")
