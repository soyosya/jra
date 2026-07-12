# -*- coding: utf-8 -*-
import json
from collections import defaultdict
recs=json.load(open('records.json'))

def stats(rs):
    n=len(rs)
    if n==0: return (0,0,0,0,0)
    win=sum(r['win'] for r in rs)/n*100
    plc=sum(r['place'] for r in rs)/n*100
    troi=sum(r['tret'] for r in rs)/n*100
    froi=sum(r['fret'] for r in rs)/n*100
    return (n,win,plc,troi,froi)

def line(name,rs):
    n,w,p,t,f=stats(rs)
    print(f"{name:38s} n={n:4d}  win%={w:5.1f}  plc%={p:5.1f}  tanROI={t:6.1f}  fukuROI={f:6.1f}")

def byyear(name,rs):
    print(f"  [{name}] 年別 複勝率(n):")
    d=defaultdict(list)
    for r in rs: d[r['year']].append(r)
    for y in sorted(d):
        n,w,p,t,f=stats(d[y])
        print(f"     {y}: plc%={p:5.1f} (n={n:3d})  fukuROI={f:6.1f}")

has_h=[r for r in recs if r['hrank'] is not None]
print("="*90)
print("JRA 単騎速(⚡)×コンピ×h2h バックテスト  2022-2025  (単騎速=逃/先ちょうど1頭)")
print(f"総単騎速サンプル={len(recs)}  / h2h順位算出可={len(has_h)}")
print("="*90)

L1=recs
L2=[r for r in recs if r['crank'] is not None and r['crank']<=6]
L2h=[r for r in L2 if r['hrank'] is not None]                 # 基準のうちh2h算出可(公平比較用)
L3=[r for r in L2 if r['hrank'] is not None and r['hrank']<=3]
L3b=[r for r in L2 if r['hrank'] is not None and r['hrank']<=2]
L3c=[r for r in L2 if r['hrank'] is not None and r['hrank']>=4]

print("\n--- 主要層 ---")
line("1. 単騎速 全体", L1)
line("2. 単騎速×コンピ<=6  [基準 ⚡単]", L2)
line("   2b. 基準のうち h2h算出可(公平母数)", L2h)
line("3. 単騎速×コンピ<=6×h2h<=3 [主案]", L3)

print("\n--- 感度(コンピ<=6 固定でh2h帯を振る) ---")
line("4a. ...×h2h<=2", L3b)
line("4b. ...×h2h>=4 (低h2hの単騎速)", L3c)

print("\n--- 参考: 単騎速×前走逃げ×コンピ<=3 (=⚡単鉄) ---")
T1=[r for r in recs if r['prevnige']==1 and r['crank'] is not None and r['crank']<=3]
T1h=[r for r in T1 if r['hrank'] is not None]
T2=[r for r in T1 if r['hrank'] is not None and r['hrank']<=3]
line("5. 前走逃げ×コンピ<=3 [基準⚡単鉄]", T1)
line("   5b. 同 h2h算出可", T1h)
line("6. 前走逃げ×コンピ<=3×h2h<=3", T2)

print("\n"+"="*90)
print("年別頑健性(複勝率)")
print("="*90)
byyear("基準 単騎速×コンピ<=6", L2)
byyear("主案 単騎速×コンピ<=6×h2h<=3", L3)
byyear("低h2h 単騎速×コンピ<=6×h2h>=4", L3c)

# h2h independence within fixed compi band: place% by h2h tier
print("\n"+"="*90)
print("交絡チェック: コンピ<=6 固定で h2h帯別 複勝率/勝率")
print("="*90)
for lab,cond in [("h2h1位",lambda r:r['hrank']==1),
                 ("h2h<=2",lambda r:r['hrank']<=2),
                 ("h2h<=3",lambda r:r['hrank']<=3),
                 ("h2h 4-6",lambda r:4<=r['hrank']<=6),
                 ("h2h>=4",lambda r:r['hrank']>=4)]:
    rs=[r for r in L2 if r['hrank'] is not None and cond(r)]
    line("  "+lab, rs)
