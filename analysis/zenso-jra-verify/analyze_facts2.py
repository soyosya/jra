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

# read history, build speed cohorts
rows=[]
cohort=defaultdict(list)  # (venue,dist,surf,going)->list of times
with open(BASE+r"\history_feat.csv",encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        nm=(row.get("馬名") or "").strip()
        if not nm: continue
        try: d=pdate(row["開催日"])
        except: continue
        n=row.get("頭数")
        t=fnum(row.get("走破時計"))
        rec={"nm":nm,"d":d,"n":n,
             "frel":rp(row.get("着順"),n),
             "gap":fnum(row.get("一着馬着差タイム")) or (0.0 if fnum(row.get("着順"))==1 else None),
             "t":t,"ck":(row["開催場所"],row["距離"],row.get("コース種別"),row.get("馬場"))}
        rows.append(rec)
        if t and t>0: cohort[rec["ck"]].append(t)
# speed percentile per run within cohort (fast=low time -> low pct = good)
coh_sorted={k:sorted(v) for k,v in cohort.items() if len(v)>=10}
import bisect
for r in rows:
    t=r["t"]; sp=None
    if t and t>0 and r["ck"] in coh_sorted:
        arr=coh_sorted[r["ck"]]; i=bisect.bisect_left(arr,t); sp=i/(len(arr)-1) if len(arr)>1 else None
    r["sp"]=sp
hist=defaultdict(list)
for r in rows: hist[r["nm"]].append(r)
for nm in hist: hist[nm].sort(key=lambda x:x["d"])

def feats(nm,rd):
    runs=[r for r in hist.get(nm,[]) if r["d"]<rd][-3:]
    if not runs: return None
    fr=[r["frel"] for r in runs if r["frel"] is not None]
    gp=[r["gap"] for r in runs if r["gap"] is not None]
    sp=[r["sp"] for r in runs if r["sp"] is not None]
    # recency weighted finish (last heaviest)
    wf=None
    if fr:
        w=list(range(1,len(runs)+1))  # older->newer small->large? runs sorted asc by date, last is newest
        pairs=[(i+1,r["frel"]) for i,r in enumerate(runs) if r["frel"] is not None]
        sw=sum(i for i,_ in pairs); wf=sum(i*v for i,v in pairs)/sw if sw else None
    return {"form":(sum(fr)/len(fr) if fr else None),
            "formbest":(min(fr) if fr else None),
            "formw":wf,
            "last":(runs[-1]["frel"]),
            "gap":(sum(gp)/len(gp) if gp else None),
            "sp":(sum(sp)/len(sp) if sp else None),
            "spbest":(min(sp) if sp else None),
            "nr":len(runs)}

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

keys={"好走avg":"form","好走best":"formbest","好走重み":"formw","前走着":"last","着差":"gap","速度avg":"sp","速度best":"spbest"}
agg=defaultdict(lambda: defaultdict(newA))
for rk,rr in races.items():
    surf,dist=meta[rk];cell=surf+band(dist)
    for label,key in keys.items():
        cand=[r for r in rr if r["fe"] and r["fe"].get(key) is not None]
        if not cand: continue
        p=min(cand,key=lambda r:r["fe"][key])
        for sc in ["ALL",cell,"Y:"+p["yr"]]: add(agg[label][sc],p)
print("== 能力ファクト別 軸ルール 全体（複勝率降順）==")
for label in sorted(keys,key=lambda l:-(agg[l]['ALL']['hit']/agg[l]['ALL']['n'] if agg[l]['ALL']['n'] else 0)):
    print(f"  {label:8s}: {rep(agg[label]['ALL'])}")
print("\n== 上位3ルール 年別 ==")
top=sorted(keys,key=lambda l:-(agg[l]['ALL']['hit']/agg[l]['ALL']['n'] if agg[l]['ALL']['n'] else 0))[:3]
for label in top:
    print(f"  [{label}]")
    for y in ['2023','2024','2025']:
        a=agg[label]['Y:'+y]
        if a['n']: print(f"    {y}: {rep(a)}")
print("\n== 好走best(回収型) 年別 ==")
for y in ['2023','2024','2025']:
    a=agg['好走best']['Y:'+y]
    if a['n']: print(f"  {y}: {rep(a)}")
print("\n== セル別: 好走avg(確度) と 好走best(回収) ==")
for c in ['芝短','芝マ','芝中','芝長','ダ中','ダ長']:
    print(f"  [{c}] avg:{rep(agg['好走avg'][c])}")
    print(f"       best:{rep(agg['好走best'][c])}")
print("\n== 好走best 長距離×年別(＋EV頑健性) ==")
# need cell×year for 好走best: recompute quickly via stored? re-aggregate

