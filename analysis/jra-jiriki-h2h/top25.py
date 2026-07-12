import json
recs=json.load(open('records.json'))
tanki=[r for r in recs if r['crank'] is not None and r['crank']<=6]
hits=[r for r in tanki if r['place']==1]   # 複勝圏内(着1-3)
hits.sort(key=lambda x:(x['date'],int(x['rno'])), reverse=True)
print(f"⚡単(単騎速×コンピ<=6) 複勝圏内的中 全期間={len(hits)}件 / 直近25件:")
print(f"{'開催日':10} {'場':4} {'R':>2} {'馬名':14} {'着':>2} {'単勝':>6} {'複勝':>5} {'コンピ':>4} {'h2h':>4} {'前走':>3} {'★':>2}")
for r in hits[:25]:
    tan=f"{r['tanpay']:.0f}" if r['fin']==1 else '-'
    h=str(r['hrank']) if r['hrank'] is not None else '-'
    star='★' if (r['hrank'] is not None and r['hrank']<=3) else ''
    nm=r['name'][:13]
    print(f"{r['date']:10} {r['venue']:<4} {r['rno']:>2}  {nm:<14} {r['fin']:>2} {tan:>6} {r['fukupay']:.0f} {r['crank']:>4} {h:>4} {r['style']:>3} {star:>2}")
