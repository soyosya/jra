# -*- coding: utf-8 -*-
import json
from collections import defaultdict

recs=json.load(open('records_all.json'))
# タグ: h2h順位∈{1,2} かつ コンピ順位>=4
def tagged(r): return r['crank'] is not None and r['hrank'] in (1,2) and r['crank']>=4

def agg(rs):
    n=len(rs)
    if n==0: return dict(n=0)
    w=sum(r['win'] for r in rs); p=sum(r['place'] for r in rs)
    tr=sum(r['tret'] for r in rs); fr=sum(r['fret'] for r in rs)
    return dict(n=n, win=100*w/n, plc=100*p/n, tROI=100*tr/n, fROI=100*fr/n)

def line(lbl, rs):
    a=agg(rs)
    if a['n']==0: return f"{lbl:<26} n=    0"
    return (f"{lbl:<26} n={a['n']:>5}  win%={a['win']:5.1f}  plc%={a['plc']:5.1f}  "
            f"tROI={a['tROI']:6.1f}  fROI={a['fROI']:6.1f}")

def band_of(c, edges):
    for lo,hi,name in edges:
        if c>=lo and c<=hi: return name
    return None

FINE=[(4,5,'4-5'),(6,7,'6-7'),(8,9,'8-9'),(10,12,'10-12'),(13,99,'13+')]
COARSE=[(4,6,'4-6'),(7,9,'7-9'),(10,99,'10+')]

tag=[r for r in recs if tagged(r)]
# ベースライン: 同コンピ帯の「h2h実力馬でない」全馬(コンピ>=4 の非タグ馬)
nontag=[r for r in recs if r['crank'] is not None and r['crank']>=4 and not tagged(r)]

print("="*90)
print("JRA h2h実力馬タグ(h2h順位1-2 ∧ コンピ順位>=4) コンピ帯別BT  2022-2025 全JRA場")
print("h2hは全馬で算出。総horse-records=%d / タグ該当=%d" % (len(recs), len(tag)))
print("="*90)

print("\n### 全体(タグ vs 非タグ・コンピ>=4母集団) ###")
print(line("h2h実力馬タグ 全体", tag))
print(line("非タグ(コンピ>=4) 基準", nontag))
# 参考: コンピ帯無関係の全馬平均複勝率
allr=[r for r in recs if r['crank'] is not None]
print(line("(参考)全馬平均", allr))

for edges,title in [(FINE,'細別: 4-5 / 6-7 / 8-9 / 10-12 / 13+'),(COARSE,'粗別: 4-6 / 7-9 / 10+')]:
    print("\n"+"="*90)
    print("### "+title+" ###")
    print("="*90)
    for lo,hi,name in edges:
        tb=[r for r in tag if lo<=r['crank']<=hi]
        nb=[r for r in nontag if lo<=r['crank']<=hi]
        at=agg(tb); an=agg(nb)
        print(f"\n-- コンピ帯 {name} --")
        print(line(f"  [タグ] コンピ{name}", tb))
        print(line(f"  [非タグ基準] コンピ{name}", nb))
        if at['n']>0 and an['n']>0:
            print(f"   → 複勝率 上乗せ = {at['plc']-an['plc']:+.1f}pt (タグ{at['plc']:.1f} vs 基準{an['plc']:.1f})")
        # 年別複勝率(タグ)
        yr=defaultdict(list)
        for r in tb: yr[r['year']].append(r)
        ys=[]
        for y in ('2022','2023','2024','2025'):
            ry=yr.get(y,[])
            if ry:
                a=agg(ry); ys.append(f"{y}:{a['plc']:.0f}%(n{a['n']})")
            else: ys.append(f"{y}:-")
        print("   年別複勝率(タグ): "+"  ".join(ys))

# 参考: タグ内 h2h1位 vs 2位 の分離(交絡チェック)
print("\n"+"="*90)
print("### 交絡チェック: タグ内 h2h1位 vs 2位 (コンピ>=4) ###")
print("="*90)
print(line("  h2h1位∧コンピ>=4", [r for r in tag if r['hrank']==1]))
print(line("  h2h2位∧コンピ>=4", [r for r in tag if r['hrank']==2]))
