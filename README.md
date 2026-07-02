# LocalHorceRace

中央競馬情報サイト（keiba.go.jp）から、開催情報、当日メニュー、出馬表由来のレース情報、競走結果、払戻金、馬情報を取得してSQL Serverへ保存するアプリケーションです。

## データの流れ

このシステムでは、開催情報を起点に各テーブルへデータを広げます。

1. `開催情報`
   - 開催日と開催場所を管理します。
   - keiba.go.jp の月別開催情報ページから、当日メニューURLを取得します。
2. `当日メニュー`
   - 開催日、開催場所ごとのレース一覧を管理します。
   - 出馬表URLと成績URLを保持します。
3. `レース情報`
   - 当日メニューの出馬表URLから取得します。
   - 出走馬、騎手、調教師、馬情報URLなどを保存します。
4. `競走結果`
   - 当日メニューの成績URLから取得します。
   - 着順、走破時計、上り3F、コーナー通過順などを保存します。
5. `払戻金`
   - 競走結果と同じ成績URLのページから取得します。
   - 馬券種別、組番、払戻金額を保存します。
6. `馬情報`
   - レース情報テーブルの馬情報URLから取得します。
   - 馬名だけでは重複する可能性があるため、保存時は馬名と調教師を検索キーとして扱います。

## プロジェクト構成

- `AppContoroller`
  - Windows Formsの操作画面です。
  - 手動取得、リアルタイム取得、欠落補完、対戦評価の起動に使います。
- `ConsoleApp`
  - バッチ実行用のコンソールアプリです。
  - タスクスケジューラなどから起動する場合はこのプロジェクトを使います。
- `月別開催日程`
  - keiba.go.jp から各種データを取得するサービス群です。
  - 現在はライブラリとして `ConsoleApp` や `AppContoroller` から参照します。
- `共通`
  - EF CoreのDBContext、モデル、ロガー、WebDriver初期化などの共通処理です。
- `RaceAnalyzer`
  - 馬同士の対戦評価ロジックです。
- `Prediction`
  - 予測・評価処理用のコンソールアプリです。
- `DatabaseExplorerApp`
  - リアルタイムオッズのチャート表示用アプリです。

## バッチ実行

`ConsoleApp` は第1引数で処理を切り替えます。

```powershell
dotnet run --project "ConsoleApp\ConsoleApp.csproj" -- nextraceinfo
```

主なモードは以下です。

- `nextraceinfo`
  - 翌日の開催情報、当日メニュー、レース情報、競走結果、払戻金、馬別競走履歴を補完します。
- `realtimeraceinfo`
  - 当日のレース情報、競走結果、払戻金をリアルタイムに取得します。
  - 当日の最終レースに払戻金が保存された時点で終了判定します。
- `realtimeodds`
  - 当日のリアルタイムオッズを取得します。
  - 発走時刻から10分以上経過したレースに競走結果または払戻金の未取得データがある場合は、当日メニューの成績URLから補完取得します。
- `fetch-schedule`
  - 開催情報を取得します。
- `fetch-today-menu`
  - 当日メニューを取得します。
- `fetch-payout`
  - 払戻金を取得します。
- `backfill-corner-positions [最大件数] [並列数]`
  - 競走結果に着順がある一方で三・四コーナー通過順が未登録の平地レースを、成績URLから再取得して補完します。
  - 場名の末尾が `ば` のばんえい競馬は通常のコーナー通過順を持たないため対象外です。

## 設定

接続文字列は `共通/appsettings.json` の `ConnectionStrings:DefaultConnection` を使用します。

ChromeDriverは各プロジェクトの `Selenium.WebDriver.ChromeDriver` パッケージで管理しています。Chrome本体のバージョンとパッケージの対応がずれるとSelenium起動に失敗するため、Chrome更新後はパッケージ更新とビルド確認を行ってください。

## ビルド

```powershell
dotnet build "中央競馬.sln"
```

## DBマイグレーション補助

`共通/Migrations` 配下には、既存DBのId列をIDENTITY化するためのSQLがあります。

- `20260603_払戻金_Id_Identity.sql`
- `20260603_共通モデル_Id_Identity_And_Keys.sql`
- `20260603_馬情報_馬名調教師検索.sql`

本番DBへ適用する前に、対象テーブル、重複データ、バックアップ取得状況を確認してください。

## 退避コードの扱い

現在参照されていない処理は、削除せず `___` プレフィックスを付けています。

- ファイル名
- クラス名
- メソッド名
- `___` クラス内だけで使われるプロパティやフィールド

`___` 付きコードは現行処理では使わない前提です。再利用する場合は、名前を戻す前にDBモデル登録、呼び出し元、ビルド、実行時の取得先ページ構造を確認してください。

## スケジュールタスク（Windows タスクスケジューラ）

このマシンで自動実行している競馬関連タスクのうち、**JRA中央競馬分**の一覧。すべて **pwsh7**（`C:\Program Files\PowerShell\7\pwsh.exe`）で実行。スクリプト実体は `…\ドキュメント\JRA\tools\`。
最終更新: 2026-06-21

> **ログオン種別**
> - **Interactive（ログオン時のみ）**: 実行時にWindowsへログオンしている必要あり。ブラウザ操作（Selenium）・対話処理を伴うものは必須。
> - **S4U（ログオン不要）**: バックグラウンドで動くが、対話デスクトップ・一部ネットワーク資格情報にアクセス不可。

### JRA中央競馬タスク

| タスク名 | トリガ | ログオン | スクリプト / コマンド | 役割 |
|---|---|---|---|---|
| **JRA_KeibabookPickup** | 週次 07:00（JRA開催日） | Interactive | `tools\jra-pickup-scheduled.ps1` | 競馬ブック推奨ピックアップ取込（自己ベスト調教・厩舎の話◎・矢印上向き） |
| **JRA_KeibabookNoryoku** | 週次 08:00（JRA開催日） | Interactive | `tools\jra-noryoku-scheduled.ps1` | 競馬ブック能力ファクター取込（スピード指数・レイティング・ファクター・ブック指数） |
| **JRA_WeightLoop** | 毎日 08:45 | Interactive | `tools\jra-weight-loop-task.ps1` | 当日馬体重のライブ取得ループ（発走前馬体重→買目再作成→ログ/メール） |
| **JRA_ReconcileMail** | 毎日 19:00 | Interactive | `tools\jra-nightly-reconcile.ps1` | 夜間の収支照合メール |
| **JRA_PicksMail** | 週次 20:00（JRA開催日） | **S4U** | `tools\jra-picks-scheduled.ps1` | JRA予想（軸/相手）メール通知 |

> ※ 週次タスク（Pickup/Noryoku/PicksMail）はJRA開催のある土日が対象。WeightLoop/ReconcileMailは毎日トリガだが、JRA非開催日はスクリプト側で対象なし→無処理。

### 管理コマンド（PowerShell）

```powershell
# JRAタスク一覧（次回実行時刻・前回結果つき）
Get-ScheduledTask -TaskName 'JRA_*' | Get-ScheduledTaskInfo |
  Format-Table TaskName,NextRunTime,LastRunTime,LastTaskResult

# 個別の一時停止 / 再開 / 手動実行
Disable-ScheduledTask -TaskName <名前>
Enable-ScheduledTask  -TaskName <名前>
Start-ScheduledTask   -TaskName <名前>
```

### 備考
- **地方競馬分のタスク**（`Keiba_*`：コンピ/調教取込・妙味カード・自動投票ランチャー・結果通知 等）は別リポジトリ `…\ドキュメント\地方競馬\20260607\README.md` の「スケジュールタスク」に記載。同一マシンで併走。
- `JRA_PicksMail` のみ **S4U**（ログオン不要）、他のJRAタスクは **Interactive**（ログオン時のみ）。
- メール通知系は Graph API 送信（`secrets.local.json` の Mail*/Graph* 設定）。`JRA_WeightLoop` は当日馬体重をライブ取得して買目を更新する常駐ループ（JRA公式出馬表・SJIS）。
