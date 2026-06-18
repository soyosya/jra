---
name: rakuten-vote
description: 楽天競馬 自動投票プロジェクト(RakutenVote)の設計・安全策・未確定事項
metadata: 
  node_type: memory
  type: project
  originSessionId: 2905a192-d835-480b-910b-6672a8227f1c
---

# 楽天競馬 自動投票(RakutenVote)

[[keiba-rating-system]] の買い目を楽天競馬へ自動投票する新規C#プロジェクト(.NET10、共通/Selenium参照)。リポジトリ直下 `RakutenVote/`。

## パイプライン
`tools/today-picks.ps1 -ExportBets bets.csv -PartnerCount 4`(危険ローテ除外つき軸+rating上位相手を買い目CSV出力)→ `RakutenVote bets.csv --mode <Mode>`。
- 券種は **3連単マルチ(軸1頭・相手N頭流し)** = 3×N×(N-1)点。相手4頭で36点。
- 軸は▼ローテ(前6着×中3週以内続戦)を**除外**して選定。today-picksの画面◎は減点込みtopなのでCSV軸と異なる事がある(CSVが投票用)。

## モード(rakuten.json の Mode / --mode で上書き)
- `DryRun`(既定): ブラウザ起動せず買い目と総額をログのみ=無投票。検証用。
- `ConfirmStop`: 購入確定ボタン直前で停止。**(2026-06-18変更)Console.ReadLine待ちを廃止し、ブラウザを開いたまま「投票が完了」表示をポーリング監視**(`RakutenSession.WaitForVoteCompleted`、`ConfirmWaitSeconds`既定180秒/`--confirm-wait`)。子プロセス(ランナー)起動でもブラウザが閉じず、人はブラウザで『投票する』を押すだけ=ターミナル操作不要。超過で見送り。**旧Enter方式はランナー経由だと子プロセスstdinがEOFで即閉じ→確認不能だった**ため変更。
- `Auto`: 購入確定まで自動=**実課金**。対話端末では `YES` 入力を要求(`!Console.IsInputRedirected`時)。**ランナー経由はstdinがEOF=YESに答えられず必ず中止**(=無人実課金の安全弁。これは外さない方針)。
- **投票完了検知の文言修正(2026-06-18)**: 実完了画面は「投票が完了」ではなく**「…受け付けました」「投票Lite:投票完了」「受付番号」**。`CompletedText`を `受け付けました|投票完了|受付番号` の複数マーカー(|区切り,いずれか一致)化(Options/rakuten.json/WaitForVoteCompleted/BettingPage Auto)。旧文言だと押下を検知できず最大180秒待ち→誤「見送り」記録になっていた(実際は投票完了済)バグを修正。
- **発売締切の検知・中断(2026-06-18)**: レース選択画面の「そのレースは発売を締め切っています」を `ClosedText`('発売を締め切')で検知。BettingPage.PlaceBet が GoToBetLite直後/競馬場選択失敗時/買い目選択遷移失敗時に判定し、検出時は投票せず `BetResult.Closed`。Program は 結果='締切' で投票履歴に記録(would-be金額、placed/spent非計上)。締切に間に合わなかったレースは投票履歴の結果='締切'で判別可能。
- **遅延解消=先行分析方式(A, 2026-06-18)**: compi-auto-vote.ps1 は起動時に全場を blend(-ExportAll)で**1回だけ先行分析**しキャッシュ(Build-Plan)。買い目はライブオッズ非依存のため**T-5は再分析もfetch-oddsもせず投票のみ**=毎レース~30秒の重処理を排除しT-5トリガに間に合う。プラン未登録は当該場のみその場再分析(保険)。旧版は毎レースblend+fetch-odds+ConfirmStop180秒待ちで詰まり、T-5を逃す/発走済みスキップが発生していた。

## 安全策
- 認証情報は **git追跡外 `secrets.local.json`(`共通/Libraly/Secrets.cs`、リポジトリ直下を上位探索)→環境変数 `RAKUTEN_USER`/`RAKUTEN_PASS`** の順。キー: RakutenUser/RakutenPass/RakutenPin/GokuUmaUser/GokuUmaPass。テンプレ=secrets.local.example.json。Options.UserId/Password と Program.cs のPINがSecrets経由。**appsettings.jsonのsa接続文字列は依然git追跡=要対処(残課題)**。
- `DailyBudgetYen` 上限ガード(超過レースはスキップ)、`MaxRaces`、`Venues` フィルタ、`StakePerPointYen`。
- **RACEIDは当日 race_card 一覧から実取得**(自前生成しない=誤レース投票防止)。RACEID末尾2桁=レース番号は実データで確認済。

## 投票フロー(実DOM 2026-06提供に基づき実装済)=投票Lite bet_lite
**通常投票(/bet/normal)はSPAで脆い→投票Lite(プレーンHTMLフォーム)に変更。** https://bet.keiba.rakuten.co.jp/bet_lite
- ログイン(楽天ID Omniウィジェット): ID `#user_id`→次へ `#cta001`→PW `#password_current`→次へ `#cta011`。ログイン済marker=`select[name=racecourseId]`。
- レース選択フォーム: `select[name=racecourseId]`(競馬場、option textで選択)/`raceNumber`/`betType`=9(三連単,複=8/馬単=6/馬複=5/ワイド=7/単=1/複=2)/`betMode`=32(流し)→ `input[name=select]`。
- 買い目選択: 軸=`input[name="me1[]"][value=N]`(ラジオ)、相手=`input[name="me2[]"][value=N]`(チェック)、`input[name=isMulti]`、金額=`input[name=buyUnitCount]`(各N00円=StakePerPointYen/100)→ `input[name=confirm]`。流し種別select既定=1着流し(32)。
- 確認: `#cashConfirm`(name=cashConfirm)に合計額→ `input[name=inputBet]`「投票する」。確認画面に「三連単 1流マ / 1着:N 相手:… / 各100円 計X円」表示。
- 点数 3連単マルチ=3×N×(N-1)(相手3で18点を実DOMで確認)。trackcode参考: racecourseId option値=36門別/21川崎/24名古屋/27園田。

## 実運用メモ(2026-06-17)
- `rakuten.json` の `Venues` ホワイトリストに無い場は「全N件→対象0件」で除外される。門別が未登録だったため追加済([門別,高知,園田,大井,佐賀,川崎])。新規場を投票する時はここに追加。
- 設定は **exe のフォルダ(`AppContext.BaseDirectory`=`RakutenVote\bin\Debug\net10.0\rakuten.json`)から読む**。元ソースだけ直しても未ビルドだと効かない→bin側も直すか再ビルド。
- 締切後/発走済レースは bet_lite の競馬場selectに出ず `SelectByText` 失敗→Failed(園田11Rで実例)。発売中レースを対象にする。
- 実行: リポジトリ直下から `.\RakutenVote\bin\Debug\net10.0\RakutenVote.exe .\bets.csv --mode ConfirmStop --date YYYY-MM-DD`。空白パスはdll指定時クォート必須。

## 入金(deposit サブコマンド・2026-06-17実装)=楽天銀行
`RakutenVote deposit <bets.csv> --mode DryRun|ConfirmStop --date YYYY-MM-DD`。必要額=投票合計(予算ガード後)+BufferYen−残高、100円単位切上げ、≤0で不要。MaxDepositYenで誤計算ガード。**ConfirmStop止まり=「入金する」は人が押す(Autoは作らない)**。
- 入金画面 `/bank/deposit`(VueのSPA): 方法 `select#select`(value=rakutenBank/paypay/rakutenPoint、既定楽天銀行)/金額 `#transactionAmountInput`(**100円単位**=suffix「00」、入力値=円/100、max99900=999万)/「確認する」`form.transactionInput__main button[data-comp-id=actionButton_action]`(金額入力で有効化)。
- 確認画面: 「入金する」`form.transactionConfirm button[data-comp-id=actionButton_action]`。暗証番号は `#pinSwitch`「省略(当日のみ有効)」がONなら不要(=技術的にはAuto入金も可能だが安全のため未実装)。
- 残高=ヘッダ `.information-balance`(購入限度額)。Vue入力はネイティブsetter+inputイベントで反映(SetReactInput)。DryRunはブラウザ無しで投票合計のみ表示。
- ConfirmStopは実サイト確認済の投票フローと同セッション(同driver)でログイン状態共有。

## 運用パターンB(入金手動・投票無人)=採用方針
- **入金の全自動(無人で「入金する」クリック)は実装しない**。ハーネスの安全機構が無人送金実行をブロック+方針として送金の最終クリックは人に残す。入金はConfirmStop(確認画面で人が押す)で手動補充。
- **投票は無人(--mode Auto)**: ログイン後に残高(購入限度額)を `Selectors.BalanceText`(`#balanceStatus li.balance .amount`)で読み、**実効予算=min(DailyBudgetYen,残高)** で投票=残高超えを賭けない。残高<予定なら警告。RakutenSession.ReadBalance / DepositPage.ComputePlannedTotal を利用。
- 入金画面は説明ポップアップ(`.pointUsagePopup__action button`/`#agreementCheckbox`)を金額入力前に閉じる必要あり。楽天銀行入金は口座振替契約が前提(未設定ならポイント/PayPay)。

## 残高照会(balance サブコマンド)
- `RakutenVote balance`: ログイン→ヘッダの購入限度額(`.information-balance`)を読む。暗証番号不要・読み取り専用。投票フローの残高ガードと同じ値。
- `balance --pin 1234`(or 環境変数 `RAKUTEN_PIN`): /reference で暗証番号入力→`#balanceInquiry`送信→`.balancePointInfo__list` の各 `li`(`.k_listItemSubtitle`ラベル/`.balancePointInfo__property`値)を解析し内訳表示(当日入金・チャージ額合計/当日購入金額/当日払戻・返還額/購入限度額/購入可能件数・回数 等)。当日収支の把握に使える。ReferencePage.cs。

## 残リスク(実機要確認)
- 楽天ID 2段階認証/CAPTCHA(`ManualLoginAssistSeconds`で手動猶予)。投票完了文言(`CompletedText`既定「投票が完了」)未確認→Auto時は履歴確認。入金残高が必要。
- 楽天競馬の利用規約で自動投票が許容されるかは要確認。
- DryRunは上記に依存せず動作確認済(today-picks→CSV→計画、予算ガード、exit0)。

## コンピ3連複の自動投票(2026-06-18 実装・DryRun検証済/実課金未実行)
- **RakutenVote 3連複対応**: 楽天bet_lite 三連複=式別(betType)8、方式32(=軸1頭流し。三連単の流しと同値)、軸=me1[]ラジオ/相手=me2[]チェック(三連単と同じ)、マルチ無し、点数=C(相手,2)(相手3頭=3点=300円)。BettingPageに IsSanrenpuku 分岐+PointCountFuku、Program/DepositPageの予算/表示を券種別点数に修正。CLI上書き --bettype SanrenpukuNagashi --partners 3 --budget。rakuten.json Venues既定=空。
- **ブリッジ**: compi-today-blend.ps1 -ExportBets <csv> = date,venue,race,axis_uma,axis_name,p1..p4(軸+ブレンド相手上位4)→RakutenVoteが読む(PartnerCount=3で3連複/4で三連単)。
- **オーケストレータ tools/compi-auto-vote.ps1**: 当日メニュー発走時刻からT-Lead(5)分前に該当レースを fetch-odds→compi-today-blend(該当場)再分析→推奨なら1行CSVでRakutenVote起動。-Mode DryRun/ConfirmStop/Auto -Budget -BetType -Partners。BOM必須。
- 検証: DryRunで6/18=7レース・各3点300円・合計2,100円(¥10,000内)・名古屋含む・h2h軸入替反映。**実課金未実行=ユーザが起動し最終クリック**。
- 未確認: 3連複の確認画面(cashConfirm/投票する)HTML未取得=三連単と同じ前提(ConfirmStopは確認画面で停止=人が確認)。楽天ログインは投票毎。初回ライブ要監視。ユーザ選択=3連複ライブ+三連単記録/ConfirmStop/¥10,000。

## 投票履歴の永続化(2026-06-18 実装・検証済)
- **投票有無に関わらず推奨買い目を記録**(ユーザ要望「投票しなくても買目を残す」)。テーブル `dbo.投票履歴`(投票日時/開催日/場名/レース番号/式別/軸馬番/相手馬番/点数/一点金額/投票金額/モード/結果/確定済/的中/払戻金/確定日時)。`tools/create-投票履歴-table.sql` に定義。
- 記録: `RakutenVote/VoteHistoryStore.cs`。appsettings.json(出力にコピー済)のDefaultConnectionでSqlClient直INSERT。**初回実行でテーブル自動作成(冪等)**。Program.cs が予算超過スキップ/本処理(計画/投票完了/見送り/失敗)すべてで Save。**ベストエフォート=DB障害でも投票は止めない**。Microsoft.Data.SqlClientは共通参照で推移利用。
- 精算 `tools/vote-settle.ps1`: 確定済=0行を 競走結果(着順上位3=top3)と払戻金で精算。的中=「軸∈top3 かつ 残り2頭⊆相手」(3連複/3連単マルチ共通=順不同)。払戻=払戻金.金額(100円あたり)×(一点金額/100)。モード問わず精算(計画/見送りも“買っていたら”検証)。-WhatIf あり。
- 集計 `tools/vote-report.ps1`: [実投票](結果=投票完了)と[全推奨](確定済全部=買っていたら)の的中率・回収率。-Date/-From/-To/-Venue。
- 罠: 払戻金.馬券 LIKE '%三連複%'、組番="2-9-13"昇順、金額=100円あたり。場名=競走結果.開催場所で結合。PS5.1は`??`不可→Nzヘルパ、BOM必須。
- 検証: 6/18園田8R(DryRun計画)を記録→精算で着順5-6-1=軸5相手6,1で三連複的中・払戻1100円(100円→×11)、回収率366.7%表示までOK。
- **推奨外レースも記録(2026-06-18・ライブ統合)**: ユーザ要望でフィルタ除外レースも検証用に記録。compi-today-blend に `-ExportAll`(全解析レース=推奨外含む、would-be買い目+eh/推奨(1/0)/頭数)。既定 -ExportBets(推奨のみ=投票用)は不変。compi-auto-vote が各レースT-5分で全解析CSVを見て、推奨→RakutenVote投票/推奨外→DB直記録(モード'分析'/結果'推奨外'、開催日+場名+R で重複スキップ、起動時テーブル保証)。vote-report は[実投票]/[推奨]/[推奨外]を分離表示。検証(園田6/18): 推奨外8確定/的中3(37.5%)/回収69.6% vs 推奨366.7%=フィルタ妥当。推奨外の式別/点数は$BetTypeに追従(三連複=C(P,2)/三連単=3P(P-1))、一点100円固定。頭数<5等で解析不能なレースは記録対象外。
- **過去日の一括記録バッチ tools/record-analysis.ps1(2026-06-18)**: 指定日/期間(-Date or -From/-To)の全解析レースを投票履歴へ一括記録(推奨=結果'計画'/推奨外=結果'推奨外'、モード'分析'、実投票なし=would-be)。開催日+場名+R で重複スキップ=ライブ記録保護。-Settle で各日精算まで。-Venue/FieldMax/EhMin/Partners/BetType 対応。検証(6/17園田)12レース記録→[推奨]40.0%/[推奨外]92.2%。※投票履歴テーブルは検証後TRUNCATEでクリーン化済(本番運用で蓄積開始)。
