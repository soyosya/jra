# 前走同条件 スクリプト一式

作成日: 2026-07-11

このパッケージは、「前走同条件 仕様書 兼 買目生成統合手順書」に関連する PowerShell スクリプトを、原本を変更せずに整理したものです。

## 1. 収録区分

### 01_current_spec_core
最新の正式仕様書（33ページ版）で実名が記載されている正準・主要検証スクリプトです。

- `samecond-detect.ps1` — 日次の中団 A/S 検出器
- `samecond-sweep.ps1` — 時計1位・簡易ADV・簡易HOLD等の一斉検証
- `samecond-v3-tables.ps1` — C0～C5、欠損、mid_rank×HOLD等の追加検証

### 02_earlier_appendix_named
同名の先行仕様書（22ページ版）の付録Dに実名が記載されていた追加スクリプトです。漏れ防止のため収録しています。

- `samecond-extract6.ps1` — 検証用基礎CSVのSQL抽出
- `samecond-v2-compare.ps1` — V2構造分岐・頑健ADV/HOLD等の比較

### 03_related_validation_reference
第三者検証資料一式に含まれていた、上記以外のPowerShellコードです。正式なA/S本番条件そのものではなく、定義確認・派生検証・再現確認用です。

## 2. 重要な依存関係

- `samecond-detect.ps1` は、同じフォルダーに `keiba-common.ps1` が存在する前提で、`Get-KeibaConnString` を呼び出します。
- `samecond-extract6.ps1` は、原本のまま `C:\keiba\tools\keiba-common.ps1` を読み込みます。
- `keiba-common.ps1` は提供された検証ZIPに含まれておらず、仕様書にも内容が定義されていないため、このパッケージでは捏造していません。既存の競馬DB環境にある正本を使用してください。
- SQL Server上に、原本コードが参照するテーブル／ビュー（例: `dbo.レース情報`, `dbo.vw_競走結果統合` 等）が必要です。
- `samecond-sweep.ps1` は既定で `C:\keiba\analysis\samecond_mid_base5.csv` を参照します。
- `samecond-v2-compare.ps1` と `samecond-v3-tables.ps1` は既定で `C:\keiba\analysis\samecond_mid_base6.csv` を参照します。

## 3. 実行例

```powershell
# 日次検出
.\samecond-detect.ps1 -Date '2026-07-10' -Venue '園田'

# 検証用CSV抽出
.\samecond-extract6.ps1 -From '2022-01-01' -To '2026-07-09' -Out 'C:\keiba\analysis\samecond_mid_base6.csv'

# 一斉検証
.\samecond-sweep.ps1 -Base 'C:\keiba\analysis\samecond_mid_base5.csv' -SameTh 0.60

# V2比較
.\samecond-v2-compare.ps1 -Base 'C:\keiba\analysis\samecond_mid_base6.csv' -SameTh 0.60

# V3追加表
.\samecond-v3-tables.ps1 -Base 'C:\keiba\analysis\samecond_mid_base6.csv' -SameTh 0.60
```

## 4. 買目生成スクリプトについて

正式仕様書の「買目生成統合手順」は、既存買目エンジンとのインターフェースと処理順を定めたものであり、本文中に専用の買目生成スクリプト名は記載されていません。そのため、存在しない買目生成コードを新規作成して正本扱いすることはしていません。

前走同条件A/Sは、既存軸・相手・券種テンプレート・較正確率・オッズ・EV閾値へ追加する補助信号です。既存買目エンジンを入手せずに、正準の買目生成処理を再現することはできません。

## 5. 原本性

- `.ps1` は提供された第三者検証資料のコードをバイト単位でコピーしています。
- 改変は行っていません。
- `SHA256SUMS.txt` で各ファイルのハッシュを確認できます。
- `MANIFEST.csv` に収録区分と役割を記載しています。
