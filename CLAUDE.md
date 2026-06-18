# 中央競馬(JRA)分析プロジェクト

このリポジトリは**地方競馬分析基盤**(GitHub: soyosya/LocalHorceRace)を複製し、コード内部の名称を「地方競馬」→「中央競馬」へ一括リネームしたものです。中央競馬(JRA)の分析・データ取込をここで行います。

## 重要な前提
- **コード内部の名称＝「中央競馬」**: 名前空間 `中央競馬.*`、ソリューション `中央競馬.sln`、DB名 `中央競馬`。**フォルダ名は `JRA`、git リポジトリは `jra`**。
- **DBは未作成**: 接続文字列は `Database=中央競馬`(共通/appsettings.json)。別途 `中央競馬` DB を作成し、JRAデータを取り込む必要がある。
- **データ源が地方競馬とは別物**: 地方競馬の取込(月別開催日程/ConsoleApp のスクレイパ)は地方競馬サイト向け。**JRA用に作り直しが必要**(JRA-VAN/netkeiba 等、別途決定)。
- **地方専用の資産**: 楽天投票(RakutenVote)/極ウマ・コンピ指数/園田 等は地方競馬専用。JRAでは不要 or 差し替え(JRA投票はIPAT、楽天競馬は地方のみ)。全部コピーしてあるので**取捨選択して使う**。

## まず読む(知識の引き継ぎ)
1. **`docs/分析ノウハウ-引き継ぎ.md`** — 地方競馬で確立した分析手法・ツール・バックテスト規律・環境の罠・**JRA適応の指針**。最初に必読。
2. **`docs/地方競馬-memory-参考/`** — 地方競馬の全分析メモ(各場の知見・独自レーティング・軸スコア・キックオフ手順)。⚠️ **これは地方競馬の知見**。JRAは傾向が異なる(前残りが弱い/フィールド大/芝ダ両用/市場効率高め)ため、**鵜呑みにせず手法だけ流用し、JRAデータで再検証**すること。

## 環境の罠(地方競馬から継承・JRAでも同じ)
- **PowerShell .ps1 は UTF-8 BOM付き 必須**。PS5.1 がBOM無しをShift-JIS誤読し、日本語のテーブル名/DB名/文字列が壊れる(`中央競馬`等)。新規 .ps1 を作ったら必ずBOMを付ける。
- 分析スクリプトは Windows PowerShell 5.1 想定(pwsh7は不可な箇所あり)。`??`(null合体)はPS5.1不可→`Nz`等の自前ヘルパ。
- DB接続は `共通/appsettings.json` の `DefaultConnection`。**appsettings.json は .gitignore 済み**(saパスワード)。テンプレ=`appsettings.example.json`(コピーして値を埋める)。
- 資格情報は **git追跡外 `secrets.local.json`**(`共通/Libraly/Secrets.cs`)→環境変数 の順。テンプレ=`secrets.local.example.json`。
- PowerShellの動的配列 `$arr += ` は O(n²) で大量行で固まる→`System.Collections.Generic.List[object]` + `.Add()`。
- ハッシュテーブル内の条件式は `$(if(){}else{})`(`(if(){})` は不可)。

## ソリューション構成(参考)
- `共通/` — EF Core DBContext と共通ライブラリ(Logger/WebDriverHelper/Secrets)。`競走結果/レース情報/払戻金/当日メニュー/リアルタイムオッズ/馬情報` 等の DbSet。
- `ConsoleApp/` — 取込/バッチCLI(地方向け。JRA取込は要新規)。
- `月別開催日程/` — レース情報・コンピ・オッズ取得(地方サイト向け。要差し替え)。
- `tools/` — PowerShell 分析・バックテスト群(手法は流用可能。`docs/分析ノウハウ-引き継ぎ.md` 参照)。
- `RakutenVote/`(地方専用・楽天投票), `園田/`, `DatabaseExplorerApp/`, `Prediction/`, `RaceAnalyzer/`, `AppContoroller/` — 取捨選択。
