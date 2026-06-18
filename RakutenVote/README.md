# RakutenVote — 楽天競馬 自動投票

危険ローテ除外つき軸 → **3連単マルチ(軸1頭・相手N頭流し)** で楽天競馬の**投票Lite(bet_lite)**に投票するツール。
投票LiteはプレーンHTMLフォーム(安定した name 属性・POST遷移)で、SPAの通常投票より自動化が堅牢。

投票フロー(実DOMに基づく):
1. ログイン: ID(`#user_id`)→次へ(`#cta001`)→PW(`#password_current`)→次へ(`#cta011`)
2. レース選択: 競馬場(名前で選択)/レース/式別=三連単(9)/方式=流し(32)→「買い目を選択する」
3. 買い目: 軸=`me1[]`ラジオ・相手=`me2[]`チェック・`isMulti`・金額=`buyUnitCount`(各N00円)→「投票内容を確認する」
4. 確認: `#cashConfirm`に合計額 → 「投票する」(`inputBet`)

## パイプライン
```
today-picks.ps1 -ExportBets bets.csv   # 買い目(軸+相手4頭)をCSV出力
        │
        ▼
RakutenVote bets.csv --mode DryRun      # 買い目プレビュー(無投票)
RakutenVote bets.csv --mode ConfirmStop # 購入確定ボタン直前で停止(人が最終確認)
RakutenVote bets.csv --mode Auto        # 購入確定まで自動(実課金)
```

## 安全策(既定で有効)
- **既定は DryRun**(ブラウザを起動せず買い目と総額をログ表示のみ)。
- **認証情報は環境変数** `RAKUTEN_USER` / `RAKUTEN_PASS`(設定ファイルに書かない)。
- **1日上限額ガード** `DailyBudgetYen`(超過レースはスキップ)。`MaxRaces` でレース数制限。
- **RACEIDは当日一覧ページから実取得**(自前生成しない=誤レース投票を防ぐ)。
- **Auto は対話端末で `YES` 入力を要求**。`ConfirmStop` はレースごとに人の確認を挟む。

## 設定 `rakuten.json`
- `Mode` / `StakePerPointYen`(1点) / `PartnerCount`(相手頭数) / `DailyBudgetYen` / `Venues` など。
- `Selectors` … **★要実機確認★** `bet_lite` の購入フォームは**ログイン後のDOM**。
  まず `--mode DryRun` で買い目を確認し、次に **ConfirmStop** で実サイトを開いて
  各セレクタ(券種=3連単/方式=マルチ/軸・相手チェック/金額/確認/購入)を実DOMに合わせて調整すること。

## 使用例
```powershell
# 1) 当日の買い目を出力(高知のみ、相手4頭)
.\tools\today-picks.ps1 -Date 2026-06-14 -Venue 高知 -ExportBets .\bets.csv -PartnerCount 4

# 2) まずDryRunで内容と総額を確認
dotnet .\RakutenVote\bin\Debug\net10.0\RakutenVote.dll .\bets.csv --mode DryRun --date 2026-06-14

# 3) 環境変数に認証情報を入れて購入直前まで(人が最終確認)
$env:RAKUTEN_USER='xxxx'; $env:RAKUTEN_PASS='yyyy'
dotnet .\RakutenVote\bin\Debug\net10.0\RakutenVote.dll .\bets.csv --mode ConfirmStop
```

## 運用パターンB: 入金は手動・投票は無人(推奨)
お金を入れる判断だけ人が持ち、投票は自動化する安全な運用。
- **入金**: 人の目があるときに `deposit --mode ConfirmStop`(確認画面で人が「入金する」)でまとめて補充。
- **投票**: `--mode Auto` で無人実行。ログイン後に**残高(購入限度額)を読み**、
  **実効予算 = min(DailyBudgetYen, 残高)** で投票するため、**残高を超えて賭けない**(無人でも安全)。
  残高 < 本日予定なら警告を出す(補充タイミングが分かる)。
- 残高セレクタ `Selectors.BalanceText`。投票は1日上限+残高の二重ガード。

## 残高照会
ログインしてヘッダの「購入限度額」を読み取る(暗証番号不要・読み取り専用)。
```powershell
$env:RAKUTEN_USER='xxxx'; $env:RAKUTEN_PASS='yyyy'
dotnet .\RakutenVote\bin\Debug\net10.0\RakutenVote.dll balance
# → 購入限度額(残高) = 10,070円
```
- 残高セレクタ `Selectors.BalanceText`(TOP/照会/bet_lite いずれのヘッダでも拾えるよう複数指定)。
- **暗証番号(`--pin` か 環境変数 `RAKUTEN_PIN`)を渡すと内訳まで取得**(/reference の残高照会):
  当日入金・チャージ額合計 / 当日購入金額 / 当日払戻・返還額 / 購入限度額 / 購入可能件数・回数 等。
  ```powershell
  $env:RAKUTEN_PIN='1234'
  dotnet .\RakutenVote\bin\Debug\net10.0\RakutenVote.dll balance --pin 1234
  ```
  暗証番号が無ければヘッダの購入限度額のみ取得。`Reference.Selectors` で項目を解析(`.balancePointInfo__list`)。

## 入金(楽天銀行)
当日買い目の必要額(投票合計 − 現在残高)を自動計算し、入金画面で金額入力 → 確認画面で停止。
**「入金する」は人が押す**(Autoは作らない=お金が動く最終クリックは人の手に残す)。

```powershell
# 必要額の計算だけ(無起動)
dotnet .\RakutenVote\bin\Debug\net10.0\RakutenVote.dll deposit .\bets.csv --mode DryRun --date 2026-06-17
# 入金画面で金額入力→確認画面で停止(人が暗証番号入力＋「入金する」)
$env:RAKUTEN_USER='xxxx'; $env:RAKUTEN_PASS='yyyy'
dotnet .\RakutenVote\bin\Debug\net10.0\RakutenVote.dll deposit .\bets.csv --mode ConfirmStop --date 2026-06-17
```
- 必要額 = `投票合計(予算ガード適用後) + BufferYen − 残高`、100円単位に切り上げ。≤0なら入金不要。
- `rakuten.json` の `Deposit`: `BufferYen`(余裕) / `MaxDepositYen`(誤計算ガード) / `Selectors`。
- フロー: `/bank/deposit` → 方法=楽天銀行(`select#select`) → 金額(`#transactionAmountInput`、100円単位) → 「確認する」 → 確認画面で停止。

## 実機で確認・調整が要る点(残リスク)
- **2段階認証/CAPTCHA**: 楽天IDログインで出る場合がある。`ManualLoginAssistSeconds` の間に人が手動操作すれば継続。
- **投票完了文言**(`CompletedText`、既定「投票が完了」)は投票完了画面で要確認。Auto時は投票後に履歴で要確認。
- **入金残高**: 投票Liteは事前入金が必要(残高不足だと確認画面でエラー)。
- **楽天競馬の利用規約**で自動投票が許容されるかは要確認(自己責任)。

確認画面が安全網: ConfirmStop はここで停止し、「三連単 1流マ / 1着:N 相手:… / 各100円 計X円」が
表示された状態で人が「投票する」を押す。DryRunはブラウザ無しで買い目・総額のみ検証。
