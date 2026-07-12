import csv, io, zipfile
from collections import defaultdict
from datetime import date

HIST_ZIP = r"C:\jra\analysis\zenso-jra-verify\jra_input.zip"
TARGET = r"C:\jra\analysis\zenso-jra-verify\jra_csv\target_turf.csv"

def pdate(s):
    s=s.strip().split()[0].replace("/","-"); y,m,d=s.split("-"); return date(int(y),int(m),int(d))
def relpos(rank,n):
    try: r=float(rank); nn=float(n)
    except: return None
    if r<=0 or nn<=1: return None
    return (r-1.0)/(nn-1.0)

hist=defaultdict(list)
with zipfile.ZipFile(HIST_ZIP) as zf:
    with zf.open("vw_競走結果統合.csv") as raw:
        for row in csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")):
            nm=(row.get("馬名") or "").strip()
            if not nm: continue
            try: d=pdate(row["開催日"])
            except: continue
            n=row.get("頭数"); q4=relpos(row.get("四コーナー"),n)
            hist[nm].append((d,q4))
for nm in hist: hist[nm].sort()

def prev_avg(nm,rd,k=3):
    runs=[x for x in hist.get(nm,[]) if x[0]<rd][-k:]
    q4s=[x[1] for x in runs if x[1] is not None]
    return (sum(q4s)/len(q4s) if q4s else None)
def bucket(a):
    if a is None: return "不明"
    return "前" if a<1/3 else ("中" if a<2/3 else "後")
def band(dist):
    d=int(dist)
    if d<=1200: return "短1000-1200"
    if d<=1600: return "マ1300-1600"
    if d<=2000: return "中1700-2000"
    if d<=2400: return "中長2100-2400"
    return "長2500+"
def newA(): return {"n":0,"win":0,"hit":0,"tan":0.0,"fuk":0.0}
def add(a,c,t,f):
    a["n"]+=1;
    if c==1:a["win"]+=1
    if 1<=c<=3:a["hit"]+=1
    a["tan"]+=t;a["fuk"]+=f
def rep(a):
    n=a["n"]
    return "n=0" if n==0 else f"n={n:5d} 複勝率{a['hit']/n:5.1%} 単回収{a['tan']/(n*100):6.1%} 複回収{a['fuk']/(n*100):6.1%}"

by_bkt=defaultdict(newA); by_band_bkt=defaultdict(newA); by_turn_bkt=defaultdict(newA)
by_bkt_yr=defaultdict(newA); by_compi=defaultdict(newA); by_cell_mid=defaultdict(newA)
win_band=defaultdict(lambda: defaultdict(int)); fld_band=defaultdict(lambda: defaultdict(int))
with open(TARGET,encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        nm=row["馬名"].strip()
        try: rd=pdate(row["開催日"]); chaku=int(row["着順"])
        except: continue
        dist=row["距離"]; venue=row["開催場所"]; yr=row["開催日"][:4]; turn=(row.get("周回方向") or "").strip() or "?"
        tan=float(row["単勝"]) if row["単勝"] else 0.0
        fuk=float(row["複勝"]) if row["複勝"] else 0.0
        try: cr=int(row["指数順位"]) if row["指数順位"] else None
        except: cr=None
        b=bucket(prev_avg(nm,rd))
        if b=="不明": continue
        bd=band(dist)
        fld_band[bd][b]+=1
        if chaku==1: win_band[bd][b]+=1
        add(by_bkt[b],chaku,tan,fuk)
        add(by_band_bkt[(bd,b)],chaku,tan,fuk)
        add(by_turn_bkt[(turn,b)],chaku,tan,fuk)
        if b=="中": add(by_bkt_yr[yr],chaku,tan,fuk)
        cband="コ1-3" if (cr and cr<=3) else ("コ4-6" if (cr and cr<=6) else "コ7+/無")
        add(by_compi[(cband,b)],chaku,tan,fuk)
        if b=="中": add(by_cell_mid[f"{venue}{dist}"],chaku,tan,fuk)

print("== 前提検証: 距離帯別 勝ち馬/全体比(中団) ==")
for bd in ["短1000-1200","マ1300-1600","中1700-2000","中長2100-2400","長2500+"]:
    ft=sum(fld_band[bd].values()); wt=sum(win_band[bd].values())
    if ft==0: continue
    def rt(b):
        fb=fld_band[bd][b]/ft if ft else 0; wb=win_band[bd][b]/wt if wt else 0
        return (wb/fb) if fb>0 else 0
    print(f"  {bd}: 前{rt('前'):.2f} 中{rt('中'):.2f} 後{rt('後'):.2f}  (勝ち馬/全体比)")
print("\n== 位置別（芝全体） ==")
for b in ["前","中","後"]: print(f"  {b}: {rep(by_bkt[b])}")
print("\n== 距離帯 × 位置 ==")
for bd in ["短1000-1200","マ1300-1600","中1700-2000","中長2100-2400","長2500+"]:
    print(f"  {bd}: 前{rep(by_band_bkt[(bd,'前')])} | 中{rep(by_band_bkt[(bd,'中')])} | 後{rep(by_band_bkt[(bd,'後')])}")
print("\n== 回り × 位置 ==")
for tn in sorted({k[0] for k in by_turn_bkt}):
    print(f"  {tn}: 前{rep(by_turn_bkt[(tn,'前')])} | 中{rep(by_turn_bkt[(tn,'中')])} | 後{rep(by_turn_bkt[(tn,'後')])}")
print("\n== 年別（中団） ==")
for yr in sorted(by_bkt_yr): print(f"  {yr}: {rep(by_bkt_yr[yr])}")
print("\n== コンピ帯 × 位置 ==")
for cb in ["コ1-3","コ4-6","コ7+/無"]:
    print(f"  {cb}: 前{rep(by_compi[(cb,'前')])} | 中{rep(by_compi[(cb,'中')])} | 後{rep(by_compi[(cb,'後')])}")
print("\n== 中団が強いセル(n>=150, 複回収降順 top15) ==")
rows=[(c,a) for c,a in by_cell_mid.items() if a["n"]>=150]
rows.sort(key=lambda x:-x[1]["fuk"]/(x[1]["n"]*100))
for c,a in rows[:15]: print(f"  {c}: {rep(a)}")
