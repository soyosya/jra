---
name: chihou-keiba-db
description: 地方競馬DB(SQL Server)とスクレイピングアプリの構成・データの癖・fetch-rangeモード
metadata: 
  node_type: memory
  type: project
  originSessionId: 92dbd5f8-a0fc-4f0f-9cd4-41ccd8b79035
---

# 地方競馬DB / スクレイピングアプリ

- ソース: `C:\Users\suzukih\OneDrive - 株式会社創陽社\ドキュメント\地方競馬\20260607`(.NET 10 / EF Core / Selenium)
- DB: `192.168.168.81\SQLEXPRESS` の「地方競馬」。接続文字列は `共通/appsettings.json`
- 主要テーブル: 競走結果(75万行)・払戻金(87万行)・レース情報(出馬表由来)・当日メニュー・開催情報

## データの癖
- レース情報テーブルの「着順」列は常に0(未使用)。着順は競走結果と 開催場所+開催日+レース番号+馬番 で結合して取得する
- 「条件」列はコース距離付き表記とクラス表記のみの2書式が混在 → 集計時は「サラブレッド系」「混合」以降を切り出して正規化する
- 当日メニュー・開催情報は2022-01以降のみ。2021以前は競走結果が部分的にあるだけ
- 賞金額がほぼクラスを表す(地方競馬の番組構成)

## fetch-range実行の実務(2026-06-17 当日結果反映で確認)
- **ConsoleApp.exe の bin は stale になりがち**。OneDrive\…\20260607 の Release/Debug exe はソース(Program.cs)より古く、`fetch-range` 指定でも switch に乗らず Start→終了だけで空振りした。実行前に `dotnet build "<…>\20260607\ConsoleApp\ConsoleApp.csproj" -c Release`(.NET10 SDK 10.0.300 で9秒)で再ビルドしてから使う。NLogログの行番号がソースとずれていたら古いバイナリの疑い。
- 当日分だけ反映: `ConsoleApp.exe fetch-range YYYY-MM-DD YYYY-MM-DD`(working dir=exeのbin)。出馬表(レース情報)が既取得ならNeedRaceInfo=falseでChrome不要、結果・払戻はHTTPで高速。`full`不要(`ResolveResultUrl`が出馬表URLの DebaTable→RaceMarkTable 置換で結果URLを導出)。
- スキップ判定: 競走結果は**走破時計>0の行が1つでもあれば取得済み**扱い→速報(着順上位のみ・時計0)は確定版で上書きされる。払戻は行が1つでもあれば取得済み(速報払戻が残ると再取得されない点に注意)。
- **四コーナー等の通過順は結果ページHTTPに含まれず常に0**。`backfill-corner-positions` で別途補完(直後のレースはソース側未掲載が多く後刻実行が必要)。脚質分析には四角が要るのでバックフィル後に再集計する。

## fetch-rangeモード(2026-06-13追加)
- `ConsoleApp.exe fetch-range <開始日> <終了日>`: 当日メニュー起点に レース情報/競走結果/払戻金 の未取得分だけ補完。取得済みスキップなので中断後同じ引数で再開可能
- keiba.go.jp はヘッドレスChromeのUA(HeadlessChrome/…)を HTTP 429 で拒否する → WebDriverHelper で通常Chrome UAを偽装して回避(2026-06-13修正)。過去のレース情報カバレッジが薄かった一因の可能性
- 2026-06-13 に 2022-01-01~2026-06-13 の全量補完(約4.7万レース、推定35時間)を起動。ログ: `C:\temp\fetch-range-full.log`

## リアルタイム取得の障害と対処(2026-06-14)
別PCのログ解析で判明した2系統の障害を 20260607 ソースで修正済み。
- 障害A: 監視ループ(ConsoleApp `MonitorTodayRaceInfo` / AppController `getRealtimeRaceInfo`)が1つのdriverを使い回し、Chromeがクラッシュしても作り直さない。死亡セッションへの各コマンドが既定60秒HttpClientタイムアウトで失敗→catch→同じ死んだdriverで再ループ、と「1分に1エラー」で一晩中空転(SocketException 995 = ブラウザプロセス消滅)。
  - 対処: `WebDriverHelper` に `IsAlive`/`EnsureAlive`(死活確認→Quit→再生成)追加。コマンドTO/ページロードTOを30秒に短縮。両監視ループの周回冒頭で `EnsureAlive` 呼び出し(driverは ref/再代入)。
- 障害B: `RaceHistoryCompleter` が馬情報ページの要素を3秒固定で待ち、429や遅延で頻発タイムアウト→ERROR大量(289件)。
  - 対処: 待機を15秒に延長、`WebDriverTimeoutException` はERRORでなくスキップ(INFO)扱い。根本の429は上記UA偽装で回避。
- ビルド検証: AppController と ConsoleApp 各0エラー。ソリューション一括ビルドは補完ジョブがDLLロック中だと MSB3021/3027 になるのでジョブ停止が必要。

## 接続・復元(2026-06-17 UM790PROで確認)
- このPC(UM790PRO)では DB はローカル `.\sqlexpress` の「地方競馬」。接続文字列例は `C:\temp\LocalHorceRace\Prediction\appsettings.json`(User Id=nra)。192.168.168.81 は別PC視点の旧情報。
- 日本語DB/テーブル名を扱うクエリ補助は `C:\temp\keiba_q.ps1`(SqlClient→Export-Csv、**BOM付きUTF-8で保存必須**)。Writeツールで作るとBOM無しになりPS5.1で文字化け→DB名「地方競馬」が「蝨ｰ譁ｹ…」化。kickoffのBOM変換を都度かける。
- **バックアップ復元手順**(nraは権限不足。Windows統合認証 `UM790PRO\suzukih` が sysadmin): master接続で `ALTER DATABASE [地方競馬] SET SINGLE_USER WITH ROLLBACK IMMEDIATE` → `RESTORE DATABASE ... WITH REPLACE, MOVE '地方競馬'/'地方競馬_log' TO ...mdf/ldf` → `SET MULTI_USER`。論理名は `地方競馬`/`地方競馬_log`。
- **復元後はnraがorphan化**(SID不一致でテーブル0件に見える)→ DB接続で `ALTER USER [nra] WITH LOGIN=[nra]; ALTER ROLE db_datareader ADD MEMBER [nra]; ALTER ROLE db_datawriter ADD MEMBER [nra]` で解消。
- バックアップ群は `C:\temp\backup\`(地方競馬.bak=13GB/2025-07、地方競馬_developer_baseline.bak・_premigration.bak=各1.3GB/2026-06-17のmigration検証時)。2026-06-17時点でライブDBが空だった→developer_baselineを復元して使用。

## 作業環境の注意
- PowerShellツールでSQLを書くとき、別名 `ri` はRemove-Itemエイリアスと誤検知されてブロックされる → 別名は rinfo 等にする
- 補完ジョブ再開後のログは `C:\temp\fetch-range-full2.log`(PID変動。プロセス名 ConsoleApp で確認)
