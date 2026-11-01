import pandas as pd, numpy as np, re, unicodedata, collections, json
U='/mnt/user-data/uploads/Database-Darkly/'; O='/mnt/user-data/outputs/'
R=['domain','supergroup','division','subdivision','class','order','family','genus','species']

# ---------- 1. vocabulary normalisation ----------
cur=pd.read_csv(U+'DatabaseDarkly_taxa_06052024.csv',low_memory=False)
ANN=[c for c in cur.columns[9:]]
FREE={'Notes','Other names','Resources','Notes on phylogenetic placement','Genes of note',
      'Lab-based studies','Field-based studies','Sequencing','Gene expression',
      'Prey Specialization','Symbiont Specialization','Host Specialization','Mutualistic Host',
      'Presence in other subeuphotic regions?','Presence in extreme environment?'}
VOCAB=[c for c in ANN if c not in FREE]
def ck(s): return re.sub(r'[^a-z0-9]','',unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
MANUAL={'Ingestion':{'Phagptrophic':'Phagotrophic'},
        'Symmetry':{'asymmetric':'Asymmetrical','Asymetrical':'Asymmetrical'},
        'Symbiotic':{'Parasitic':'Parasite'},
        'Shape':{'Elonagted':'Elongated'}}
vocab_map=[]
for c in VOCAB:
    vals=[str(v).strip() for v in cur[c] if pd.notna(v) and str(v).strip()]
    if not vals: continue
    g=collections.defaultdict(collections.Counter)
    for v in vals: g[ck(v)][v]+=1
    m={}
    for k,ctr in g.items():
        canon=max(sorted(ctr), key=lambda x:(ctr[x], x==x.strip().title()))
        for v in ctr:
            if v!=canon: m[v]=canon
    m.update(MANUAL.get(c,{}))
    if m:
        cur[c]=cur[c].map(lambda v: m.get(str(v).strip(), v) if pd.notna(v) else v)
        for a,b in sorted(m.items()):
            vocab_map.append(dict(field=c,original_value=a,canonical_value=b,
                                  n_rows_changed=int((pd.read_csv(U+'DatabaseDarkly_taxa_06052024.csv',
                                      low_memory=False)[c].astype(str).str.strip()==a).sum())))
VM=pd.DataFrame(vocab_map)
print(f"vocabulary normalisation: {len(VM)} value mappings across {VM.field.nunique()} fields, "
      f"{VM.n_rows_changed.sum()} cell changes")
cur['k']=cur.Taxon.astype(str).str.strip()
curi=cur.drop_duplicates('k').set_index('k')

# ---------- 2. conflict resolution, Kind A vs Kind B ----------
v1=pd.read_csv(U+'input-data/taxonomy.tsv',sep='\t'); v1['k']=v1.Taxon.astype(str).str.strip()
v2r=pd.read_pickle('/home/claude/v2remap.pkl')
p51=pd.read_pickle('/home/claude/p51.pkl')
bridge=v1[['Feature ID','k']].merge(
    v2r[['Feature ID','Taxon','lineage_511','pr2_taxon_id_511','lca_depth']],on='Feature ID')
bridge=bridge[bridge.k.isin(set(curi.index[curi[ANN].notna().any(axis=1)]))]
bridge=bridge[bridge.lineage_511.notna()]

def names(s,sep=';'): return {x for x in str(s).rstrip(sep).split(sep) if x and x!='nan'}
review=[]; resolved_rows=[]
for lin,g in bridge.groupby('lineage_511'):
    srcs=sorted(g.k.unique()); tgt=names(lin,'|')
    if len(srcs)>1:
        ov={s:len(names(s)&tgt) for s in srcs}
        best=max(ov.values()); winners=[s for s in srcs if ov[s]==best]
        # Kind A: one source is clearly the matching lineage
        kind='A_wrong_lineage_sweep' if len(winners)==1 and best>max([ov[s] for s in srcs if ov[s]<best]+[0]) else 'B_sibling_variation'
        use = winners if kind.startswith('A') else srcs
    else:
        kind='single'; use=srcs; ov={srcs[0]:len(names(srcs[0])&tgt)}
    fids=g['Feature ID'].tolist()
    for f in ANN:
        vals=[(s,str(curi.at[s,f]).strip()) for s in use
              if pd.notna(curi.at[s,f]) and str(curi.at[s,f]).strip()]
        if not vals: continue
        uniq=sorted({v for _,v in vals})
        resolved_rows.append(dict(lineage_511=lin,trait=f,
            value=' | '.join(uniq), n_values=len(uniq),
            sources='; '.join(sorted({s for s,_ in vals})),
            resolution_kind=kind,
            needs_review=(kind=='B_sibling_variation' and len(uniq)>1)))
    if len(srcs)>1:
        review.append(dict(lineage_511=lin,n_curated_sources=len(srcs),resolution_kind=kind,
            kept_sources='; '.join(use),dropped_sources='; '.join([s for s in srcs if s not in use]),
            n_asvs=len(fids)))
CUR=pd.DataFrame(resolved_rows); RV=pd.DataFrame(review)
print(f"curated annotation resolved: {len(CUR)} lineage/trait rows over {CUR.lineage_511.nunique()} lineages")
print(RV.resolution_kind.value_counts().to_string())
print(f"  multi-valued cells kept for review: {CUR.needs_review.sum()}")
CUR.to_pickle('/home/claude/CUR.pkl'); VM.to_pickle('/home/claude/VM.pkl'); RV.to_pickle('/home/claude/RV.pkl')
