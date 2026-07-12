import csv, io, zipfile
from collections import defaultdict
from datetime import date

HIST_ZIP = r"C:\jra\analysis\zenso-jra-verify\jra_input.zip"
TARGET = r"C:\jra\analysis\zenso-jra-verify\jra_csv\target_outcomes.csv"

def pdate(s):
    s=s.strip().split()[0].replace("/","-"); y,m,d=s.split("-"); return date(int(y),int(m),int(d))
def relpos(rank, n):
    try: r=float(rank); nn=float(n)
    except: return None
    if r<=0 or nn<=1: return None
    return (r-1.0)/(nn-1.0)

# history per 馬名: list of (date, q4, q3)
hist=defaultdict(list)
with zipfile.ZipFile(HIST_ZIP) as zf:
    with zf.open("vw_競走結果統合.csv") as raw:
        for row in csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")):
            nm=(row.get("馬名") or "").strip()
            if not nm: continue
            try: d=pdate(row["開催日"])
            except: continue
            n=row.get("頭数"); q4=relpos(row.get("四コーナー"),n); q3=relpos(row.get("三コーナー"),n)
            hist[nm].append((d,q4,q3))
for nm in hist: hist[nm].sort()

def prev_avg(nm, raceday, k=3):
    runs=[x for x in hist.get(nm,[]) if x[0]<raceday]
    runs=runs[-k:] if len(runs)>k else runs
    q4s=[x[1] for x in runs if x[1] is not None]
    q3s=[x[2] for x in runs if x[2] is not None]
    a4=sum(q4s)/len(q4s) if q4s else None
    a3=sum(q3s)/len(q3s) if q3s else None
    return a4,a3,len(runs)

def bucket(a):
    if a is None: return "不明"
    if a<1/3: return "前"
    if a<2/3: return "中"
    return "後"

# aggregate helper
def newA(): return {"n":0,"win":0,"hit":0,"tan":0.0,"fuk":0.0}
def add(a,chaku,tan,fuk):
    a["n"]+=1
    if chaku==1: a["win"]+=1
    if 1<=chaku<=3: a["hit"]+=1   # 参考上位3着（複勝は実払戻で回収計上）
    a["tan"]+=tan; a["fuk"]+=fuk
def rep(a):
    n=a["n"];
    if n==0: return "n=0"
    return f"n={n:5d} 複勝率{a['hit']/n:5.1%} 単回収{a['tan']/(n*100):6.1%} 複回収{a['fuk']/(n*100):6.1%}"

by_bkt=defaultdict(newA); by_bkt_dist=defaultdict(newA); by_bkt_yr=defaultdict(newA)
by_bkt_compi=defaultdict(newA); by_cell_mid=defaultdict(newA)
winner_bkt=defaultdict(int); field_bkt=defaultdict(int)
tot=0; used=0
with open(TARGET, encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        tot+=1
        nm=row["馬名"].strip();
        try: rd=pdate(row["開催日"])
        except: continue
        try: chaku=int(row["着順"])
        except: continue
        dist=row["距離"]; venue=row["開催場所"]; yr=row["開催日"][:4]
        tan=float(row["単勝"]) if row["単勝"] else 0.0
        fuk=float(row["複勝"]) if row["複勝"] else 0.0
        try: cr=int(row["指数順位"]) if row["指数順位"] else None
        except: cr=None
        a4,a3,nruns=prev_avg(nm,rd)
        b=bucket(a4)
        if b=="不明":
            continue
        used+=1
        field_bkt[b]+=1
        if chaku==1: winner_bkt[b]+=1
        add(by_bkt[b],chaku,tan,fuk)
        add(by_bkt_dist[(dist,b)],chaku,tan,fuk)
        add(by_bkt_yr[(yr,b)],chaku,tan,fuk)
        cband = "コ1-3" if (cr and cr<=3) else ("コ4-6" if (cr and cr<=6) else "コ7+/無")
        add(by_bkt_compi[(cband,b)],chaku,tan,fuk)
        if b=="中": add(by_cell_mid[f"{venue}{dist}"],chaku,tan,fuk)

print(f"総出走={tot} 位置判定可={used}")
print("\n== 前提検証: 勝ち馬と全出走の近走位置分布 ==")
wt=sum(winner_bkt.values()); ft=sum(field_bkt.values())
for b in ["前","中","後"]:
    print(f"  {b}: 全体{field_bkt[b]/ft:5.1%}  勝ち馬{winner_bkt[b]/wt:5.1%}  (勝ち馬/全体比 {(winner_bkt[b]/wt)/(field_bkt[b]/ft):.2f})")
print("\n== 位置バケット別（中距離ダ全体・実払戻回収） ==")
for b in ["前","中","後"]: print(f"  {b}: {rep(by_bkt[b])}")
print("\n== 距離別 ==")
for dist in sorted({k[0] for k in by_bkt_dist}, key=lambda x:int(x)):
    line=f"  ダ{dist}: "
    for b in ["前","中","後"]: line+=f"[{b}]{rep(by_bkt_dist[(dist,b)])}  "
    print(line)
print("\n== 年別（中団のみ） ==")
for yr in sorted({k[0] for k in by_bkt_yr}):
    print(f"  {yr} 中: {rep(by_bkt_yr[(yr,'中')])}")
print("\n== コンピ順位帯 × 位置（中団が市場に上乗せするか） ==")
for cb in ["コ1-3","コ4-6","コ7+/無"]:
    print(f"  {cb}: 前{rep(by_bkt_compi[(cb,'前')])} | 中{rep(by_bkt_compi[(cb,'中')])} | 後{rep(by_bkt_compi[(cb,'後')])}")
print("\n== 中団が強いセル(venue×dist, n>=150, 複回収降順 top12) ==")
rows=[(c,a) for c,a in by_cell_mid.items() if a["n"]>=150]
rows.sort(key=lambda x:-x[1]["fuk"]/(x[1]["n"]*100))
for c,a in rows[:12]: print(f"  {c}: {rep(a)}")
