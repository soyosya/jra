# 前走同条件 完全再現パッケージ

## 目的

第三者が、同一のCSVエクスポートZIPと対象日を使い、**前走同条件**の確度判定、参考印、参考買目、監査出力を同一結果で生成・照合できる自己完結型パッケージです。

旧名称からの変更は名称・ファイル名・出力スキーマの移行であり、選抜条件、閾値、対象20セル、時計同率処理、買目4点の生成規則は変更していません。対応表は `docs/名称変更対応表.md` を参照してください。

本パッケージは次を生成します。

1. 前走同条件V3（M_base、clock1、S/A/A-K/A-U）
2. コンピ指数上位4頭による参考印
3. 固定された参考買目4点
4. 前走同条件S/Aと既存主軸の一致判定
5. レース単位・馬単位の監査CSV

外部Pythonパッケージ、SQL Server、`keiba-common.ps1`は不要です。Python標準ライブラリだけで動作します。

## 必要環境

- Windows 10/11 または Windows Server
- Python 3.11以上
- 入力: `地方競馬_csv_export_latest.zip` と同じ構造のCSV ZIP

## 1日分の実行

```powershell
.in\Generate-Picks.ps1 `
  -InputZip 'C:\data\地方競馬_csv_export_latest.zip' `
  -Date '2026-07-10' `
  -OutputDir 'C:\data\output'
```

Pythonを直接使う場合:

```powershell
python .\src\generate_picks.py --input-zip C:\data\地方競馬_csv_export_latest.zip --date 2026-07-10 --output-dir C:\data\output
```

## 出力

- `race_picks.csv`: 全レースの印、参考買目、前走同条件S/A統合結果
- `samecond_race_summary.csv`: レース単位ゲート、M_raw、M_base、clock1
- `samecond_horse_audit.csv`: 全馬の計算値と除外理由
- `recommendations.csv`: S/Aが◎と一致したレースだけ
- `picks.json`: API連携用
- `run_metadata.json`: バージョン、表示名称、対象日

`race_picks.csv` の前走同条件列は `samecond_m_base`, `samecond_pick_u`, `samecond_pick_name`, `samecond_tier`, `samecond_subtype`, `samecond_reason` です。

## 5日固定検証

```powershell
.in\Run-Validation.ps1
```

同梱fixtureから固定5日分を再生成し、`validation/expected` の25ファイルとバイト単位で比較します。合成受入試験と固定5日検証がともに `PASS` になれば、実装・設定・Python環境が正本と一致しています。

固定検証日は次の5日です。

- 2023-08-29
- 2025-04-23
- 2025-06-20
- 2025-09-08
- 2025-12-03

選定条件と固定seedは `validation/selected_dates.csv` に保存されています。

## 買目の位置付け

本パッケージの買目は、正式仕様書の参考表示テンプレートを一致検証用に固定したものです。オッズ・EVを使用しないため、購入推奨ではありません。実購入には、別途確立されたオッズ、期待値、資金配分の判定が必要です。

## フォルダー

- `src`: 実行に必要な全Pythonコード
- `bin`: PowerShell/バッチ実行ラッパー
- `config`: 固定定数、対象20セル、参考買目定義
- `docs`: 正式仕様書、補足仕様、名称変更対応表
- `validation`: 固定5日、最小fixture、期待出力、2026-07-10既知参照
- `legacy_reference`: 第三者検証時のPowerShell参考実装。日次生成には不要
