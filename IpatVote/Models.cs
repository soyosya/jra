namespace 中央競馬.IpatVote;

public enum BetMode { DryRun, ConfirmStop, Auto }
public enum BetResult { Planned, Purchased, StoppedForConfirm, Closed, Failed }
public enum RaceSelect { Clicked, Closed, NotFound }   // レース番号ボタン選択の結果(Closed=締切表示/NotFound=リンクなし→いずれも投票中止)
public enum DepositResult { Skipped, Planned, StoppedForConfirm, Done, Failed }

/// <summary>ipat.json の IpatVote セクション。RakutenOptions相当。</summary>
public sealed class IpatOptions
{
    public string Mode { get; set; } = "DryRun";
    public string BetType { get; set; } = "三連複";     // 単勝/複勝/馬連/馬単/ワイド/三連複/三連単
    public string Method { get; set; } = "流し";         // 通常/流し/ボックス/フォーメーション
    public int PartnerCount { get; set; } = 4;
    public string ModeLabel { get; set; } = "";          // 投票履歴.取得元 上書き(/buyme手動='手動'・空=IpatVote)。ランナーAuto収支と区別
    public int StakePerPointYen { get; set; } = 100;
    public int DailyBudgetYen { get; set; } = 20000;
    public int MaxRaces { get; set; } = 0;
    public List<string> Venues { get; set; } = new();
    public bool Headless { get; set; } = false;
    public int ManualLoginAssistSeconds { get; set; } = 120;
    public int ConfirmWaitSeconds { get; set; } = 180;
    public string CompletedText { get; set; } = "投票を受け付けました|受付番号|投票完了";
    public string AcceptedText { get; set; } = "受け付けました";   // 投票成立の主判定=完了画面の受付メッセージ(「(お客様の投票を)受け付けました」)。受付番号regexより堅牢([[jra-ipat-vote]] 2026-07-05)
    public string ClosedText { get; set; } = "発売を締め切|締め切られて|投票可能な投票内容が(?:無|な)い";  // ★カート(購入予定リスト)段階の締切=「※投票可能な投票内容が無いため、投票できません。」も含む(選択後に締切ったケース)。固有文言に限定し誤中止を回避
    public IpatUrls Urls { get; set; } = new();
    public IpatSelectors Selectors { get; set; } = new();
    public IpatDeposit Deposit { get; set; } = new();

    public BetMode ResolvedMode => Mode?.Trim().ToLowerInvariant() switch
    {
        "auto" => BetMode.Auto,
        "confirmstop" or "confirm" => BetMode.ConfirmStop,
        _ => BetMode.DryRun
    };
}

public sealed class IpatUrls
{
    // ★IPAT(即PAT)実URL。会員トップ。投票/照会は同サイト内遷移。
    public string Top { get; set; } = "https://www.ipat.jra.go.jp/";
}

/// <summary>IPATの実DOMセレクタ。★は実機ログイン後に較正して埋める(現状はプレースホルダ)。</summary>
public sealed class IpatSelectors
{
    // --- ログイン(INET-ID → 加入者番号/暗証番号/P-ARS番号) ---  ★要較正
    public string LoginInetIdInput { get; set; } = "TODO_INETID";
    public string LoginInetIdSubmit { get; set; } = "TODO_INETID_SUBMIT";
    public string LoginSubscriberInput { get; set; } = "TODO_SUBSCRIBER";   // 加入者番号
    public string LoginPinInput { get; set; } = "TODO_PIN";                 // 暗証番号
    public string LoginParsInput { get; set; } = "TODO_PARS";               // P-ARS番号
    public string LoginSubmit { get; set; } = "TODO_LOGIN_SUBMIT";
    public string LoggedInMarker { get; set; } = "TODO_MENU_MARKER";        // 投票メニュー等の存在確認

    // --- 残高(購入可能額/限度額) ---  ★要較正
    public string BalanceText { get; set; } = "TODO_BALANCE_TEXT";

    // --- 投票フォーム(通常投票) ---  ★要較正
    public string MenuNormalVote { get; set; } = "TODO_NORMAL_VOTE";
    public string SelRacecourse { get; set; } = "TODO_RACECOURSE";
    public string SelRaceNumber { get; set; } = "TODO_RACENUMBER";
    public string SelBetType { get; set; } = "TODO_BETTYPE";
    public string SelMethod { get; set; } = "TODO_METHOD";
    public string AxisInputTemplate { get; set; } = "TODO_AXIS_{UMA}";
    public string PartnerInputTemplate { get; set; } = "TODO_PARTNER_{UMA}";
    // 位置別入力(着順固定/フォーメーション/ながし軸相手)。IPAT通常投票は horse1_no/horse2_no/horse3_no で統一。
    // ながし軸=horse1_no(radio)、相手=horse2_no(checkbox)。通常の馬単/三連単やフォーメーションも同テンプレ。
    public string NagashiAxisTemplate { get; set; } = "input#horse1_no{UMA}";    // = 1着/軸列
    public string NagashiPartnerTemplate { get; set; } = "input#horse2_no{UMA}"; // = 2着/相手列
    public string Pos3Template { get; set; } = "input#horse3_no{UMA}";           // = 3着列(三連系フォーメーション/通常)
    public string MultiCheckbox { get; set; } = "input[ng-model=\"vm.bMulti\"]";
    public string SelectAllPartners { get; set; } = "button[ng-click=\"vm.selectAllOpponentHorse()\"]";
    public string AmountInput { get; set; } = "TODO_AMOUNT";
    public string SetButton { get; set; } = "TODO_SET";             // 「セット」
    public string PurchaseButton { get; set; } = "TODO_PURCHASE";   // 「入力終了(購入)」
    public string ConfirmAmountInput { get; set; } = "TODO_CONFIRM_AMOUNT"; // 合計金額の確認入力
    public string VoteSubmit { get; set; } = "TODO_VOTE_SUBMIT";    // 「購入する」(vm.clickPurchase)
    // 「購入する」後の確認ポップアップ「投票内容と金額を送信してもよろしいですか？」のOK=実際の課金発火。
    public string VoteConfirmOk { get; set; } = ".ipat-error-window button.btn-ok";
}

public sealed class IpatDeposit
{
    public string MenuDeposit { get; set; } = "TODO_DEPOSIT_MENU";   // ★入金ボタン(別窓で入金サイトを開く)
    public string AmountInput { get; set; } = "TODO_DEPOSIT_AMOUNT"; // 金額入力(NYUKIN)
    public string NextButton { get; set; } = "TODO_DEPOSIT_NEXT";    // 「次へ」(金額→確認)
    public string PinInput { get; set; } = "TODO_DEPOSIT_PIN";       // 確認画面の暗証番号(PASS_WORD)
    public string SubmitButton { get; set; } = "TODO_DEPOSIT_SUBMIT"; // 「実行」=★人が押す(自動では押さない)
    public string CompletedText { get; set; } = "入金指示完了|受付ID"; // 完了判定(人の実行後)
    public int BufferYen { get; set; } = 0;
    public int MaxDepositYen { get; set; } = 50000;
}

/// <summary>買い目1行(jra-card等のCSV出力)。</summary>
public sealed class BetTicket
{
    public string Date = "";
    public string Venue = "";
    public int Race;
    public string BetType = "";      // 空ならCLI/設定既定
    public string Method = "";
    public string AxisUma = "";
    public List<string> Axes = new();    // 複数軸(三連複軸2頭ながし/三連単 1・2着等の2着固定ながし)。axis列を|/-/空白で分割
    public List<string> Partners = new();
    public int StakeYen;             // 行ごとの一点金額(任意)
    public string Kumiban = "";      // 確定組番(任意)
    public bool Multi;               // 馬単/三連単のマルチ(ながし時のみ有効)
    public List<string> F1 = new();  // フォーメーション1着列(CSV列 f1)
    public List<string> F2 = new();  // フォーメーション2着列(CSV列 f2)
    public List<string> F3 = new();  // フォーメーション3着列(CSV列 f3・三連系のみ)
}
