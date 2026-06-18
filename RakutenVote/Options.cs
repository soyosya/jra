// 役割: rakuten.json の RakutenVote セクションを束ねる設定クラスです。
// 認証情報(ID/PW)は設定ファイルに置かず、環境変数 RAKUTEN_USER / RAKUTEN_PASS から取得します。
namespace 中央競馬.RakutenVote
{
    /// <summary>投票の自動化レベル。</summary>
    public enum BetMode
    {
        /// <summary>画面遷移と買い目をログ出力するだけで投票はしない(無課金)。</summary>
        DryRun,
        /// <summary>購入確定ボタンの直前まで自動操作し、人が内容を確認してから手動でクリックする。</summary>
        ConfirmStop,
        /// <summary>購入確定まで無人で自動実行する(実際に課金される)。</summary>
        Auto
    }

    /// <summary>楽天競馬サイトのURL群。</summary>
    public sealed class RakutenUrls
    {
        public string BetLite { get; set; } = "";   // 投票Lite
    }

    /// <summary>投票Lite(bet_lite)のCSSセレクタ。</summary>
    public sealed class RakutenSelectors
    {
        public string LoginUserInput { get; set; } = "";
        public string LoginUserNext { get; set; } = "";
        public string LoginPassInput { get; set; } = "";
        public string LoginPassNext { get; set; } = "";
        public string LoggedInMarker { get; set; } = "";
        public string SelRacecourse { get; set; } = "";
        public string SelRaceNumber { get; set; } = "";
        public string SelBetType { get; set; } = "";
        public string SelBetMode { get; set; } = "";
        public string SubmitSelect { get; set; } = "";
        public string AxisRadioTemplate { get; set; } = "";
        public string PartnerCheckTemplate { get; set; } = "";
        public string MultiCheckbox { get; set; } = "";
        public string AmountInput { get; set; } = "";
        public string SubmitConfirm { get; set; } = "";
        public string VerifyInput { get; set; } = "";
        public string VoteSubmit { get; set; } = "";
        public string BalanceText { get; set; } = "";
    }

    /// <summary>入金(楽天銀行)のセレクタ。</summary>
    public sealed class DepositSelectors
    {
        public string PopupCloseButton { get; set; } = "";
        public string PopupDontShowCheckbox { get; set; } = "";
        public string MethodSelect { get; set; } = "";
        public string AmountInput { get; set; } = "";
        public string ConfirmButton { get; set; } = "";
        public string ExecuteButton { get; set; } = "";
        public string BalanceText { get; set; } = "";
    }

    /// <summary>入金設定。</summary>
    public sealed class DepositOptions
    {
        public string Url { get; set; } = "";
        public int BufferYen { get; set; } = 0;
        public int MaxDepositYen { get; set; } = 50000;
        public string MethodValue { get; set; } = "rakutenBank";
        public DepositSelectors Selectors { get; set; } = new();
    }

    /// <summary>照会(残高・有効期限)のセレクタ。</summary>
    public sealed class ReferenceSelectors
    {
        public string PinInput { get; set; } = "";
        public string BalanceSubmit { get; set; } = "";
        public string BalanceTab { get; set; } = "";
        public string DetailList { get; set; } = "";
        public string ItemRow { get; set; } = "";
        public string ItemLabel { get; set; } = "";
        public string ItemValue { get; set; } = "";
    }

    /// <summary>照会設定。</summary>
    public sealed class ReferenceOptions
    {
        public string Url { get; set; } = "";
        public ReferenceSelectors Selectors { get; set; } = new();
    }

    /// <summary>RakutenVote セクション全体。</summary>
    public sealed class RakutenOptions
    {
        public string Mode { get; set; } = "DryRun";
        public string BetType { get; set; } = "SanrentanMulti";
        public int PartnerCount { get; set; } = 4;
        public int StakePerPointYen { get; set; } = 100;
        public int DailyBudgetYen { get; set; } = 20000;
        public int MaxRaces { get; set; } = 0;
        /// <summary>ConfirmStop で確認画面に停止後、人が『投票する』を押すのを待つ最大秒数。超過で見送り。</summary>
        public int ConfirmWaitSeconds { get; set; } = 180;
        public List<string> Venues { get; set; } = new();
        public bool Headless { get; set; } = false;
        public int ManualLoginAssistSeconds { get; set; } = 120;
        public string BetTypeValue { get; set; } = "9";   // 三連単
        public string BetModeValue { get; set; } = "32";  // 流し(三連単=1着流し / 三連複=軸1頭流し いずれも32)
        public string SanrenpukuBetTypeValue { get; set; } = "8";  // 三連複
        public string CompletedText { get; set; } = "受け付けました|投票完了|受付番号";
        /// <summary>発売締切メッセージの判定文言(レース選択画面)。検出時は投票を中断し履歴に「締切」を残す。</summary>
        public string ClosedText { get; set; } = "発売を締め切";

        /// <summary>3連複(軸1頭流し)モードか。BetType に "Sanrenpuku"/"3puku"/"三連複" を含むと真。</summary>
        public bool IsSanrenpuku =>
            !string.IsNullOrEmpty(BetType) &&
            (BetType.IndexOf("Sanrenpuku", StringComparison.OrdinalIgnoreCase) >= 0
             || BetType.IndexOf("3puku", StringComparison.OrdinalIgnoreCase) >= 0
             || BetType.Contains("三連複"));
        public RakutenUrls Urls { get; set; } = new();
        public RakutenSelectors Selectors { get; set; } = new();
        public DepositOptions Deposit { get; set; } = new();
        public ReferenceOptions Reference { get; set; } = new();

        /// <summary>文字列の Mode を列挙体へ。未知の値は安全側の DryRun。</summary>
        public BetMode ResolvedMode =>
            Enum.TryParse<BetMode>(Mode, ignoreCase: true, out var m) ? m : BetMode.DryRun;

        /// <summary>楽天ID。secrets.local.json(RakutenUser)→環境変数RAKUTEN_USER の順。未設定なら null。</summary>
        public static string? UserId => 中央競馬.共通.Libraly.Secrets.RakutenUser;
        /// <summary>楽天パスワード。secrets.local.json(RakutenPass)→環境変数RAKUTEN_PASS の順。未設定なら null。</summary>
        public static string? Password => 中央競馬.共通.Libraly.Secrets.RakutenPass;
    }
}
