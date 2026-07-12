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

# history: per run features + per-race agari percentile
raw=defaultdict(list);allrows=[]
with open(BASE+r"\history_feat.csv",encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        nm=(row.get("馬名") or "").strip()
        if not nm: continue
        try: d=pdate(row["開催日"])
        except: continue
        n=row.get("頭数")
        e=rp(row.get("一コーナー"),n)
        if e is None: e=rp(row.get("二コーナー"),n)
        rec={"nm":nm,"d":d,"e":e,"q4":rp(row.get("四コーナー"),n),
             "frel":rp(row.get("着順"),n),"ag":fnum(row.get("上り3F"))}
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
    if not runs: return None
    def m(key):
        v=[r[key] for r in runs if r[key] is not None]
        return sum(v)/len(v) if v else None
    fr=[r["frel"] for r in runs if r["frel"] is not None]
    return {"form":m("frel"),"formbest":(min(fr) if fr else None),
            "ag":m("agpct"),"early":m("e"),"pos":m("q4"),"nr":len(runs)}

def band(d):
    d=int(d);return "短" if d<=1200 else ("マ" if d<=1600 else ("中" if d<=2000 else "長"))
races=defaultdict(list);meta={}
def load(fn,surf):
    with open(fn,encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            rk=(row["開催日"],row["開催場所"],row["レース番号"])
            try: chaku=int(row["着順"])
            except: continue
            fe=feats(row["馬名"].strip(),pdate(row["開催日"]))
            races[rk].append({"chaku":chaku,"fe":fe,"tan":fnum(row["単勝"]) or 0,"fuk":fnum(row["複勝"]) or 0,"yr":row["開催日"][:4]})
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

def gval(r,k): return r["fe"][k] if r["fe"] and r["fe"][k] is not None else None
def pick(rr):
    ok=[r for r in rr if r["fe"] and r["fe"]["nr"]>=1]
    out={}
    def mn(pool,key):
        c=[r for r in pool if gval(r,key) is not None]
        return min(c,key=lambda r:r["fe"][key]) if c else None
    if ok:
        out["好走(着順)"]=mn(ok,"form")
        out["末脚1位"]=mn(ok,"ag")
        out["最前(先行)"]=mn(ok,"early")
        fronts=[r for r in ok if gval(r,"early") is not None and r["fe"]["early"]<0.25]
        if len(fronts)==1: out["単騎逃げ"]=fronts[0]
        if fronts: out["好走×先行"]=mn(fronts,"form")
        mids=[r for r in ok if gval(r,"pos") is not None and 1/3<=r["fe"]["pos"]<2/3]
        if mids: out["中団×末脚"]=mn(mids,"ag")
        goodform=[r for r in ok if gval(r,"form") is not None and r["fe"]["form"]<0.33]
        if goodform: out["好走×末脚1位"]=mn(goodform,"ag")
        # 好走×単騎逃げ
        if len(fronts)==1 and gval(fronts[0],"form") is not None and fronts[0]["fe"]["form"]<0.40:
            out["好走×単騎逃"]=fronts[0]
    return out
rules=["好走(着順)","末脚1位","最前(先行)","単騎逃げ","好走×先行","中団×末脚","好走×末脚1位","好走×単騎逃"]
agg=defaultdict(lambda: defaultdict(newA))
for rk,rr in races.items():
    surf,dist=meta[rk];cell=surf+band(dist)
    for rule,p in pick(rr).items():
        if p is None: continue
        for sc in ["ALL",cell,"Y:"+p["yr"]]: add(agg[rule][sc],p)
print("== ファクトのみ 軸ルール 全体（複勝率降順）==")
for r in sorted(rules,key=lambda r:-(agg[r]['ALL']['hit']/agg[r]['ALL']['n'] if agg[r]['ALL']['n'] else 0)):
    print(f"  {r:12s}: {rep(agg[r]['ALL'])}")
print("\n== トップ2ルールのセル別 ==")
for r in ["好走(着順)","好走×単騎逃"]:
    print(f"  [{r}]")
    for c in ['芝短','芝マ','芝中','芝長','ダ中','ダ長']:
        a=agg[r][c]
        if a['n']>=60: print(f"    {c}: {rep(a)}")
print("\n== トップ2ルール 年別 ==")
for r in ["好走(着順)","好走×単騎逃"]:
    print(f"  [{r}]")
    for y in ['2023','2024','2025']:
        a=agg[r]['Y:'+y]
        if a['n']: print(f"    {y}: {rep(a)}")
