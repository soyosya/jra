import csv
from collections import defaultdict
from datetime import date
BASE=r"C:\jra\analysis\zenso-jra-verify\jra_csv"
def pdate(s):
    s=s.strip().split()[0].replace("/","-");y,m,d=s.split("-");return date(int(y),int(m),int(d))
def fnum(x):
    try: return float(x)
    except: return None
def relpos(rank,n):
    r=fnum(rank);nn=fnum(n)
    if r is None or nn is None or nn<=1 or r<=0: return None
    return (r-1.0)/(nn-1.0)

# history: early position (1st corner, fallback 2nd)
hist=defaultdict(list)
with open(BASE+r"\history_feat.csv",encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        nm=(row.get("馬名") or "").strip()
        if not nm: continue
        try: d=pdate(row["開催日"])
        except: continue
        n=row.get("頭数")
        e=relpos(row.get("一コーナー"),n)
        if e is None: e=relpos(row.get("二コーナー"),n)
        hist[nm].append((d,e))
for nm in hist: hist[nm].sort()
def early(nm,rd):
    runs=[x for x in hist.get(nm,[]) if x[0]<rd][-3:]
    e=[x[1] for x in runs if x[1] is not None]
    return sum(e)/len(e) if e else None

# kousei
compi=defaultdict(list)
with open(BASE+r"\コンピ指数.csv",encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        v=fnum(row["指数"])
        if v is not None: compi[(row["開催日"],row["開催場所"],row["レース番号"])].append(v)
def kousei(vals):
    s=sorted(vals,reverse=True);n=len(s)
    if n<2: return "不明"
    idx1=s[0];r13=s[0]-s[2] if n>=3 else s[0]-s[1];danso=99
    for k in range(1,min(8,n)):
        if s[k-1]-s[k]>=10: danso=k;break
    kc=sum(1 for v in s if v>=idx1-12)
    if idx1<=78 or r13<=6: return "混戦警戒"
    if danso==1 and kc<=2: return "1強"
    if danso==1: return "1強-下割れ"
    if danso==2: return "2強"
    if danso==3: return "3強"
    return "上位混戦"
kmap={k:kousei(v) for k,v in compi.items()}

def band(d):
    d=int(d);return "短" if d<=1200 else ("マ" if d<=1600 else ("中" if d<=2000 else "長"))
races=defaultdict(list); meta={}
def load(fn,surf):
    with open(fn,encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            rk=(row["開催日"],row["開催場所"],row["レース番号"])
            try: chaku=int(row["着順"])
            except: continue
            try: cr=int(row["指数順位"]) if row["指数順位"] else None
            except: cr=None
            races[rk].append({"nm":row["馬名"].strip(),"chaku":chaku,"cr":cr,
                              "e":early(row["馬名"].strip(),pdate(row["開催日"])),
                              "tan":fnum(row["単勝"]) or 0,"fuk":fnum(row["複勝"]) or 0,"yr":row["開催日"][:4]})
            meta[rk]=(surf,row["距離"])
load(BASE+r"\target_turf.csv","芝"); load(BASE+r"\target_outcomes.csv","ダ")

FRONT=0.25
def newA(): return {"n":0,"win":0,"hit":0,"tan":0.0,"fuk":0.0}
def add(a,r):
    a["n"]+=1
    if r["chaku"]==1: a["win"]+=1
    if 1<=r["chaku"]<=3: a["hit"]+=1
    a["tan"]+=r["tan"];a["fuk"]+=r["fuk"]
def rep(a):
    n=a["n"];return "n=0" if n==0 else f"n={n:5d} 勝率{a['win']/n:5.1%} 複勝率{a['hit']/n:5.1%} 単回収{a['tan']/(n*100):6.1%} 複回収{a['fuk']/(n*100):6.1%}"

rules=["F1_最前","F2_単騎逃","F3_単騎コ≤4","F4_前×コ7+"]
agg=defaultdict(lambda: defaultdict(newA))  # rule->scope
def pick(rr):
    fronts=[r for r in rr if r["e"] is not None and r["e"]<FRONT]
    out={}
    if fronts:
        out["F1_最前"]=min(fronts,key=lambda r:r["e"])
        if len(fronts)==1:
            out["F2_単騎逃"]=fronts[0]
            if fronts[0]["cr"] and fronts[0]["cr"]<=4: out["F3_単騎コ≤4"]=fronts[0]
        lo=[r for r in fronts if r["cr"] and r["cr"]>=7]
        if lo: out["F4_前×コ7+"]=min(lo,key=lambda r:r["e"])
    return out
for rk,rr in races.items():
    surf,dist=meta[rk]; cell=surf+band(dist); kv=kmap.get(rk,"不明")
    for rule,p in pick(rr).items():
        for sc in ["ALL",cell,"K:"+kv,"CK:"+cell+"/"+kv,"Y:"+p["yr"],"CY:"+cell+"/"+p["yr"]]:
            add(agg[rule][sc],p)

print("== 先行軸ルール 全体（単複回収）==")
for r in rules: print(f"  {r}: {rep(agg[r]['ALL'])}")
print("\n== F2単騎逃 セル別(n>=100, 複回収降順) ==")
rows=[(k,a) for k,a in agg['F2_単騎逃'].items() if k[0] not in 'AKCY' and len(k)<=3 and a['n']>=100]
# select cell scopes (surf+band like 'ダ中')
cells=[(k,a) for k,a in agg['F2_単騎逃'].items() if k in ('芝短','芝マ','芝中','芝長','ダ短','ダマ','ダ中','ダ長') and a['n']>=80]
cells.sort(key=lambda x:-x[1]['fuk']/(x[1]['n']*100))
for k,a in cells: print(f"  {k}: {rep(a)}")
print("\n== F3単騎コ≤4 セル別 ==")
cells=[(k,a) for k,a in agg['F3_単騎コ≤4'].items() if k in ('芝短','芝マ','芝中','芝長','ダ短','ダマ','ダ中','ダ長') and a['n']>=60]
cells.sort(key=lambda x:-x[1]['tan']/(x[1]['n']*100))
for k,a in cells: print(f"  {k}: {rep(a)}")
print("\n== F4前×コ7+(前残り穴) セル別(単回収降順) ==")
cells=[(k,a) for k,a in agg['F4_前×コ7+'].items() if k in ('芝短','芝マ','芝中','芝長','ダ短','ダマ','ダ中','ダ長') and a['n']>=80]
cells.sort(key=lambda x:-x[1]['tan']/(x[1]['n']*100))
for k,a in cells: print(f"  {k}: {rep(a)}")
print("\n== F3単騎コ≤4 年別(全体・頑健性) ==")
for y in ['2023','2024','2025']:
    a=agg['F3_単騎コ≤4']['Y:'+y]
    if a['n']: print(f"  {y}: {rep(a)}")
print("\n== F3単騎コ≤4 有望セル×年別(単勝+EV頑健性) ==")
for cell in ['芝マ','芝中','ダ中']:
    print(f"  [{cell}]")
    for y in ['2023','2024','2025']:
        a=agg['F3_単騎コ≤4']['CY:'+cell+'/'+y]
        if a['n']: print(f"    {y}: {rep(a)}")
print("\n== F3単騎コ≤4 構成kousei別 ==")
for kv in ['1強','2強','3強','上位混戦','混戦警戒']:
    a=agg['F3_単騎コ≤4']['K:'+kv]
    if a['n']>=30: print(f"  {kv}: {rep(a)}")
