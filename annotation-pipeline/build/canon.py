# shared value canonicaliser
import re, unicodedata, pandas as pd
_TYPO={'heterpolar':'Heteropolar','phagptrophic':'Phagotrophic','elonagted':'Elongated',
       'asymetrical':'Asymmetrical','asymmetric':'Asymmetrical','parasitic':None}
# strict: no underscores, no spaces - float() would silently accept 0_100 as 100
_NUM=re.compile(r'^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$')
def canon_value(v):
    """'1', '1.0' and ' 1 ' become one value; known typos fixed; non-numeric left alone."""
    if v is None or (isinstance(v,float) and pd.isna(v)): return None
    s=unicodedata.normalize('NFKC',str(v)).strip()
    if s=='' or s.lower() in ('nan','na','none'): return None
    if _NUM.match(s):
        f=float(s)
        return str(int(f)) if f==int(f) and abs(f)<1e15 else repr(f)
    low=s.lower()
    if low in _TYPO and _TYPO[low] is not None: return _TYPO[low]
    return re.sub(r'\s+',' ',s)
