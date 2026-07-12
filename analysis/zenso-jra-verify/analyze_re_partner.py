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

# history feats (position + agari percentile)
raw=defaultdict(list);allrows=[]
with open(BASE+r"\history_feat.csv",encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        nm=(row.get("馬名") or "").strip()
        if not nm: continue
        try: d=pdate(row["開催日"])
        except: continue
        rec={"nm":nm,"d":d,"n":row.get("頭数"),"q4":relpos(row.get("四コーナー"),row.get("頭数")),"ag":fnum(row.get("上り3F"))}
        raw[(row["開催日"],row["開催場所"],row["レース番号"])].append(rec);allrows.append(rec)
for rk,rows in raw.items():
    v=[r for r in rows if r["ag"] and r["ag"]>0];m=len(v)
    if m>=2:
        v.sort(key=lambda r:r["ag"])
        for i,r in enumerate(v): r["agpct"]=i/(m-1)
    for r in rows: r.setdefault("agpct",None)
hist=defaultdict(list)
for r in allrows: hist[r["nm"]].append(r)
for nm in hist: hist[nm].sort(key=lambda x:x["d"])
def feats(nm,rd):
    runs=[r for r in hist.get(nm,[]) if r["d"]<rd][-3:]
    q4=[r["q4"] for r in runs if r["q4"] is not None]
    ag=[r["agpct"] for r in runs if r["agpct"] is not None]
    return (sum(q4)/len(q4) if q4 else None, sum(ag)/len(ag) if ag else None)

# kousei
compi=defaultdict(list)
with open(BASE+r"\コンピ指数.csv",encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        v=fnum(row["指数"]);
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
# wide payoffs
wide=defaultdict(dict)
with open(BASE+r"\wide.csv",encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        try: a,b=sorted(int(x) for x in row["組番"].split("-"))
        except: continue
        wide[(row["開催日"],row["開催場所"],row["レース番号"])][(a,b)]=fnum(row["金額"]) or 0
# race attr surface/band
def band(d):
    d=int(d);return "短" if d<=1200 else ("マ" if d<=1600 else ("中" if d<=2000 else "長"))

races=defaultdict(list); meta={}
def load(fn,surf):
    with open(fn,encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            rk=(row["開催日"],row["開催場所"],row["レース番号"])
            try: chaku=int(row["着順"]); u=int(row["馬番"])
            except: continue
            try: cr=int(row["指数順位"]) if row["指数順位"] else None
            except: cr=None
            pos,ag=feats(row["馬名"].strip(),pdate(row["開催日"]))
            races[rk].append({"u":u,"chaku":chaku,"cr":cr,"pos":pos,"ag":ag,"fuk":fnum(row["複勝"]) or 0})
            meta[rk]=(surf,row["距離"])
load(BASE+r"\target_turf.csv","芝"); load(BASE+r"\target_outcomes.csv","ダ")

def newA(): return {"n":0,"wn":0,"wret":0.0,"refuk":0.0,"rehit":0,"bwn":0,"bwret":0.0}
agg=defaultdict(newA)  # key=("cell"/"kousei"/"ALL", label)
def add(keys, wide_hit, wide_ret, refuk, rehit, bwn, bwret):
    for k in keys:
        a=agg[k]; a["n"]+=1; a["wn"]+=wide_hit; a["wret"]+=wide_ret
        a["refuk"]+=refuk; a["rehit"]+=rehit; a["bwn"]+=bwn; a["bwret"]+=bwret

for rk,rr in races.items():
    surf,dist=meta[rk]; cell=surf+band(dist); kv=kmap.get(rk,"不明")
    c1=next((r for r in rr if r["cr"]==1),None)
    c2=next((r for r in rr if r["cr"]==2),None)
    mids=[r for r in rr if r["pos"] is not None and 1/3<=r["pos"]<2/3 and r["ag"] is not None and r["cr"] and r["cr"]<=4]
    if not mids or c1 is None: continue
    re=min(mids,key=lambda r:r["ag"])
    if re["u"]==c1["u"]: continue  # RE must differ from コンピ1位 to be a partner
    wd=wide[rk]
    pair=tuple(sorted((c1["u"],re["u"])))
    w=wd.get(pair,0); wide_hit=1 if w>0 else 0
    # baseline: コンピ1位×コンピ2位
    bwn=0;bwret=0.0
    if c2 is not None and c2["u"]!=c1["u"]:
        bp=tuple(sorted((c1["u"],c2["u"]))); bw=wd.get(bp,0); bwn=1 if bw>0 else 0; bwret=bw
    rehit=1 if 1<=re["chaku"]<=3 else 0
    add([("ALL","RE"),("cell",cell),("kousei",kv),("cellk",cell+"/"+kv)], wide_hit, w, re["fuk"], rehit, bwn, bwret)

def rep(a):
    n=a["n"]
    if n==0: return "n=0"
    return (f"n={n:5d} ワイド的中{a['wn']/n:5.1%} ワイド回収{a['wret']/(n*100):6.1%} | RE複勝率{a['rehit']/n:5.1%} RE複回収{a['refuk']/(n*100):6.1%} "
            f"| 基準ワイド(コ1×コ2)回収{a['bwret']/(n*100):6.1%}")
print("== RE相手軸(軸コ1×相手RE) 全体 ==")
print("  "+rep(agg[("ALL","RE")]))
print("\n== 構成kousei別 ==")
for kv in ["1強","2強","3強","上位混戦","混戦警戒"]:
    k=("kousei",kv)
    if agg[k]["n"]>=50: print(f"  {kv}: {rep(agg[k])}")
print("\n== セル別(n>=150, ワイド回収降順) ==")
rows=[(k[1],a) for k,a in agg.items() if k[0]=="cell" and a["n"]>=150]
rows.sort(key=lambda x:-x[1]["wret"]/(x[1]["n"]*100))
for c,a in rows: print(f"  {c}: {rep(a)}")
print("\n== セル×混戦警戒(n>=60, ワイド回収降順) ==")
rows=[(k[1],a) for k,a in agg.items() if k[0]=="cellk" and k[1].endswith("混戦警戒") and a["n"]>=60]
rows.sort(key=lambda x:-x[1]["wret"]/(x[1]["n"]*100))
for c,a in rows: print(f"  {c}: {rep(a)}")
