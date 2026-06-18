---
name: kawasaki-kickoff
description: 川崎競馬の分析キックオフ(引き継ぎ)。南関知見・検証workflow・ツール・環境の罠・規律を集約
metadata: 
  node_type: memory
  type: project
  originSessionId: 3458bcf5-956c-4582-a6d7-47d85dd89930
---

川崎競馬(南関東)の分析を別セッションで始めるための引き継ぎ。園田([[sonoda-basics]]/[[sonoda-axis-bet]]/[[sonoda-extra]])・大井([[oi-kyaku-course]]/[[oi-jockey-trainer]]/[[oi-roi-backtest]])で確立した枠組み(コア[[keiba-rating-system]]・DB[[chihou-keiba-db]])を川崎へ適用する。

## 川崎の起点事実(確認済 2026-06)
- DB場名 **N'川崎'**。データ充実は2022以降(各756-779R/年)、最新2026/06/17、**通年開催**(南関は通年)。三連単払戻あり=馬券BT可。
- 距離: **1400mが主力(1345R)**、次1500m(777)/900m(668)/1600m(334)/2000m(228)。
- 未知(最初に出す): 脚質バイアス/四角位置/枠/騎手前付け力/前残り度合い。

## 川崎で既に分かっている関連知見(流用可)
- **南関4場(大井・川崎・船橋・浦和)は市場効率的**: 頑健な過小評価厩舎は無い、軸の単勝は織込済([[oi-jockey-trainer]])。回収プラスは期待しにくい前提。
- **オッズ/人気はDB未保存**(大井で0件)。血統データ14%で使用不可 → 回収は払戻金テーブル(単勝/複勝)で近似。
- ~~馬体重「2走で-10kg以下」妙味は川崎で有効~~ → **訂正: 川崎では妙味なし**([[kawasaki-bet-value]]で多年検証。勝率フラット~0.087・回収~0.76=全体並)。today-picksで★点灯しても川崎では割引く。高知のような勝率2倍効果は出ない。
- 脚質・コース分解は [[oi-kyaku-course]] の手法(序盤位置×四角位置、四角位置が決定的)をそのまま -Venue 川崎 で適用。

## 実証済みの検証 workflow(この順で回す)
1. 規模・最新日・距離×条件分布を確認。
2. 基礎: 脚質IV(序盤位置)・四角位置・枠(内中外)・主力距離・騎手前付け力。tools/oi-kyaku-course.ps1 -Venue 川崎。
3. 軸有力度: tools/axis-backtest.ps1 -Venue 川崎 を複数年(川崎は通年なので年window自由、各年同期間で)。標準重み0.5/0.2/0.2/0.1が頑健か。
4. 馬券BT: tools/trio-backtest.ps1 -Venue 川崎 を複数年平均(3連複/3連単マルチ・相手頭数)。
5. 妙味: 馬体重-10kg(既知)・休養明け・騎手・厩舎・距離替わり・馬場 を年別回収で。

## ツール(接続はappsettings.jsonから自動)
- 汎用(-Venueで川崎可): axis-backtest.ps1, trio-backtest.ps1, today-picks.ps1, oi-kyaku-course.ps1, race-axis.ps1, sonoda-swap-backtest.ps1(軸入替BT)。
- **園田ハードコード(N'園田'→N'川崎'に置換コピー)**: sonoda-overview/draw-jockey/jockey-front/edge/extra.ps1 → 川崎版は kawasaki-*.ps1 として複製推奨。
- today-picks.ps1 の表示フラグ: 馬体重-10kg★妙味は**川崎で点灯する**(valueVenues該当)。重馬場逃げ強調・★短縮降級・◎厩は園田専用なので川崎では出ない(知見が出たら追加)。

## 環境の罠(必須)
- 日本語含む.ps1は**BOM付きUTF-8**保存: `$t=[IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false)); $t=$t.TrimStart([char]0xFEFF); [IO.File]::WriteAllText($p,$t,[Text.UTF8Encoding]::new($true))`。
- コンソール日本語化け回避: 実行時 `[Console]::OutputEncoding=[Text.Encoding]::UTF8`、結果は Export-Csv→Read か Out-File -Encoding UTF8 で取得。
- DB同時アクセスでタイムアウト→複数窓は**順次**実行。bashの `>` で `\` が壊れる→`tools/xxx`(スラッシュ)かWriteツール。
- DB注意([[chihou-keiba-db]]): レース情報「着順」は常に0で未使用→競走結果と 開催場所+開催日+レース番号+馬番 で結合。走破時計破損値は距離別下限でフィルタ。
- リーク回避: コース/騎手/厩舎傾向は検証開始日より前で算出。

## 規律(園田・大井・高知で繰り返し確認)
- 地方は**そこそこ効率的**(南関は特に): 軸の的中力は当たるが**回収は全券種100%割れ**になりがち。価値は「堅い軸」。
- **年度ブレ・単日分散が大きい**→単年/単日の好成績を実力と誤認しない。必ず複数年平均。
- **サブ条件/単年の高回収は過学習**として割り引く(年別で頑健性確認)。
- 軸入替や安易な重み変更より、知見は**today-picksの表示フラグ**で人の判断補助にする(園田で入替ルールは複数年ノイズ=不採用だった)。
