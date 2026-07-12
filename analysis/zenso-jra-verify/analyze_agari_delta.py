import csv
from collections import defaultdict
from datetime import date
BASE=r"C:\jra\analysis\zenso-jra-verify\jra_csv"
def pdate(s):
    s=s.strip().split()[0].replace("/","-");y,m,d=s.split("-");return date(int(y),int(m),int(d))
def fnum(x):
    try: return float(x)
    except: return None
def rp(rank,n):
    r=fnum(rank);nn=fnum(n)
    if r is None or nn is None or nn<=1 or r<=0: return None
    return (r-1.0)/(nn-1.0)

# history: per run agari percentile within race + position(4corner rel)
raw=defaultdict(list);allrows=[]
with open(BASE+r"\history_feat.csv",encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        nm=(row.get("馬名") or "").strip()
        if not nm: continue
        try: d=pdate(row["開催日"])
        except: continue
        n=row.get("頭数")
        q4=rp(row.get("四コーナー"),n)
        if q4 is None: q4=rp(row.get("三コーナー"),n)
        rec={"nm":nm,"d":d,"pos":q4,"ag":fnum(row.get("上り3F")),"frel":rp(row.get("着順"),n)}
        raw[(row["開催日"],row["開催場所"],row["レース番号"])].append(rec);allrows.append(rec)
for rk,rows in raw.items():
    v=[r for r in rows if r["ag"] and r["ag"]>0];m=len(v)
    if m>=3:
        v.sort(key=lambda r:r["ag"])
        for i,r in enumerate(v): r["agpct"]=i/(m-1)
    for r in rows: r.setdefault("agpct",None)
hist=defaultdict(list)
for r in allrows: hist[r["nm"]].append(r)
for nm in hist: hist[nm].sort(key=lambda x:x["d"])

def feats(nm,rd):
    runs=[r for r in hist.get(nm,[]) if r["d"]<rd]
    if len(runs)<2: return None
    last3=runs[-3:]
    pv=[r["pos"] for r in last3 if r["pos"] is not None]
    posavg=sum(pv)/len(pv) if pv else None
    # 前走・前々走の上り3F percentile
    prev=runs[-1];prev2=runs[-2]
    a1=prev.get("agpct");a2=prev2.get("agpct")
    dlt=(a1-a2) if (a1 is not None and a2 is not None) else None
    return {"posavg":posavg,"ag_prev":a1,"ag_prev2":a2,"dag":dlt,
            "form":(sum(r["frel"] for r in last3 if r["frel"] is not None)/max(1,len([r for r in last3 if r["frel"] is not None])) if any(r["frel"] is not None for r in last3) else None)}

def band(d):
    d=int(d);return "短" if d<=1200 else ("マ" if d<=1600 else ("中" if d<=2000 else "長"))
races=defaultdict(list);meta={}
def load(fn,surf):
    with open(fn,encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            rk=(row["開催日"],row["開催場所"],row["レース番号"])
            try: chaku=int(row["着順"])
            except: continue
            races[rk].append({"chaku":chaku,"fe":feats(row["馬名"].strip(),pdate(row["開催日"])),
                              "tan":fnum(row["単勝"]) or 0,"fuk":fnum(row["複勝"]) or 0,"yr":row["開催日"][:4]})
            meta[rk]=(surf,row["距離"])
load(BASE+r"\target_turf.csv","芝"); load(BASE+r"\target_outcomes.csv","ダ")

def newA(): return {"n":0,"win":0,"hit":0,"tan":0.0,"fuk":0.0}
def add(a,r):
    a["n"]+=1
    if r["chaku"]==1:a["win"]+=1
    if 1<=r["chaku"]<=3:a["hit"]+=1
    a["tan"]+=r["tan"];a["fuk"]+=r["fuk"]
def rep(a):
    n=a["n"];return "n=0" if n==0 else f"n={n:5d} 勝率{a['win']/n:5.1%} 複勝率{a['hit']/n:5.1%} 単回{a['tan']/(n*100):6.1%} 複回{a['fuk']/(n*100):6.1%}"

def isMid(fe): return fe and fe["posavg"] is not None and 1/3<=fe["posavg"]<2/3
def dbucket(d):
    if d is None: return None
    if d<=-0.25: return "1_大幅良化"
    if d<=-0.05: return "2_良化"
    if d< 0.05: return "3_横ばい"
    if d< 0.25: return "4_悪化"
    return "5_大幅悪化"

# (A) 中団勢を上り3F Δ で層別（全馬・軸でなく該当馬全部）
aggA=defaultdict(lambda: defaultdict(newA))
for rk,rr in races.items():
    surf,dist=meta[rk];cell=surf+band(dist)
    for r in rr:
        if not isMid(r["fe"]): continue
        b=dbucket(r["fe"]["dag"])
        if b is None: continue
        for sc in ["ALL","Y:"+r["yr"],cell+"|"+b if False else "ALL2"]: pass
        add(aggA[b]["ALL"],r); add(aggA[b]["Y:"+r["yr"]],r); add(aggA[b][cell],r)
print("== 中団勢×上り3F順位Δ(前々走→前走) 全体 ==")
for b in sorted(aggA):
    print(f"  {b}: {rep(aggA[b]['ALL'])}")
print("\n== 大幅良化・良化 の年別 ==")
for b in ["1_大幅良化","2_良化"]:
    print(f"  [{b}]")
    for y in ['2023','2024','2025']:
        a=aggA[b]['Y:'+y]
        if a['n']: print(f"    {y}: {rep(a)}")
print("\n== 大幅良化 のセル別 ==")
for c in ['芝短','芝マ','芝中','芝長','ダ中','ダ長']:
    a=aggA["1_大幅良化"][c]
    if a['n']>=40: print(f"    {c}: {rep(a)}")
# 芝マ大幅良化の年別(価値ポケット頑健性)
aggAM=defaultdict(newA)
for rk,rr in races.items():
    surf,dist=meta[rk];cell=surf+band(dist)
    if cell!="芝マ": continue
    for r in rr:
        if isMid(r["fe"]) and dbucket(r["fe"]["dag"])=="1_大幅良化": add(aggAM["Y:"+r["yr"]],r)
print("  芝マ大幅良化 年別:")
for y in ['2023','2024','2025']:
    if aggAM['Y:'+y]['n']: print(f"    {y}: {rep(aggAM['Y:'+y])}")
# 消しシグナル: 大幅悪化の年別
print("  大幅悪化(消し) 年別:")
for y in ['2023','2024','2025']:
    if aggA['5_大幅悪化']['Y:'+y]['n']: print(f"    {y}: {rep(aggA['5_大幅悪化']['Y:'+y])}")

# (B) 軸ルール: 各レースで中団勢のうち上り3FΔ最小(最も良化)を1頭選ぶ
aggB=defaultdict(newA)
for rk,rr in races.items():
    surf,dist=meta[rk];cell=surf+band(dist)
    mids=[r for r in rr if isMid(r["fe"]) and r["fe"]["dag"] is not None]
    if not mids: continue
    p=min(mids,key=lambda r:r["fe"]["dag"])
    for sc in ["ALL","Y:"+p["yr"],cell]: add(aggB[sc],p)
print("\n== 軸ルール: 中団勢×上り3FΔ最小(最良化) を1頭 ==")
print(f"  全体: {rep(aggB['ALL'])}")
for y in ['2023','2024','2025']:
    if aggB['Y:'+y]['n']: print(f"    {y}: {rep(aggB['Y:'+y])}")
for c in ['芝短','芝マ','芝中','芝長','ダ中','ダ長']:
    if aggB[c]['n']>=40: print(f"    {c}: {rep(aggB[c])}")

# (C) 良化かつ好走(着順)良い中団を軸に
aggC=defaultdict(newA)
for rk,rr in races.items():
    surf,dist=meta[rk];cell=surf+band(dist)
    mids=[r for r in rr if isMid(r["fe"]) and r["fe"]["dag"] is not None and r["fe"]["dag"]<=-0.05 and r["fe"]["form"] is not None]
    if not mids: continue
    p=min(mids,key=lambda r:r["fe"]["form"])
    for sc in ["ALL","Y:"+p["yr"],cell]: add(aggC[sc],p)
print("\n== 軸ルール: 中団×良化(Δ≤-0.05)×好走(着順)最良 ==")
print(f"  全体: {rep(aggC['ALL'])}")
for y in ['2023','2024','2025']:
    if aggC['Y:'+y]['n']: print(f"    {y}: {rep(aggC['Y:'+y])}")
for c in ['芝短','芝マ','芝中','芝長','ダ中','ダ長']:
    if aggC[c]['n']>=40: print(f"    {c}: {rep(aggC[c])}")
# 芝長 C の年別(複回101%ポケット頑健性)
aggCL=defaultdict(newA)
for rk,rr in races.items():
    surf,dist=meta[rk];cell=surf+band(dist)
    if cell!="芝長": continue
    mids=[r for r in rr if isMid(r["fe"]) and r["fe"]["dag"] is not None and r["fe"]["dag"]<=-0.05 and r["fe"]["form"] is not None]
    if not mids: continue
    p=min(mids,key=lambda r:r["fe"]["form"])
    add(aggCL["Y:"+p["yr"]],p)
print("  芝長×良化×好走 年別:")
for y in ['2023','2024','2025']:
    if aggCL['Y:'+y]['n']: print(f"    {y}: {rep(aggCL['Y:'+y])}")
