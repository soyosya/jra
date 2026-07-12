# -*- coding: utf-8 -*-
# JRA h2h実力馬タグ(h2h順位1-2 かつ コンピ順位>=4)のコンピ帯別バックテスト
# h2hは全馬について算出する(単騎速に限定しない)。前回bt.pyのh2hロジックと一致。
import csv, statistics, json, sys
from collections import defaultdict
from datetime import datetime, timedelta

def rd(f):
    with open(f, encoding='utf-8') as fh:
        for row in csv.DictReader(fh, delimiter='\t'):
            yield row

# ---- race_info ----
race_meta = {}
umaname = {}
field_by_race = defaultdict(list)
for row in rd('race_info.tsv'):
    key = (row['開催日'], row['開催場所'], row['レース番号'])
    dist = row['dist']; dist = int(dist) if dist not in ('', None) else 0
    race_meta[key] = (row['surf'], dist)
    nm = row['馬名']; num = row['馬番']
    umaname[(key, num)] = nm
    field_by_race[key].append(nm)

# ---- result ----
race_time = defaultdict(dict)
race_finishers = defaultdict(int)
horse_hist = defaultdict(list)
finish_by = {}   # (key,name) -> rank
for row in rd('result.tsv'):
    key = (row['開催日'], row['開催場所'], row['レース番号'])
    rank = row['rank']; tim = row['tim']; c4 = row['c4']
    rank = int(rank) if rank not in ('',None) else 0
    tim = float(tim) if tim not in ('',None) else 0.0
    c4 = int(c4) if c4 not in ('',None) else 0
    nm = row['馬名']
    if rank > 0:
        race_finishers[key]+=1
        if tim>0: race_time[key][nm]=tim
        finish_by[(key,nm)] = rank
    horse_hist[nm].append({'date':row['開催日'],'key':key,'rank':rank,'tim':tim,'c4':c4})
for h in horse_hist:
    horse_hist[h].sort(key=lambda x:(x['date'], x['key'][2]))

# ---- compi ----
compi_rank = {}
field_size = {}
for row in rd('compi.tsv'):
    key = (row['開催日'], row['開催場所'], row['レース番号'])
    rc = row['rankc']
    if rc not in ('',None):
        compi_rank[(key,row['馬番'])] = int(rc)
    hd = row.get('頭数')
    if hd not in ('',None):
        try: field_size[key]=int(hd)
        except: pass

# ---- payout ----
tan_pay = {}; fuku_pay = {}
for row in rd('payout.tsv'):
    key = (row['開催日'], row['開催場所'], row['レース番号'])
    pay = row['pay']
    if pay in ('',None): continue
    pay = float(pay)
    if row['bet']=='単勝': tan_pay[(key,row['組番'])]=pay
    elif row['bet']=='複勝': fuku_pay[(key,row['組番'])]=pay

name2num = {}
for (key,num),nm in umaname.items():
    name2num[(key,nm)]=num

def clip(x): return 8.0 if x>8 else (-8.0 if x<-8 else x)

def h2h_scores(field, tdate, tsurf, tdist):
    if not tsurf or tdist<=0: return None
    dmin = (datetime.strptime(tdate,'%Y-%m-%d')-timedelta(days=365)).strftime('%Y-%m-%d')
    recent={}
    for h in field:
        hist=horse_hist.get(h,[])
        picks=[]
        for rec in reversed(hist):
            if rec['date']>=tdate or rec['date']<dmin: continue
            if rec['tim']<=0: continue
            k=rec['key']; m=race_meta.get(k)
            if not m: continue
            s,dd=m
            if s!=tsurf or dd<=0 or abs(dd-tdist)>200: continue
            picks.append(k)
            if len(picks)>=6: break
        recent[h]=picks
    mavg={h:{} for h in field}
    for a in field:
        tmp=defaultdict(list)
        for k in recent[a]:
            m=race_time[k]
            if a not in m: continue
            ta=m[a]; wt=min(m.values())
            if wt<=0: continue
            for x,tx in m.items():
                if x==a: continue
                tmp[x].append(clip((tx-ta)/wt*100.0))
        for x,vals in tmp.items():
            mavg[a][x]=statistics.median(vals)
    fset=set(field)
    def pairm(a,b):
        vv=[]
        if b in mavg[a]: vv.append(mavg[a][b])
        if a in mavg[b]: vv.append(-mavg[b][a])
        if vv: return sum(vv)/len(vv)
        common=[c for c in mavg[a] if c in mavg[b] and c!=a and c!=b]
        if not common: return None
        fc=[c for c in common if c in fset]
        use=fc if fc else common
        return statistics.median([mavg[a][c]-mavg[b][c] for c in use])
    score={}
    for a in field:
        ms=[]
        for b in field:
            if a==b: continue
            m=pairm(a,b)
            if m is not None: ms.append(m)
        if ms: score[a]=sum(ms)/len(ms)
    ranked=sorted(score.keys(), key=lambda h:-score[h])
    return {h:i+1 for i,h in enumerate(ranked)}

target_keys=[k for k in field_by_race if '2022'<=k[0][:4]<='2025' and k in race_meta]
print("target races:", len(target_keys), file=sys.stderr)

records=[]   # 全馬(h2h算出可のみ)。tagged判定はコンピ順位が必要。
done=0
for key in target_keys:
    field=field_by_race[key]
    if len(field)<5: continue
    tdate=key[0]
    tsurf,tdist=race_meta[key]
    h2hrank=h2h_scores(field,tdate,tsurf,tdist)
    if not h2hrank: continue
    for h in field:
        hr=h2hrank.get(h)
        if hr is None: continue
        num=name2num.get((key,h))
        if num is None: continue
        crank=compi_rank.get((key,num))
        fin=finish_by.get((key,h))
        if fin is None or fin<=0: continue
        win=1 if fin==1 else 0
        place=1 if fin<=3 else 0
        tret=tan_pay.get((key,num),0.0)/100.0 if win else 0.0
        fret=fuku_pay.get((key,num),0.0)/100.0 if place else 0.0
        records.append({'year':tdate[:4],'crank':crank,'hrank':hr,'win':win,'place':place,
                        'tret':tret,'fret':fret,
                        'date':tdate,'venue':key[1],'rno':key[2],'num':num,'name':h,'fin':fin,
                        'nfield':field_size.get(key,len(field))})
    done+=1
    if done%2000==0: print("  processed races:", done, file=sys.stderr)

with open('records_all.json','w') as f: json.dump(records,f)
print("total horse-records(h2h算出可,コンピ有無問わず):", len(records), file=sys.stderr)
print("  with compi rank:", sum(1 for r in records if r['crank'] is not None), file=sys.stderr)
