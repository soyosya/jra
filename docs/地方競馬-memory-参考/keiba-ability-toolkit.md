---
name: keiba-ability-toolkit
description: 全場共通の軸スコア＋能力z汎用ツール(-Venue)と各場の重み検証結果
metadata: 
  node_type: memory
  type: project
  originSessionId: 8163103f-28b9-4a45-93e3-004689721fba
---

地方競馬の軸スコアを**任意の開催場所で-Venue指定**で回せる汎用ツール。門別で確立([[monbetsu-axis-bet]]/[[monbetsu-basics]])した「脚質・コネクション＋能力z」を全場へ一般化。コア思想は[[keiba-rating-system]]、DB/接続は[[chihou-keiba-db]]。

## 汎用ツール一式(C:\temp\tools\、接続はkeiba_q.ps1)
- `keiba-features.sql` / `keiba-card.sql`: テンプレ(`:::VENUE:::`/`:::DATE:::`置換)。全距離対象。能力z(ab_time/ab_up3/ab_best/ab_n)出力。
- `keiba-extract.ps1 -Venue <場> -What features|card [-Date]`: 上記を置換実行し `feat_<場>.csv` / `card_<場>.csv` 出力。
- `keiba-score.ps1`: 共通スコア部品(dot-source)。`Init-Rates`で学習年の騎手/調教師勝率を作り `Score-Row $r $WTime $WUp3`。
- `keiba-backtest.ps1 -Venue <場> [-TrainStart/End -TestStart/End -WTime -WUp3]`: 本命勝率/複勝/単複回収を年別表示。
- `keiba-nagashi.ps1 -Venue <場> [-Partners 4 -WTime -WUp3]`: card_<場>.csvから軸1+相手N。
- スコア式(全場共通): `2.0*前走脚質 +1.6*門別逃げ率 +1.2*馬勝率 +5.0*騎手勝率 +3.0*調教師勝率 +0.5*外枠 +gap/延長補正 +WTime*ab_time +WUp3*ab_up3`。能力z=レース内標準化で開催場所/距離/馬場/開催日を相殺・リーク回避。
- 門別専用旧版(monbetsu-*.ps1)はsprint(1000/1200)限定。汎用版は全距離なので数値は微差。

## 能力zの全場検証(2022-23学習→24-25, 本命)←移植性は実証済み
- **全場で勝率が向上**(能力なし→あり最良): 大井26.3→32.4 / 園田29.0→33.2 / 川崎27.3→31.1 / 高知33.5→37.6 / 門別28.3→33.7(全距離)。
- 回収トレードオフは場で違う: **大井・高知は能力で単回収も改善**(中量級重みで大井83.5・高知82.5)、門別・川崎は単回収やや低下。複回収はほぼ全場で改善(園田77→84, 川崎78→85, 高知84→87)。
- **既定重み WTime=2.0/WUp3=1.0** が全場で勝率ほぼ最良=ユニバーサル既定に採用。回収優先なら大井/川崎は WTime=1.0/WUp3=0.5 が好バランス。
- 結論: 能力zは普遍的に「**当てる力↑**」。利益は市場効率で場依存。重みは場ごとに上記から微調整可。

## 注意
- 前残りの強さ・主力距離は場で違う([[oi-kyaku-course]]/[[sonoda-basics]]/[[kawasaki-basics-axis]]/[[kochi-roi-payout]])。スコアの脚質重みは前残り場前提。差し優勢場が出たら脚質重み見直し。
- 単年・サブ条件の高回収は過学習として割引([[oi-roi-backtest]])。複数年で確認。
