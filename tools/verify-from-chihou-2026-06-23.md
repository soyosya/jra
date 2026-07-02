# 地方→JRA 知見の検証＆ランナーパラメータ移植（2026-06-23 依頼）

地方競馬(C:\keiba)の知見をJRA(中央競馬・C:\jra)で**検証し、JRAで有益(年別頑健)なものだけ取り込む**。あわせて地方ランナーのパラメータをJRAランナーに移植する。
**メモリは共有**なので各 `[[...]]` はそのまま読める。地方の台帳=[eval-criteria.md](eval-criteria.md)/[bet-strategies.md](bet-strategies.md)（JRA版と同名・中身は要突合）。

## A. 知見の検証・取り込み
JRAデータ(中央競馬DB)で年別頑健性を検証 → 有益なら **JRA台帳(C:\jra\tools\eval-criteria.md / bet-strategies.md)に追記＋jra-card等へ実装**。地方で効いてもJRAで効くとは限らない（特に脚質は場別）。

- [ ] 突出コンピ1位 g12(1位-2位指数差)≥10 で軸尊重 … [[keiba-compi-standout-axis]]（JRAの「指88+」と類似。g12版の単調性を検証）
- [ ] 軸確度 g12/range13/idx1 → 鉄板/標準/警戒 … [[keiba-compi-axis-confidence]]
- [ ] テクニカル6（コンピ1-3位和）波乱度・断層 … [[keiba-compi-technical6-danso]]
- [ ] 落ち目1位抜け range16(1位-6位差)≥33 … [[keiba-ochime-axis]]
- [ ] 前々走比下降の軸格下げ … [[keiba-compi-prevdrop-axis]]（JRAの[[jra-compi-trajectory]]と突合）
- [ ] 馬場×脚質 買い消し（前走逃げ先行=買い/追込=消し）… [[keiba-baba-style]]（JRAは脚質が**場別で符号反転**＝前残り場[函館]/差し場[東京]。場別に検証 [[hakodate-basics]][[tokyo-basics]]）
- [ ] 能力z（馬場差補正の持時計/上り3F のレース内標準化）… [[keiba-ability-toolkit]]（JRAの[[jra-axis-prob-model]]/スピード指数と統合検討）
- [ ] コンピ前走比Δの回収妙味 … [[compi-index-trend]]（JRAは[[jra-compi-trajectory]]で順位交絡を確認済→突合）
- [ ] オッズ乖離（大谷理論）… [[keiba-odds-divergence]]（JRA公式オッズ[[jra-official-odds]]で早朝乖離を検証）
- [ ] 軸/相手の選び方=コンピ1位軸+コンピ上位相手が最良 … [[keiba-axis-method-comparison]]
- 既にJRA一般化確認済（再検証不要）: コンピ系普遍シグナル（トラジェクトリ連続上昇/下降・乗替穴軸∩地力・拮抗SD）… [[keiba-universal-signals]]

## B. ランナーパラメータの移植
JRAランナー＝**jra-weight-loop / runner-params.json / jra-export-bets**（[[jra-runner-control-web]]）。JRA最良券種＝**ワイド軸流し相手3**（[[jra-bettype-roi]]）に合わせて適応する。地方ランナー実装は C:\keiba\tools\compi-auto-vote.ps1。

- [ ] AiteByCompi … 相手=コンピ順位上位で選ぶ
- [ ] 枠連vs馬連 高オッズ比較 … 馬連の組の枠連オッズが高ければ枠連で投票（単一プール＝公式オッズ=払戻）。**IpatVote/IPATで枠連投票が可能か確認・枠番は出馬表の確定枠を使う**（地方は dbo.レース情報 の確定枠）
- [ ] VolHedge / HedgeMaxSeg / WidePoints … 単勝(断然軸)×波乱度高→複勝/ワイド退避（複勝MIN≤1.1でワイド・点数選択可）
- [ ] TanIfFukushoMin1 … 断然軸(複勝MIN<1.2&単<2.0)→馬連+ワイド(+枠連)
- [ ] VolatilityStake … 波乱度ティア掛金(段1-2×0.5/段3-5×1.0/段6×1.2)
- [ ] Seg6Single … 段6(堅すぎ)の推奨は単複へ迂回
- [ ] FlatStakeFrontRaces … 前半Nレース一律100円
- [ ] TrigamiFukuMin … 複勝→単勝の切替閾値(本番1.35)
- [ ] StakePct … 残高%案分
- [ ] RunnerControlプリセット（複数保存/呼出/編集/コメント・[[keiba-ledger]]）

→ runner-params.json と JRA RunnerControl(:5081) のUIに対応づけて移植。検証して**JRAで頑健なものだけ本番化**。

## 制約
- **作業はC:\jra（OneDrive不使用）** … [[keiba-workfolder-onedrive]]。
- 検証はJRAデータで**年別頑健性必須**。**+EVは期待しない**（JRAは市場効率的＝[[jra-ev-hunt]]。確度向上/損失分散/トリガミ回避が目的）。
- **実金IPAT安全第一**（IpatVoteは実DOMセレクタ較正後に実動 … [[jra-ipat-vote]]）。
