import csv, statistics
from collections import defaultdict, Counter
def rd(f):
    with open(f,encoding='utf-8') as fh:
        for r in csv.DictReader(fh,delimiter='\t'): yield r
race_finishers=defaultdict(int); horse_hist=defaultdict(list)
for row in rd('result.tsv'):
    key=(row['開催日'],row['開催場所'],row['レース番号'])
    rank=int(row['rank']) if row['rank'] else 0
    c4=int(row['c4']) if row['c4'] else 0
    if rank>0: race_finishers[key]+=1
    horse_hist[row['馬名']].append({'date':row['開催日'],'key':key,'rank':rank,'c4':c4})
for h in horse_hist: horse_hist[h].sort(key=lambda x:(x['date'],x['key'][2]))
field=defaultdict(list)
for row in rd('race_info.tsv'):
    key=(row['開催日'],row['開催場所'],row['レース番号'])
    field[key].append(row['馬名'])
def style(h,td):
    hist=horse_hist.get(h)
    if not hist: return None
    for rec in reversed(hist):
        if rec['date']>=td: continue
        if rec['rank']>0 and rec['c4']>0:
            fn=race_finishers[rec['key']]
            if fn>1:
                c4=rec['c4']; rat=c4/fn
                return '逃' if c4<=1 else ('先' if rat<=0.34 else ('差' if rat<=0.66 else '追'))
            return None
    return None
cnt=Counter()
tk=[k for k in field if '2022'<=k[0][:4]<='2025']
for k in tk:
    if len(field[k])<5: continue
    td=k[0]
    sp=sum(1 for h in field[k] if style(h,td) in ('逃','先'))
    cnt[sp]+=1
print("races analyzed:",sum(cnt.values()))
for i in sorted(cnt): print(f"  speed-horses={i}: {cnt[i]}")
