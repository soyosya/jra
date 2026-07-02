# 競馬ブック取得を地方競馬プロジェクトへ移植する手順(ポータブル雛形)

JRA(中央競馬)プロジェクトで実装した「競馬ブック取得」の**取得インフラ**を、地方競馬プロジェクト
(`地方競馬.sln` / namespace `地方競馬.*` / DB `地方競馬`)へ移植するための雛形と手順です。

---

## 0. 大前提(重要)
- **競馬ブックの「厩舎の話(danwa)」「調教(cyokyo)」は中央競馬(`/cyuou/`)専用**で、地方競馬(`/chihou/`)には**存在しません**。
- 地方の競馬ブックにあるのは: `nittei`(日程) `syutuba`(出馬表) `cyokuzen`(直前) `nouken`(能力検査) `seiseki`(成績) `sokuhou`(速報) 等。
- したがって移植するのは「**取得の土台(curl/ログイン/発見/range/保存)**」で、**解析(Parse)と保存(Save)は地方で取りたいページに合わせて実装**します。
- 地方の **race_id は16桁**(中央は12桁)。**内部の並びは要検証で「先頭8桁=YYYYMMDD」ではない**(例 `2026041905010611` は6/11開催)。ただし発見は `nittei/{yyyyMMdd}` 日付駆動なので**開催日は対象日で確定**。場・Rは**ページのタイトル/内容から取得**するのが確実。

## 1. 雛形ファイルの配置
- `競馬ブック取得.地方雛形.cs` を **`月別開催日程/Services/競馬ブック取得.cs`** として配置(namespace は `地方競馬.Services` 済み)。
- そのまま流用できる土台: `RunCurl`/`GetHtml`(curl.exe経由=.NET HttpClientのbot判定回避)、`EnsureLogin`(会員ログイン)、`DiscoverRaceIds`(/chihou/nittei→syutuba race_id)、`取得`/`取得範囲`(range・raceid単位スキップ=再開可)、`LoadExistingRaceIds`。
- `TODO` 箇所(対象ページURL・Parse・Save・テーブル名)を地方の対象に合わせて実装。

## 2. Secrets に競馬ブックの資格情報を追加
`共通/Libraly/Secrets.cs` に以下を追加(JRAと同実装。**競馬ブックのアカウントは中央・地方共通**):
```csharp
public static string? KeibabookUser => Get("KeibabookUser", "KEIBABOOK_USER");
public static string? KeibabookPass => Get("KeibabookPass", "KEIBABOOK_PASS");
```
> ⚠️ 地方の旧版には `共通/Libraly/Secrets.cs` 自体が無い場合があります。無ければJRAの `共通/Libraly/Secrets.cs`(secrets.local.json→環境変数の順で読むヘルパ)ごと移植してください。

`secrets.local.example.json`(と実体 `secrets.local.json`)にキーを追加:
```json
"KeibabookUser": "",
"KeibabookPass": ""
```
`secrets.local.json` は `.gitignore` 済みであること。値はJRAで使っているものと同じ。

## 3. csproj にパッケージ追加
`月別開催日程/レース情報取得.csproj`(地方の該当csproj)に **Microsoft.Data.SqlClient** を追加(raw INSERT用。地方の旧版には未追加の可能性):
```xml
<PackageReference Include="Microsoft.Data.SqlClient" Version="6.0.1" />
```
> 競馬ブックは UTF-8 なので `System.Text.Encoding.CodePages` は不要(EUC-JPのnetkeiba/極ウマとは別)。

## 4. 保存テーブル(取りたいデータに応じて)
- 取りたい地方ページのデータに合わせて raw テーブルを作成(EFモデル外・`取得日時`スナップショット推奨)。
- 雛形DDL: JRAの `tools/keibabook-danwa-schema.sql` / `tools/keibabook-cyokyo-schema.sql` を参照(列・索引・スナップショットUXの作り方)。
- 着順等との結合は `(開催場所,開催日,レース番号,馬番)` を共通キーに。`raceid` 列を持たせると range のスキップに使える。

## 5. ConsoleApp にコマンド配線
`ConsoleApp/Program.cs` の switch に追加(コマンド名は任意):
```csharp
case "fetch-kb":       競馬ブック取得.取得(args); break;
case "fetch-kb-range": 競馬ブック取得.取得範囲(args); break;
```
> ConsoleApp が `共通/appsettings.json` を出力へコピーしていること(DBContext/接続文字列解決のため。JRAと同構成)。

## 6. 動作確認
1. `secrets.local.json` に `KeibabookUser/Pass` を設定。
2. `dotnet run --project ConsoleApp -- fetch-kb --date <開催日>` 等で、ログ冒頭に「**競馬ブックにログインしました**」が出れば会員データ取得が有効。
3. curl は Windows標準 `C:\Windows\System32\curl.exe` を使用(.NET HttpClient はTLSフィンガープリントでbot判定されログインページが返るため)。

## はまりどころ(JRAで実証済み)
- **.NET HttpClient は不可**(bot判定でログインページ18KBが返る)→ 必ず `curl.exe` 経由。
- ログインは `/login/login` への Laravel フォーム(`_token` CSRF + `login_id`/`pswd`/`service=keibabook`/`autologin=1`)。成功判定=応答に `name="pswd"` が無いこと。
- 解析はスナップショット重複に注意(同レース複数回取得で `調教` 等が複数行 → 結合は最新1件 `OUTER APPLY ... ORDER BY 取得日時 DESC`)。
- 地方 race_id=16桁。`DiscoverRaceIds` の正規表現は `\d{16}`(中央は `\d{12}`)。

## 将来(共通ライブラリ化=オプション3)
土台(curl/ログイン/発見/range/保存)を `共通` 配下の共有クラス(例 `共通/Libraly/KeibabookClient.cs`)に切り出し、中央・地方の両 `競馬ブック取得` がそれを使う形にすると重複が消えます。中央(`/cyuou/`・12桁)と地方(`/chihou/`・16桁)の差分はコンストラクタ引数(section・race_id桁数・場コード表)で吸収。今回はコピー運用(オプション1)、安定後に共通化(オプション3)へ。
