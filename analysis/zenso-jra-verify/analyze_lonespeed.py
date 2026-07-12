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

# history: per horse chronological runs with prev-style inputs + form
hist=defaultdict(list)
with open(BASE+r"\history_feat.csv",encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        nm=(row.get("馬名") or "").strip()
        if not nm: continue
        try: d=pdate(row["開催日"])
        except: continue
        n=fnum(row.get("頭数")); c4=fnum(row.get("四コーナー"))
        hist[nm].append({"d":d,"n":n,"c4":c4,"frel":rp(row.get("着順"),row.get("頭数"))})
for nm in hist: hist[nm].sort(key=lambda x:x["d"])

def prevstyle(nm,rd):
    runs=[r for r in hist.get(nm,[]) if r["d"]<rd]
    if not runs: return None
    r=runs[-1]
    if r["c4"] is None or r["n"] is None or r["n"]<=1 or r["c4"]<=0: return None
    rat=r["c4"]/r["n"]
    return "逃" if r["c4"]<=1 else ("先" if rat<=0.34 else ("差" if rat<=0.66 else "追"))
def formavg(nm,rd):
    runs=[r for r in hist.get(nm,[]) if r["d"]<rd][-3:]
    fr=[r["frel"] for r in runs if r["frel"] is not None]
    return sum(fr)/len(fr) if fr else None

def band(d):
    d=int(d);return "短" if d<=1200 else ("マ" if d<=1600 else ("中" if d<=2000 else "長"))
races=defaultdict(list);meta={}
def load(fn,surf):
    with open(fn,encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            rk=(row["開催日"],row["開催場所"],row["レース番号"])
            try: chaku=int(row["着順"])
            except: continue
            nm=row["馬名"].strip();rd=pdate(row["開催日"])
            races[rk].append({"nm":nm,"chaku":chaku,"comp":fnum(row.get("指数順位")),
                              "tou":fnum(row.get("頭数")),"ps":prevstyle(nm,rd),"form":formavg(nm,rd),
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

# identify 単騎速 per race = exactly 1 front-runner(逃/先)。地力先行=単騎速×コンピ上位(≤6)
lone=[]  # each = the lone-speed runner with attrs
for rk,rr in races.items():
    surf,dist=meta[rk]
    fronts=[r for r in rr if r["ps"] in ("逃","先")]
    if len(fronts)!=1: continue
    r=dict(fronts[0]); r["surf"]=surf; r["cell"]=surf+band(dist); r["dist"]=int(dist)
    lone.append(r)
print(f"単騎速 総数={len(lone)}  (コンピ有={sum(1 for r in lone if r['comp'] is not None)})")

def show(title,groups):
    print("\n== "+title+" ==")
    for label,pool in groups:
        a=newA()
        for r in pool: add(a,r)
        if a["n"]>=30: print(f"  {label:14s}: {rep(a)}")

# 全体・地力先行(コンピ≤6)
show("単騎速 全体 vs 地力先行(コンピ≤6)",[
    ("単騎速 全体",lone),
    ("地力先行 コンピ≤6",[r for r in lone if r["comp"] is not None and r["comp"]<=6]),
    ("参考 コンピ7+",[r for r in lone if r["comp"] is not None and r["comp"]>=7]),
])
# コンピ順位別
show("単騎速×コンピ順位",[
    ("コンピ1位",[r for r in lone if r["comp"]==1]),
    ("コンピ2-3位",[r for r in lone if r["comp"] in (2,3)]),
    ("コンピ4-6位",[r for r in lone if r["comp"] is not None and 4<=r["comp"]<=6]),
    ("コンピ7-9位",[r for r in lone if r["comp"] is not None and 7<=r["comp"]<=9]),
    ("コンピ10+位",[r for r in lone if r["comp"] is not None and r["comp"]>=10]),
])
L6=[r for r in lone if r["comp"] is not None and r["comp"]<=6]
# 頭数別(地力先行)
show("地力先行(コ≤6)×頭数",[
    ("少頭数≤10",[r for r in L6 if r["tou"] and r["tou"]<=10]),
    ("中11-13",[r for r in L6 if r["tou"] and 11<=r["tou"]<=13]),
    ("多頭数14+",[r for r in L6 if r["tou"] and r["tou"]>=14]),
])
# セル別(地力先行)
show("地力先行(コ≤6)×セル",[(c,[r for r in L6 if r["cell"]==c]) for c in ['芝短','芝マ','芝中','芝長','ダ短','ダマ','ダ中','ダ長']])
# 脚質別(逃 vs 先)
show("地力先行(コ≤6)×前走脚質",[
    ("前走=逃げ",[r for r in L6 if r["ps"]=="逃"]),
    ("前走=先行",[r for r in L6 if r["ps"]=="先"]),
])
# フォーム別(地力先行)
show("地力先行(コ≤6)×近走フォーム",[
    ("好走(form<0.33)",[r for r in L6 if r["form"] is not None and r["form"]<0.33]),
    ("凡走(form>=0.5)",[r for r in L6 if r["form"] is not None and r["form"]>=0.5]),
])
# 年別(地力先行)
show("地力先行(コ≤6)×年",[(y,[r for r in L6 if r["yr"]==y]) for y in ['2023','2024','2025']])
# 鉄板タグ根拠: 前走逃げ×コンピ≤3 の交差
tetsu=[r for r in lone if r["ps"]=="逃" and r["comp"] is not None and r["comp"]<=3]
show("鉄板候補: 単騎速×前走逃げ×コンピ≤3",[
    ("前走逃×コ≤3",tetsu),
    ("(参考)前走逃×コ全",[r for r in lone if r["ps"]=="逃"]),
    ("(参考)前走先×コ≤3",[r for r in lone if r["ps"]=="先" and r["comp"] is not None and r["comp"]<=3]),
])
for y in ['2023','2024','2025']:
    a=newA()
    for r in [x for x in tetsu if x["yr"]==y]: add(a,r)
    print(f"    鉄板 {y}: {rep(a)}")
# 鉄板ケースの開催日リスト(jra-card確認用) — race key を逆引き
print("\n== 鉄板ケース race-key(確認用・2025) ==")
for rk,rr in races.items():
    if rk[0][:4]!='2025': continue
    fronts=[r for r in rr if r["ps"] in ("逃","先")]
    if len(fronts)!=1: continue
    f=fronts[0]
    if f["ps"]=="逃" and f["comp"] is not None and f["comp"]<=3:
        print(f"  {rk[0]} {rk[1]} {rk[2]}R  馬={f['nm']} コ={int(f['comp'])} 着={f['chaku']}")
