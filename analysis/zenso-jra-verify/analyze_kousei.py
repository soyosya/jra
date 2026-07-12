import csv, io, zipfile
from collections import defaultdict
from datetime import date

BASE=r"C:\jra\analysis\zenso-jra-verify"
HIST_ZIP=BASE+r"\jra_input.zip"

def pdate(s):
    s=s.strip().split()[0].replace("/","-"); y,m,d=s.split("-"); return date(int(y),int(m),int(d))
def relpos(rank,n):
    try: r=float(rank); nn=float(n)
    except: return None
    if r<=0 or nn<=1: return None
    return (r-1.0)/(nn-1.0)

# history -> position bucket
hist=defaultdict(list)
with zipfile.ZipFile(HIST_ZIP) as zf:
    with zf.open("vw_競走結果統合.csv") as raw:
        for row in csv.DictReader(io.TextIOWrapper(raw,encoding="utf-8-sig",newline="")):
            nm=(row.get("馬名") or "").strip()
            if not nm: continue
            try: d=pdate(row["開催日"])
            except: continue
            q4=relpos(row.get("四コーナー"),row.get("頭数"))
            hist[nm].append((d,q4))
for nm in hist: hist[nm].sort()
def bkt(nm,rd):
    runs=[x for x in hist.get(nm,[]) if x[0]<rd][-3:]
    q=[x[1] for x in runs if x[1] is not None]
    if not q: return "不明"
    a=sum(q)/len(q); return "前" if a<1/3 else ("中" if a<2/3 else "後")

# kousei per race from compi
compi=defaultdict(list)
with zipfile.ZipFile(HIST_ZIP) as zf:  # コンピ指数.csv is inside jra_input? no. read from jra_csv
    pass
with open(BASE+r"\jra_csv\コンピ指数.csv",encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        try: idx=float(row["指数"])
        except: continue
        k=(row["開催日"],row["開催場所"],row["レース番号"]); compi[k].append(idx)
def kousei(vals):
    s=sorted(vals,reverse=True); n=len(s)
    if n<2: return "不明"
    idx1=s[0]; g12=s[0]-s[1]; range13=s[0]-s[2] if n>=3 else g12
    danso=99
    for k in range(1,min(8,n)):
        if s[k-1]-s[k]>=10: danso=k; break
    kcont=sum(1 for v in s if v>=idx1-12)
    if idx1<=78 or range13<=6: return "混戦警戒"
    if danso==1 and kcont<=2: return "1強"
    if danso==1: return "1強-下割れ"
    if danso==2: return "2強"
    if danso==3: return "3強"
    return "上位混戦"
kmap={k:kousei(v) for k,v in compi.items()}

# race attr -> 番組
def parse_ban(joken):
    j=joken or ""
    if "2歳" in j: age="2歳"
    elif "3歳以上" in j: age="3歳上"
    elif "4歳以上" in j: age="4歳上"
    elif "3歳" in j: age="3歳"
    else: age="他"
    if "新馬" in j: cls="新馬"
    elif "未勝利" in j: cls="未勝利"
    elif "1勝" in j: cls="1勝"
    elif "2勝" in j: cls="2勝"
    elif "3勝" in j: cls="3勝"
    elif "オープン" in j: cls="OP"
    else: cls="他"
    return age,cls
attr={}
with open(BASE+r"\jra_csv\race_attr.csv",encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        k=(row["開催日"],row["開催場所"],row["レース番号"])
        attr[k]=(row["コース種別"],parse_ban(row["条件"]))

def newA(): return {"n":0,"hit":0,"fuk":0.0,"tan":0.0}
def add(a,c,t,f):
    a["n"]+=1
    if 1<=c<=3:a["hit"]+=1
    a["tan"]+=t;a["fuk"]+=f
def rep(a):
    n=a["n"]; return "n=0" if n==0 else f"n={n:5d} 複勝率{a['hit']/n:5.1%} 単回収{a['tan']/(n*100):6.1%} 複回収{a['fuk']/(n*100):6.1%}"

mid_by_kousei=defaultdict(lambda: defaultdict(newA))  # surface -> kousei -> agg  (mid only)
mid_by_age=defaultdict(lambda: defaultdict(newA))
mid_by_cls=defaultdict(lambda: defaultdict(newA))
compi1_by_kousei=defaultdict(newA)  # validation: compi1位 複勝率 by kousei (all surfaces)

def process(fn):
    with open(fn,encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            k=(row["開催日"],row["開催場所"],row["レース番号"])
            surf=attr.get(k,("?",("他","他")))[0]
            age,cls=attr.get(k,("?",("他","他")))[1]
            try: chaku=int(row["着順"])
            except: continue
            tan=float(row["単勝"]) if row["単勝"] else 0.0
            fuk=float(row["複勝"]) if row["複勝"] else 0.0
            kv=kmap.get(k,"不明")
            try: cr=int(row["指数順位"]) if row["指数順位"] else None
            except: cr=None
            if cr==1: add(compi1_by_kousei[kv],chaku,tan,fuk)
            b=bkt(row["馬名"].strip(),pdate(row["開催日"]))
            if b!="中": continue
            add(mid_by_kousei[surf][kv],chaku,tan,fuk)
            add(mid_by_age[surf][age],chaku,tan,fuk)
            add(mid_by_cls[surf][cls],chaku,tan,fuk)
process(BASE+r"\jra_csv\target_turf.csv")
process(BASE+r"\jra_csv\target_outcomes.csv")

print("== 検証: コンピ1位軸の複勝率が構成kousei順に単調か(JRAでkousei有効か・全種別) ==")
for kv in ["1強","1強-下割れ","2強","3強","上位混戦","混戦警戒"]:
    print(f"  {kv}: {rep(compi1_by_kousei[kv])}")
for surf in ["芝","ダ"]:
    print(f"\n== [{surf}] 中団勢 × 構成kousei ==")
    for kv in ["1強","1強-下割れ","2強","3強","上位混戦","混戦警戒"]:
        print(f"  {kv}: {rep(mid_by_kousei[surf][kv])}")
    print(f"== [{surf}] 中団勢 × 番組(年齢) ==")
    for a in ["2歳","3歳","3歳上","4歳上"]:
        print(f"  {a}: {rep(mid_by_age[surf][a])}")
    print(f"== [{surf}] 中団勢 × 番組(クラス) ==")
    for c in ["新馬","未勝利","1勝","2勝","3勝","OP"]:
        print(f"  {c}: {rep(mid_by_cls[surf][c])}")
