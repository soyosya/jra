# -*- coding: utf-8 -*-
import csv, statistics, json
from collections import defaultdict
from datetime import datetime, timedelta

def rd(f):
    with open(f, encoding='utf-8') as fh:
        for row in csv.DictReader(fh, delimiter='\t'):
            yield row

NIGE = '逃'  # 逃
SEN  = '先'  # 先
SASHI= '差'  # 差
OI   = '追'  # 追

# ---- race_info ----
race_meta = {}
umaname = {}
field_by_race = defaultdict(list)
for row in rd('race_info.tsv'):
    key = (row['開催日'], row['開催場所'], row['レース番号'])
    dist = row['dist']
    dist = int(dist) if dist not in ('', None) else 0
    race_meta[key] = (row['surf'], dist)
    nm = row['馬名']; num = row['馬番']
    umaname[(key, num)] = nm
    field_by_race[key].append(nm)

# ---- result ----
race_time = defaultdict(dict)
race_finishers = defaultdict(int)
horse_hist = defaultdict(list)
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
    horse_hist[nm].append({'date':row['開催日'],'key':key,'rank':rank,'tim':tim,'c4':c4})
for h in horse_hist:
    horse_hist[h].sort(key=lambda x:(x['date'], x['key'][2]))

# ---- compi ----
compi_rank = {}
for row in rd('compi.tsv'):
    key = (row['開催日'], row['開催場所'], row['レース番号'])
    rc = row['rankc']
    if rc not in ('',None):
        compi_rank[(key,row['馬番'])] = int(rc)

# ---- payout ----
tan_pay = {}; fuku_pay = {}
TAN='単勝'; FUKU='複勝'
for row in rd('payout.tsv'):
    key = (row['開催日'], row['開催場所'], row['レース番号'])
    pay = row['pay']
    if pay in ('',None): continue
    pay = float(pay)
    if row['bet']==TAN: tan_pay[(key,row['組番'])]=pay
    elif row['bet']==FUKU: fuku_pay[(key,row['組番'])]=pay

name2num = {}
for (key,num),nm in umaname.items():
    name2num[(key,nm)]=num

def clip(x): return 8.0 if x>8 else (-8.0 if x<-8 else x)

def prev_race_style(h, tdate):
    hist = horse_hist.get(h)
    if not hist: return None
    for rec in reversed(hist):
        if rec['date']>=tdate: continue
        if rec['rank']>0 and rec['c4']>0:
            fn = race_finishers[rec['key']]
            if fn>1:
                c4=rec['c4']; rat=c4/fn
                if c4<=1: return NIGE
                elif rat<=0.34: return SEN
                elif rat<=0.66: return SASHI
                else: return OI
            return None
    return None

def single_speed(field, tdate):
    styles={}
    for h in field:
        s=prev_race_style(h, tdate)
        if s: styles[h]=s
    speed=[h for h in styles if styles[h] in (NIGE,SEN)]
    if len(speed)==1:
        return speed[0], styles[speed[0]]
    return None, None

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
records=[]
for key in target_keys:
    field=field_by_race[key]
    if len(field)<5: continue
    tdate=key[0]
    ss_h, ss_style = single_speed(field, tdate)
    if not ss_h: continue
    num=name2num.get((key,ss_h))
    if num is None: continue
    crank=compi_rank.get((key,num))
    tsurf,tdist=race_meta[key]
    h2hrank=h2h_scores(field,tdate,tsurf,tdist)
    hrank = h2hrank.get(ss_h) if h2hrank else None
    rec = next((r for r in horse_hist[ss_h] if r['key']==key), None)
    if rec is None: continue
    fin=rec['rank']
    if fin<=0: continue
    win = 1 if fin==1 else 0
    place = 1 if fin<=3 else 0
    tret = tan_pay.get((key,num),0.0)/100.0 if win else 0.0
    fret = fuku_pay.get((key,num),0.0)/100.0 if place else 0.0
    prevnige = 1 if ss_style==NIGE else 0
    records.append({'year':tdate[:4],'crank':crank,'hrank':hrank,'win':win,'place':place,
                    'tret':tret,'fret':fret,'prevnige':prevnige,
                    # --- 明細(CSV用) ---
                    'date':tdate,'venue':key[1],'rno':key[2],'num':num,'name':ss_h,
                    'fin':fin,'style':ss_style,
                    'tanpay':tan_pay.get((key,num),0.0),'fukupay':fuku_pay.get((key,num),0.0)})

with open('records.json','w') as f: json.dump(records,f)
print("single-speed samples:", len(records))
print("with compi rank:", sum(1 for r in records if r['crank'] is not None))
print("with h2h rank:", sum(1 for r in records if r['hrank'] is not None))

# --- ⚡単(単騎速×コンピ<=6)の全馬明細をCSV出力 ---
import csv as _csv
tanki=[r for r in records if r['crank'] is not None and r['crank']<=6]
with open('hits_tanki.csv','w',newline='',encoding='utf-8-sig') as f:
    w=_csv.writer(f)
    w.writerow(['レースID','開催日','開催場所','レース番号','馬番','馬名','着順',
                '複勝圏内','単勝払戻','複勝払戻','コンピ順位','h2h順位','前走脚質','実力馬★'])
    # 新しい順(直近優先)
    for r in sorted(tanki, key=lambda x:(x['date'],int(x['rno']),int(x['num'])), reverse=True):
        rid=f"{r['date']}_{r['venue']}_{r['rno']}R"
        jitsu='★' if (r['hrank'] is not None and r['hrank']<=3) else ''
        w.writerow([rid,r['date'],r['venue'],r['rno'],r['num'],r['name'],r['fin'],
                    ('的中' if r['place'] else ''),
                    (f"{r['tanpay']:.0f}" if r['fin']==1 else ''),
                    (f"{r['fukupay']:.0f}" if r['place'] else ''),
                    r['crank'], (r['hrank'] if r['hrank'] is not None else ''),
                    r['style'], jitsu])
print("hits_tanki.csv rows(⚡単全馬):", len(tanki),
      " 複勝圏内的中:", sum(1 for r in tanki if r['place']))
