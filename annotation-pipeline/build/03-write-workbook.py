import pandas as pd, numpy as np
from openpyxl import Workbook
from openpyxl.styles import Font,PatternFill,Alignment,Border,Side
from openpyxl.utils import get_column_letter
from openpyxl.utils.dataframe import dataframe_to_rows
O='/mnt/user-data/outputs/'
DB=pd.read_pickle('/home/claude/DB.pkl'); ASV=pd.read_pickle('/home/claude/ASVIDX.pkl')
ASVDB=pd.read_pickle('/home/claude/ASVDB.pkl')
import sys as _s; _s.path.insert(0,'/home/claude')
from concepts import CONCEPT_OF, CONCEPT_ORDER
CM=pd.DataFrame([{'concept':c,'source_field':f,
                  'source_db':('PR2 5.1.1' if f.startswith('pr2') else '')}
                 for f,c in sorted(CONCEPT_OF.items(), key=lambda kv:(kv[1],kv[0]))])
CM=CM[['concept','source_field']]
XW=pd.read_pickle('/home/claude/XWALK.pkl')
VM=pd.read_pickle('/home/claude/VM.pkl'); RV=pd.read_pickle('/home/claude/RV.pkl')
CUR=pd.read_pickle('/home/claude/CUR.pkl')
WL=pd.read_csv(O+'dd-v2-curation-worklist.csv')
# --- data hygiene before writing ---
UNRES='UNRESOLVED_LCA'
for _df in (DB,RV,WL):
    if 'lineage_511' in _df.columns:
        _df['lineage_511']=(_df['lineage_511'].astype('object')
            .where(_df['lineage_511'].notna(),UNRES))
        _df.loc[_df['lineage_511'].astype(str).str.strip()=='','lineage_511']=UNRES
if 'lineage_511' in ASV.columns:
    ASV['lineage_511']=ASV['lineage_511'].astype('object')
    ASV.loc[ASV['lineage_511'].astype(str).str.strip().isin(['','nan']),'lineage_511']=None
def _debool(df):
    df=df.copy()
    for c in df.columns:
        if df[c].dtype==bool: df[c]=df[c].map({True:'TRUE',False:'FALSE'})
        elif df[c].dtype==object:
            if df[c].dropna().map(lambda v: isinstance(v,(bool,)) ).any():
                df[c]=df[c].map(lambda v:'TRUE' if v is True else ('FALSE' if v is False else v))
    return df
DB=_debool(DB); RV=_debool(RV); WL=_debool(WL); ASV=_debool(ASV)
TR=_debool(pd.read_csv(O+'dd-v2-trophic-mdb-tmd.csv'))


ARIAL=lambda **k: Font(name='Arial',color='000000',**k)
GREY=PatternFill('solid',fgColor='D9D9D9')
HDR=GREY; HDRF=ARIAL(bold=True,size=10)
SEC=ARIAL(bold=True,size=10)
BODY=ARIAL(size=10); NOTE=ARIAL(size=10)
YEL=GREY   # no yellow anywhere; section rows use the same light grey as headers
thin=Side(style='thin',color='BFBFBF'); BOX=Border(left=thin,right=thin,top=thin,bottom=thin)

wb=Workbook(); wb.remove(wb.active)
# Arial 10 pt black as the workbook default, so all 27,559 ASV rows inherit it
# without per-cell styling (which would bloat the file).
try:
    wb._named_styles['Normal'].font=Font(name='Arial',size=10,color='000000')
except Exception as _e:
    print('WARNING could not set default font:',_e)

def sheet(name,df,freeze='A2',widths=None):
    ws=wb.create_sheet(name)
    ws.append(list(df.columns))
    for c in range(1,len(df.columns)+1):
        cell=ws.cell(1,c); cell.fill=HDR; cell.font=HDRF
        cell.alignment=Alignment(vertical='center',wrap_text=True)
    for row in df.itertuples(index=False):
        ws.append(['' if (isinstance(v,float) and np.isnan(v)) or v is None else
                   (str(v)[:32000] if isinstance(v,str) else v) for v in row])
    ws.freeze_panes=freeze
    ws.auto_filter.ref=f"A1:{get_column_letter(len(df.columns))}{len(df)+1}"
    ws.row_dimensions[1].height=42
    for i,col in enumerate(df.columns,1):
        w=min(max(12,len(str(col))+2, int(df[col].astype(str).str.len().quantile(.9)) if len(df) else 12),46)
        ws.column_dimensions[get_column_letter(i)].width=w
    return ws

# ---------------- README / data dictionary ----------------
rd=wb.create_sheet('README')
rd.column_dimensions['A'].width=34; rd.column_dimensions['B'].width=18
rd.column_dimensions['C'].width=96
rows=[]
def S(t): rows.append(('SEC',t,'',''))
def L(a,b='',c=''): rows.append(('L',a,b,c))

S('Database Darkly — functional annotation database')
L('Release','Version 2.1 — 2026-11-01','Deep-sea microbial eukaryote 18S rRNA (V4) amplicons with functional and ecological annotation. This workbook is self-contained: everything needed to read and cite it is on this sheet.')
L('Taxonomy','PR2 5.1.1','Protist Ribosomal Reference database, release 5.1.1 (2025-10-27). The PR2 nine-rank path is the authoritative taxonomy throughout.')
L('Sequences','27,559 ASVs','176 samples, 16,638,540 reads. Hydrothermal vents: Piccard and Von Damm (Mid-Cayman Rise), Sea Cliff and Apollo (Gorda Ridge), Axial Seamount (Juan de Fuca Ridge), including Axial 2022 and 2023.')
L('License','CC BY 4.0','')
L('Version 3','in preparation','Phylogenetic placement of ASVs onto a full-length 18S reference tree is in preparation. This release is annotation only.')
L('','','')
S('How to cite')
L('This database','','Hu, S. K. (2026). Database Darkly files. Zenodo. https://doi.org/10.5281/zenodo.15496977')
L('Originating survey','','Hu, S. K., Smith, A. R., Anderson, R. E., Sylva, S. P., Setzer, M., Steadmon, M., Frank, K. L., Chan, E. W., Lim, D. S. S., German, C. R., Breier, J. A., Lang, S. Q., Butterfield, D. A., Fortunato, C. S., Seewald, J. S., & Huber, J. A. (2022). Globally-distributed microbial eukaryotes exhibit endemism at deep-sea hydrothermal vents. Molecular Ecology, 32(23), 6580-6598. https://doi.org/10.1111/mec.16745')
L('','','')
S('Source databases — cite these if you use the annotations')
L('PR2 5.1.1','taxonomy spine','Guillou, L., Bachar, D., Audic, S., Bass, D., Berney, C., Bittner, L., et al. (2013). The Protist Ribosomal Reference database (PR2). Nucleic Acids Research, 41, D597-D604. https://doi.org/10.1093/nar/gks1160')
L('MDB (Mitra)','mixoplankton','Mitra, A., Caron, D. A., Faure, E., Flynn, K. J., Leles, S. G., Hansen, P. J., McManus, G. B., Not, F., do Rosario Gomes, H., Santoferrara, L. F., Stoecker, D. K., & Tillmann, U. (2023). The Mixoplankton Database (MDB). Journal of Eukaryotic Microbiology, 70(4), e12972. https://doi.org/10.1111/jeu.12972')
L('TMD v1.1 (Jones)','trophic mode','Jones, E. L., Menden-Deuer, S., & Rynearson, T. A. (2025). Dinoflagellate and ciliate trophic modes database. Microbiology Resource Announcements, 14(7), e0015425. https://doi.org/10.1128/mra.00154-25 — data set: https://doi.org/10.5281/zenodo.15149504 (the DOI resolves to a references document; the data table is TMD v1.1)')
L('Ramond et al.','functional traits','Ramond, P., Sourisseau, M., Simon, N., Romac, S., Schmitt, S., Rigaut-Jalabert, F., Henry, N., de Vargas, C., & Siano, R. (2019). Coupling between taxonomic and functional diversity in protistan coastal communities. Environmental Microbiology, 21(2), 730-749. https://doi.org/10.1111/1462-2920.14537')
L('PIDA v1.11','interactions','Bjorbaekmo, M. F. M., Evenstad, A., Rosaeg, L. L., Krabberod, A. K., & Logares, R. (2020). The planktonic protist interactome: where do we stand after a century of research? ISME Journal, 14(2), 544-559. https://doi.org/10.1038/s41396-019-0542-5')
L('Taxonomic framework','MDB groups','Adl, S. M., et al. (2019). Revisions to the classification, nomenclature, and diversity of eukaryotes. Journal of Eukaryotic Microbiology, 66, 4-119.')
L('','','')
S('Method and code')
L('Full protocol','GitHub','github.com/shu251/Database-Darkly — annotation-pipeline/PROTOCOL.md gives the 11-step curation protocol; VERSIONS.md pins every version and records caveats; build/ regenerates this workbook.')
L('','','')
S('Database Darkly — compiled annotation database')
L('Built','2026-11-01','Sheet-by-sheet documentation follows. Taxon_Database is one row per observed PR2 5.1.1 lineage; ASV_Database is one row per ASV and is the primary sheet.')
L('Reference taxonomy','PR2 5.1.1','pr2_version_5.1.1_taxonomy.xlsx, GitHub release asset. 64,870 species-level taxa.')
L('ASV assignment','PR2 5.0.0 → 5.1.1','vsearch consensus (0.90 identity, 0.80 consensus) against PR2 5.0.0, May 2025 HPRC run, then carried onto 5.1.1 by the official taxon crosswalk. NOT re-assigned against 5.1.1 — see VERSIONS.md.')
L('Sequence set','27,559 ASVs','18S V4, deep-sea hydrothermal vents: Piccard, Von Damm, Axial Seamount, Gorda Ridge, plus Axial 2022/2023.')
L('Total reads','16,638,540','')
L('','','')
S('Sheets')
L('Taxon_Database','1,236 rows','The compiled database. One row per 5.1.1 lineage observed in the ASV set.')
L('ASV_Index','27,559 rows','One row per ASV: taxonomy, re-mapping status, reads, prevalence, vent fraction.')
L('Curation_Worklist','822 rows','Uncurated taxa ranked by read abundance, effort-tagged.')
L('Trophic_MDB_TMD','604 rows','Mixoplankton Database + TMD reconciled, TMD priority on conflict.')
L('Review_Queue','146 rows','Lineages where more than one curated record collided, and how it was resolved.')
L('Vocabulary_Map','25 rows','Controlled-vocabulary normalisations applied to the curated fields.')
L('','','')
S('ASV_Database — the primary sheet')
L('one row per ASV','27,559','Every ASV in the deep-sea set, annotated or not. The ASV is the unit of this database; the taxon sheet is a rollup of it.')
L('51 concept columns','','The 85 trait field names across the five annotation sources collapse onto 51 canonical concepts — one column per biological idea instead of one per source label. Nothing is dropped.')
L('Crosswalk sheet','99 rows','Concept map plus origin of curation: for every source field, which concept it feeds, which database and file it came from, that source version, how it was joined, its precedence rank, how many ASV rows it contributed, and the full citation with DOI.')
L('precedence','','Where more than one source speaks to the same concept, the column holds the value from the highest-precedence source: own curation, then MDB (Mitra), then TMD (Jones), then Ramond, then PIDA.')
L('alternate_values','2,260 ASVs','Every value the precedence rule did not promote, with its source. This is what makes the collapse lossless — no observation is discarded, it is relegated.')
L('pr2_* columns','','PR2 5.1.1 own annotations are kept as separate columns rather than folded into the concepts. pr2_ecological_function has only five bins, so folding it in would have replaced finer calls from Mitra and Jones with coarser ones.')
L('best_evidence_rank','','asv_direct (curation, attached along the sequence) > species > genus > family. Filter on this before treating a value as an observation about a species.')
L('','','')
S('Column groups in Taxon_Database — and how each was synthesized')
L('lineage_511','derived','Pipe-joined PR2 5.1.1 rank path, truncated at the depth the ASV assignment supports. THE PRIMARY KEY of this sheet.')
L('pr2_taxon_id_511','derived','PR2T + first 12 hex of sha1(9-rank path). Populated only where the lineage resolves to species (lca_depth=9).')
L('lca_depth','derived','1=domain … 9=species. Lowest common ancestor depth of the 5.0.0→5.1.1 crosswalk targets. Read every annotation on this row as applying at this depth, not below it.')
L('domain … species','PR2 5.1.1','The nine ranks, split out of lineage_511. "NA" where unresolved.')
L('n_asvs / total_reads','ASV table','Count and summed reads of ASVs assigned to this lineage. From deepsea-18s-merged-asv-table-05022025.tsv.')
L('pct_total_reads','derived','100 × total_reads / 16,638,540.')
L('max_prevalence','ASV table','Highest number of samples (of 176) any single ASV in this lineage occurs in.')
L('vent_read_frac','derived','Mean per-ASV fraction of reads falling in the 63 sample columns whose name contains "vent". A deep-sea specificity signal, not a formal enrichment test.')
L('kingdom_class / effort_tier','policy','protist → full effort (all 41 curated fields); metazoa/fungi/plant → medium effort (reduced 9-field set). Set 2026-11-01.')
L('annotation_status','derived','curated_and_external / curated_only / external_only / unannotated.')
L('pr2_* columns','PR2 5.1.1','Carried verbatim from PR2 own taxonomy table: ecological_function (5 coarse bins), mixoplankton (MFT code), HAB_species, worms_id (AphiaID), gbif_id, n_seq_SSU (reference sequences backing this taxon).')
L('ext_sources','derived','Which external trait databases reached this lineage: MDB, TMD, Ramond, PIDA.')
L('ext_n_annotations','derived','Count of external trait/value rows for this lineage.')
L('ext_best_evidence','derived','Most specific rank at which any external annotation attached: species > genus > family.')
L('ext_trophic_calls','derived','MFT / Feeding Mode / Morphotype / Trophic strategy values from the external databases, as field=value pairs.')
L('cur_* columns','v1 curation','The 41 hand-curated fields from DatabaseDarkly_taxa_06052024.csv, transferred along the ASV sequence hash (not by name matching). Multi-valued cells are joined with " | ".')
L('cur_sources','v1 curation','The PR2 4.x taxon string(s) of the curated record(s) feeding this row.')
L('cur_n_fields','derived','How many of the 41 curated fields are populated.')
L('cur_resolution_kind','derived','single · A_wrong_lineage_sweep (one source matched the lineage, others dropped) · B_sibling_variation (all sources legitimate, values kept multi-valued).')
L('cur_needs_review','derived','TRUE where a B_sibling_variation collision left a field with more than one value. 93 cells.')
L('','','')
S('Synthesis method, in order')
L('1. Vocabulary normalisation','','218 cells in 9 curated fields collapsed to canonical values (e.g. four spellings of "Passive Ambush Feeder"). Plus 4 typo fixes: Phagptrophic→Phagotrophic, asymmetric/Asymetrical→Asymmetrical, Parasitic→Parasite (Symbiotic field), Elonagted→Elongated. See Vocabulary_Map.')
L('2. PR2 crosswalk','','PR2 5.0.0 → 5.1.1 built from both official taxonomy tables. 94.6% identical 9-rank paths; 99.7% mapped; 1 supergroup change.')
L('3. ASV re-mapping','','Each ASV 5.0.0 taxonomy string → longest matching 5.0.0 lineage prefix → crosswalk → LCA of targets. 17,994 ASVs (65.3%) get a 5.1.1 lineage; 11,068 resolve to species.')
L('4. v1 curation transfer','','Sequence-anchored: curated taxon → v1 ASV feature IDs → identical IDs in v2 → 5.1.1 lineage. All 17,934 v1 feature IDs persist into v2, so no name matching is involved.')
L('5. Collision resolution','','146 lineages received >1 curated record. 56 resolved as wrong-lineage sweeps (keep the source whose 4.x lineage overlaps the 5.1.1 target most); 90 kept multi-valued as genuine sibling variation.')
L('6. External alignment','','MDB, TMD, Ramond, PIDA matched to PR2 5.1.1 at species, then genus, then family; the rank used is recorded. MDB/TMD conflicts resolved in TMD\'s favour.')
L('','','')
S('Read these caveats before using the sheet')
L('Genus/family-rank annotation is a hypothesis','','An annotation attached at genus propagates to every congener. Filter on ext_best_evidence and lca_depth before treating a value as an observation about a species.')
L('MDB and TMD are not independent','','TMD\'s Morphotype column uses MDB\'s MFT vocabulary; 184 of 209 shared species agree exactly. Agreement between them is shared provenance, not corroboration.')
L('The external databases are not deep-sea','','Ramond is coastal, MDB and TMD largely surface plankton, PIDA mixed. MDB\'s 54 geographic columns are all surface Longhurst provinces. The annotation gap is concentrated in the lineages this project exists to document.')
L('Curated annotation does not reach the new ASVs','','v1 curation transfers along sequence, so it covers only the 17,934 ASVs that existed in v1. Axial 2022/2023 ASVs sharing an annotated lineage carry no curated row. This is why lineage-level read coverage (61.8%) exceeds ASV-level (47.1%).')
L('Assignment resolution, not taxonomy, drives collisions','','Receiving 5.1.1 lineages are often shallower than the 4.x records feeding them. Partly a function of the 0.90/0.80 vsearch thresholds — worth re-testing one group at higher identity.')

for kind,a,b,c in rows:
    r=rd.max_row+1
    if kind=='SEC':
        rd.cell(r,1,a).font=SEC; rd.cell(r,1).fill=YEL
        for _c in (2,3):
            rd.cell(r,_c).fill=YEL; rd.cell(r,_c).font=SEC
    else:
        rd.cell(r,1,a).font=ARIAL(bold=True,size=10)
        rd.cell(r,2,b).font=NOTE
        rd.cell(r,3,c).font=BODY
        rd.cell(r,3).alignment=Alignment(wrap_text=True,vertical='top')
rd.freeze_panes='A2'

# ---------------- data sheets ----------------
sheet('Taxon_Database',DB,freeze='B2')
sheet('ASV_Database',ASVDB,freeze='B2')
sheet('Crosswalk',XW)
sheet('Curation_Worklist',WL)
sheet('Trophic_MDB_TMD',TR)
sheet('Review_Queue',RV)
sheet('Vocabulary_Map',VM)

# live summary block on README
r=rd.max_row+3
rd.cell(r,1,'LIVE COUNTS (recalculated from the sheets)').font=SEC
for _c in (1,2,3):
    rd.cell(r,_c).fill=YEL; rd.cell(r,_c).font=SEC
from openpyxl.utils import get_column_letter as _CL
def _c(df,name): return _CL(list(df.columns).index(name)+1)
_st=_c(DB,'annotation_status'); _nr=_c(DB,'cur_needs_review'); _kc=_c(WL,'kingdom_class')
f=[('Lineages in Taxon_Database','=COUNTA(Taxon_Database!A2:A100000)'),
   ('  of which curated',f'=COUNTIF(Taxon_Database!{_st}2:{_st}100000,"curated*")'),
   ('  of which external only',f'=COUNTIF(Taxon_Database!{_st}2:{_st}100000,"external_only")'),
   ('  of which unannotated',f'=COUNTIF(Taxon_Database!{_st}2:{_st}100000,"unannotated")'),
   ('  flagged cur_needs_review',f'=COUNTIF(Taxon_Database!{_nr}2:{_nr}100000,"TRUE")'),
   ('ASVs in ASV_Index','=COUNTA(ASV_Index!A2:A100000)'),
   ('Worklist taxa','=COUNTA(Curation_Worklist!A2:A100000)'),
   (f'  protist, full effort',f'=COUNTIF(Curation_Worklist!{_kc}2:{_kc}100000,"protist")'),
   ('Vocabulary normalisations','=COUNTA(Vocabulary_Map!A2:A10000)'),
   ('Collisions resolved','=COUNTA(Review_Queue!A2:A10000)')]
for i,(lab,fml) in enumerate(f,1):
    rd.cell(r+i,1,lab).font=ARIAL(bold=True,size=10)
    cell=rd.cell(r+i,2,fml); cell.font=ARIAL(size=10); cell.border=BOX

wb.save(O+'Database-Darkly-v2.1-2026-11-01.xlsx')
print("written. sheets:",wb.sheetnames)
print("Taxon_Database cols:",len(DB.columns),"rows:",len(DB))
