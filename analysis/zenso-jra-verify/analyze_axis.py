import csv
from collections import defaultdict
from datetime import date

BASE=r"C:\jra\analysis\zenso-jra-verify\jra_csv"
def pdate(s):
    s=s.strip().split()[0].replace("/","-");y,m,d=s.split("-");return date(int(y),int(m),int(d))
def fnum(x):
    try:
        v=float(x); return v
    except: return None
def relpos(rank,n):
    r=fnum(rank);nn=fnum(n)
    if r is None or nn is None or nn<=1 or r<=0: return None
    return (r-1.0)/(nn-1.0)

# ---- history: per-race agari percentile, then per-horse chronological feats ----
raw=defaultdict(list)  # racekey -> list of dict rows
allrows=[]
with open(BASE+r"\history_feat.csv",encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        nm=(row.get("馬名") or "").strip()
        if not nm: continue
        try: d=pdate(row["開催日"])
        except: continue
        rk=(row["開催日"],row["開催場所"],row["レース番号"])
        rec={"nm":nm,"d":d,"rk":rk,"n":row.get("頭数"),"chaku":fnum(row.get("着順")),
             "q3":relpos(row.get("三コーナー"),row.get("頭数")),"q4":relpos(row.get("四コーナー"),row.get("頭数")),
             "ag":fnum(row.get("上り3F"))}
        raw[rk].append(rec); allrows.append(rec)
# agari percentile within race (small ag = fast = rank1)
for rk,rows in raw.items():
    valid=[r for r in rows if r["ag"] and r["ag"]>0]
    m=len(valid)
    if m>=2:
        valid.sort(key=lambda r:r["ag"])
        for i,r in enumerate(valid): r["agpct"]=i/(m-1)
    for r in rows:
        if "agpct" not in r: r["agpct"]=None
        r["frel"]=relpos(r["chaku"],r["n"])
hist=defaultdict(list)
for r in allrows: hist[r["nm"]].append(r)
for nm in hist: hist[nm].sort(key=lambda x:x["d"])

def feats(nm,rd):
    runs=[r for r in hist.get(nm,[]) if r["d"]<rd][-3:]
    if not runs: return None
    q4=[r["q4"] for r in runs if r["q4"] is not None]
    ag=[r["agpct"] for r in runs if r["agpct"] is not None]
    sus=[(1.0 if (r["frel"] is not None and r["q4"] is not None and r["frel"]<r["q4"]) else 0.0) for r in runs if r["frel"] is not None and r["q4"] is not None]
    pos=sum(q4)/len(q4) if q4 else None
    agari=sum(ag)/len(ag) if ag else None
    sustain=sum(sus)/len(sus) if sus else None
    return {"pos":pos,"agari":agari,"sustain":sustain}

def bucket(pos):
    if pos is None: return "不明"
    return "前" if pos<1/3 else ("中" if pos<2/3 else "後")

# ---- target races ----
def band(dist):
    d=int(dist)
    if d<=1200: return "短"
    if d<=1600: return "マ"
    if d<=2000: return "中"
    return "長"
races=defaultdict(list)   # racekey -> list of runner dict
surf_of={}; dist_of={}
def load(fn,surf_default):
    with open(fn,encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            rk=(row["開催日"],row["開催場所"],row["レース番号"])
            try: chaku=int(row["着順"])
            except: continue
            try: cr=int(row["指数順位"]) if row["指数順位"] else None
            except: cr=None
            rd=pdate(row["開催日"])
            fe=feats(row["馬名"].strip(),rd)
            races[rk].append({"nm":row["馬名"].strip(),"chaku":chaku,"cr":cr,"fe":fe,
                              "surf":surf_default,"dist":row["距離"],"venue":row["開催場所"]})
            surf_of[rk]=surf_default; dist_of[rk]=row["距離"]
load(BASE+r"\target_turf.csv","芝")
load(BASE+r"\target_outcomes.csv","ダ")

# kousei per race
import io,zipfile
compi=defaultdict(list)
with open(BASE+r"\コンピ指数.csv",encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        v=fnum(row["指数"])
        if v is None: continue
        compi[(row["開催日"],row["開催場所"],row["レース番号"])].append(v)
def kousei(vals):
    s=sorted(vals,reverse=True);n=len(s)
    if n<2: return "不明"
    idx1=s[0];range13=s[0]-s[2] if n>=3 else s[0]-s[1]
    danso=99
    for k in range(1,min(8,n)):
        if s[k-1]-s[k]>=10: danso=k;break
    kcont=sum(1 for v in s if v>=idx1-12)
    if idx1<=78 or range13<=6: return "混戦警戒"
    if danso==1 and kcont<=2: return "1強"
    if danso==1: return "1強-下割れ"
    if danso==2: return "2強"
    if danso==3: return "3強"
    return "上位混戦"
kmap={k:kousei(v) for k,v in compi.items()}

# ---- rules ----
def hit(ch): return 1 if 1<=ch<=3 else 0
def newA(): return {"n":0,"hit":0,"compi1n":0}
# cell = surf+band ; also track overall
agg=defaultdict(lambda: defaultdict(newA))   # rule -> cell -> {n,hit,compi1n}; plus baseline コンピ1位 on same firing races
base=defaultdict(lambda: defaultdict(newA))   # rule -> cell -> コンピ1位複勝(on firing races)

def pick_rules(runners):
    mids=[r for r in runners if r["fe"] and bucket(r["fe"]["pos"])=="中" and r["fe"]["agari"] is not None]
    out={}
    # 末脚メンバー1位(全体)
    cand=[r for r in runners if r["fe"] and r["fe"]["agari"] is not None]
    if cand:
        out["RA_末1"]=min(cand,key=lambda r:(r["fe"]["agari"],))
    if mids:
        out["RB_中末1"]=min(mids,key=lambda r:r["fe"]["agari"])
        sus=[r for r in mids if r["fe"]["sustain"] is not None and r["fe"]["sustain"]>=0.66]
        if sus: out["RC_中末1進"]=min(sus,key=lambda r:r["fe"]["agari"])
        hi=[r for r in mids if r["cr"] and 2<=r["cr"]<=4]
        if hi: out["RD_中末1コ2-4"]=min(hi,key=lambda r:r["fe"]["agari"])
        hi1=[r for r in mids if r["cr"] and r["cr"]<=4]
        if hi1: out["RE_中末1コ≤4"]=min(hi1,key=lambda r:r["fe"]["agari"])
    return out

aggk=defaultdict(lambda: defaultdict(newA)); basek=defaultdict(lambda: defaultdict(newA))  # rule->kousei
aggck=defaultdict(lambda: defaultdict(newA)); baseck=defaultdict(lambda: defaultdict(newA))  # rule->(cell,kousei)
for rk,runners in races.items():
    surf=surf_of[rk]; cell=surf+band(dist_of[rk]); kv=kmap.get(rk,"不明")
    compi1=next((r for r in runners if r["cr"]==1),None)
    picks=pick_rules(runners)
    for rule,p in picks.items():
        for c in (cell,"ALL"):
            a=agg[rule][c]; a["n"]+=1; a["hit"]+=hit(p["chaku"])
            if p["cr"]==1: a["compi1n"]+=1
            if compi1 is not None:
                b=base[rule][c]; b["n"]+=1; b["hit"]+=hit(compi1["chaku"])
        ak=aggk[rule][kv]; ak["n"]+=1; ak["hit"]+=hit(p["chaku"])
        if p["cr"]==1: ak["compi1n"]+=1
        if compi1 is not None:
            bk=basek[rule][kv]; bk["n"]+=1; bk["hit"]+=hit(compi1["chaku"])
        ck=(cell,kv)
        ac=aggck[rule][ck]; ac["n"]+=1; ac["hit"]+=hit(p["chaku"])
        if p["cr"]==1: ac["compi1n"]+=1
        if compi1 is not None:
            bc=baseck[rule][ck]; bc["n"]+=1; bc["hit"]+=hit(compi1["chaku"])

def rate(a): return a["hit"]/a["n"] if a["n"] else 0
print("== ルール別 複勝率(ALL) vs 同一発火レースのコンピ1位複勝率 ==")
for rule in ["RA_末1","RB_中末1","RC_中末1進","RD_中末1コ2-4","RE_中末1コ≤4"]:
    a=agg[rule]["ALL"]; b=base[rule]["ALL"]
    if a["n"]==0: continue
    print(f"  {rule}: n={a['n']:5d} 複勝率{rate(a):5.1%}  (同レースのコンピ1位{rate(b):5.1%}  差{rate(a)-rate(b):+.1%})  コ1採用率{a['compi1n']/a['n']:.0%}")
print("\n== セル別: 中団×末脚1位(RB) がコンピ1位を上回るセル(n>=80, 差降順) ==")
rows=[]
for c,a in agg["RB_中末1"].items():
    if c=="ALL" or a["n"]<80: continue
    b=base["RB_中末1"][c]; rows.append((c,a,b,rate(a)-rate(b)))
rows.sort(key=lambda x:-x[3])
for c,a,b,dd in rows:
    print(f"  {c}: RB複勝率{rate(a):5.1%}(n={a['n']}) vs コ1{rate(b):5.1%}  差{dd:+.1%}  コ1採用{a['compi1n']/a['n']:.0%}")
print("\n== 構成kousei別: RB/RE 複勝率 vs 同レースのコンピ1位（混戦で逆転するか）==")
for rule in ["RB_中末1","RE_中末1コ≤4"]:
    print(f"  [{rule}]")
    for kv in ["1強","2強","3強","上位混戦","混戦警戒"]:
        a=aggk[rule][kv]; b=basek[rule][kv]
        if a["n"]<50: continue
        print(f"    {kv}: 複勝率{rate(a):5.1%}(n={a['n']}) vs コ1{rate(b):5.1%}  差{rate(a)-rate(b):+.1%}  コ1採用{a['compi1n']/a['n']:.0%}")
print("\n== 混戦警戒 × セル別: REがコンピ1位を上回るか(n>=40, 差降順) ==")
rows=[]
for (cell,kv),a in aggck["RE_中末1コ≤4"].items():
    if kv!="混戦警戒" or a["n"]<40: continue
    b=baseck["RE_中末1コ≤4"][(cell,kv)]; rows.append((cell,a,b,rate(a)-rate(b)))
rows.sort(key=lambda x:-x[3])
for cell,a,b,dd in rows:
    print(f"  {cell}×混戦警戒: RE複勝率{rate(a):5.1%}(n={a['n']}) vs コ1{rate(b):5.1%}  差{dd:+.1%}")
