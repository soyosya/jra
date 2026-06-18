// 役割: 楽天競馬 自動投票の入口。買い目CSV(today-picks.ps1 -ExportBets が出力)を読み、
//       危険ローテ除外つき軸 → 3連単マルチ(軸1相手N)で投票します。
// 使い方: RakutenVote <買い目CSV> [--mode DryRun|ConfirmStop|Auto] [--date yyyy-MM-dd]
// 安全策: 既定DryRun / 認証情報は環境変数 / 1日上限額ガード / RACEIDは実ページから取得。
using Microsoft.Extensions.Configuration;
using 中央競馬.RakutenVote;
using CommonLogger = 中央競馬.共通.Libraly.Logger;

var positional = args.Where(a => !a.StartsWith("--")).ToList();
string subcmd = positional.FirstOrDefault() ?? "";
bool isDeposit = subcmd == "deposit";   // 入金サブコマンド
bool isBalance = subcmd == "balance";   // 残高照会サブコマンド(読み取り専用)
string csvPath = (isDeposit ? positional.Skip(1).FirstOrDefault() : positional.FirstOrDefault()) ?? "";
string? modeOverride = GetOpt("--mode");
string dateOverride = GetOpt("--date") ?? DateTime.Today.ToString("yyyy-MM-dd");
int amountOverride = int.TryParse(GetOpt("--amount"), out var _amt) ? _amt : 0;  // 入金: 固定額(円)

// balance / 固定額入金 は買い目CSV不要。それ以外はCSV必須。
if (string.IsNullOrWhiteSpace(csvPath) && !isBalance && !(isDeposit && amountOverride > 0))
{
    Console.WriteLine("使い方:");
    Console.WriteLine("  投票: RakutenVote <買い目CSV> [--mode DryRun|ConfirmStop|Auto] [--date yyyy-MM-dd]");
    Console.WriteLine("  入金: RakutenVote deposit <買い目CSV> [--mode DryRun|ConfirmStop] [--date yyyy-MM-dd]");
    Console.WriteLine("  入金(固定額): RakutenVote deposit --amount 10000 [--mode ConfirmStop]");
    Console.WriteLine("  残高照会: RakutenVote balance");
    return 1;
}

// rakuten.json の RakutenVote セクションを読み込む
var cfg = new ConfigurationBuilder()
    .SetBasePath(AppContext.BaseDirectory)
    .AddJsonFile("rakuten.json", optional: false, reloadOnChange: false)
    .AddEnvironmentVariables()
    .Build();
var opt = cfg.GetSection("RakutenVote").Get<RakutenOptions>() ?? new RakutenOptions();
if (!string.IsNullOrWhiteSpace(modeOverride)) opt.Mode = modeOverride!;
// 券種/相手数/1日上限を CLI で上書き(3連複運用や両券種比較のため)
var betTypeOverride = GetOpt("--bettype"); if (!string.IsNullOrWhiteSpace(betTypeOverride)) opt.BetType = betTypeOverride!;
if (int.TryParse(GetOpt("--partners"), out var _pc) && _pc > 0) opt.PartnerCount = _pc;
if (int.TryParse(GetOpt("--budget"), out var _bud) && _bud > 0) opt.DailyBudgetYen = _bud;
if (int.TryParse(GetOpt("--confirm-wait"), out var _cw) && _cw > 0) opt.ConfirmWaitSeconds = _cw;

CommonLogger.Log($"=== RakutenVote 開始 verb={subcmd} mode={opt.ResolvedMode} date={dateOverride} csv={csvPath} ===", 1);

// ===== 残高照会(読み取り専用。ログインしてヘッダの購入限度額を読む。暗証番号不要) =====
if (isBalance)
{
    using var bsess = new RakutenSession(opt);
    if (!bsess.Login()) { Console.WriteLine("ログインに失敗。残高を取得できません(認証情報/2段階認証を確認)。"); return 1; }

    // 暗証番号(--pin か 環境変数 RAKUTEN_PIN)があれば照会で内訳取得。無ければヘッダの購入限度額のみ。
    string? pin = GetOpt("--pin") ?? 中央競馬.共通.Libraly.Secrets.RakutenPin;
    if (!string.IsNullOrWhiteSpace(pin))
    {
        var detail = new ReferencePage(opt, bsess).ReadDetailedBalance(pin!);
        if (detail.Count > 0)
        {
            Console.WriteLine("=== 残高・有効期限照会(投票資金情報) ===");
            foreach (var (label, value) in detail) Console.WriteLine($"  {label,-16} {value}");
            CommonLogger.Log($"=== 残高照会(内訳{detail.Count}項目) ===", 1);
            return 0;
        }
        Console.WriteLine("内訳照会に失敗(暗証番号/セレクタ確認)。ヘッダの購入限度額にフォールバック。");
    }

    int bal = bsess.ReadBalance(opt.Selectors.BalanceText);
    if (bal >= 0) Console.WriteLine($"購入限度額(残高) = {bal:N0}円");
    else Console.WriteLine("残高を読み取れませんでした(セレクタ要確認)。");
    CommonLogger.Log($"=== 残高照会 {bal}円 ===", 1);
    return bal >= 0 ? 0 : 1;
}

Console.WriteLine($"モード: {opt.ResolvedMode}  (DryRun=無投票 / ConfirmStop=購入直前停止 / Auto=実課金)");

// 買い目読み込み + 場フィルタ + 日付フィルタ(固定額入金時はCSV無しでも可)
var allBets = string.IsNullOrWhiteSpace(csvPath) ? new List<BetTicket>() : BetsLoader.Load(csvPath, opt.PartnerCount);
var bets = allBets
    .Where(b => string.IsNullOrEmpty(b.Date) || b.Date == dateOverride)
    .Where(b => opt.Venues.Count == 0 || opt.Venues.Contains(b.Venue))
    .ToList();
Console.WriteLine($"買い目: 全{allBets.Count}件 → 対象{bets.Count}件");
if (bets.Count == 0 && !(isDeposit && amountOverride > 0)) { CommonLogger.Log("対象の買い目がありません。", 1); return 0; }

// ===== 入金モード(楽天銀行・確認画面で停止。Autoは無し) =====
if (isDeposit)
{
    Console.WriteLine("=== 入金モード(楽天銀行・確認画面で停止) ===");
    using var dsess = new RakutenSession(opt);
    if (opt.ResolvedMode != BetMode.DryRun && !dsess.Login())
        CommonLogger.Log("ログイン失敗。入金できません(認証情報/2段階認証を確認)。", 1);
    var dp = new DepositPage(opt, dsess);
    var dres = dp.Run(bets, amountOverride, out int amt);
    Console.WriteLine($"入金結果: {dres}{(amt > 0 ? "  指示額 " + amt.ToString("N0") + "円" : "")}");
    if (dres == DepositResult.StoppedForConfirm)
        Console.WriteLine("→ 確認画面で内容を確認し、暗証番号(必要時)を入力のうえ『入金する』を押してください。");
    CommonLogger.Log($"=== RakutenVote 入金終了 {dres} {amt:N0}円 ===", 1);
    return 0;
}

// 予定総額の事前提示(安全確認)
int ptsPerRace = opt.IsSanrenpuku ? opt.PartnerCount * (opt.PartnerCount - 1) / 2 : 3 * opt.PartnerCount * (opt.PartnerCount - 1);
int plannedPerRace = ptsPerRace * opt.StakePerPointYen;
Console.WriteLine($"1レースあたり {ptsPerRace}点 × {opt.StakePerPointYen}円 = {plannedPerRace:N0}円 ({(opt.IsSanrenpuku ? $"三連複 軸1相手{opt.PartnerCount}" : $"三連単マルチ 軸1相手{opt.PartnerCount}")})");
Console.WriteLine($"上限: 1日 {opt.DailyBudgetYen:N0}円 / 最大{(opt.MaxRaces == 0 ? "無制限" : opt.MaxRaces + "レース")}");

// Auto は実課金のため、対話端末では最終確認を要求(非対話時はスキップ)
if (opt.ResolvedMode == BetMode.Auto && !Console.IsInputRedirected)
{
    Console.Write("【警告】Autoは実際に課金されます。続行するには 'YES' と入力: ");
    if (Console.ReadLine()?.Trim() != "YES") { Console.WriteLine("中止しました。"); return 0; }
}

using var sess = new RakutenSession(opt);
bool needBrowser = opt.ResolvedMode != BetMode.DryRun;

// DryRun はブラウザを起動せず買い目プレビューのみ(高速・無投票)。実投票時のみログイン。
if (needBrowser && !sess.Login())
    CommonLogger.Log("ログインに失敗。投票はスキップされる可能性があります(認証情報/2段階認証を確認)。", 1);
var page = new BettingPage(opt, sess);

// 残高チェック(B運用: 入金は手動・投票は無人)。実効予算 = min(DailyBudget, 残高) で残高超えを防ぐ。
int effectiveBudget = opt.DailyBudgetYen;
if (needBrowser)
{
    int bal = sess.ReadBalance(opt.Selectors.BalanceText);
    int plannedTotal = DepositPage.ComputePlannedTotal(bets, opt);
    if (bal >= 0)
    {
        effectiveBudget = Math.Min(opt.DailyBudgetYen, bal);
        Console.WriteLine($"残高(購入限度額) = {bal:N0}円 / 本日予定 = {plannedTotal:N0}円 / 実効予算 = {effectiveBudget:N0}円");
        if (bal < plannedTotal)
            Console.WriteLine($"  [残高不足] 不足 {plannedTotal - bal:N0}円。入金で補充してください(B運用: 入金は手動)。残高内のみ投票します。");
        if (bal <= 0)
            Console.WriteLine("  [残高0] 投票できる残高がありません。補充してください。");
    }
    else { Console.WriteLine("残高を読み取れませんでした(セレクタ要確認)。DailyBudgetで続行。"); }
}

int spentTotal = 0, placed = 0, races = 0;
var summary = new List<string>();
var history = new VoteHistoryStore();   // 投票有無に関わらず買い目を記録(ベストエフォート)
foreach (var b in bets)
{
    if (opt.MaxRaces > 0 && races >= opt.MaxRaces) { Console.WriteLine("MaxRaces到達で打ち切り。"); break; }

    int per = (opt.IsSanrenpuku ? b.PointCountFuku : b.PointCount) * opt.StakePerPointYen;
    if (spentTotal + per > effectiveBudget)
    {
        CommonLogger.Log($"[予算/残高超過でスキップ] {b.Venue}{b.Race}R 予定{per:N0}円 (累計{spentTotal:N0}+{per:N0} > 実効予算{effectiveBudget:N0})", 1);
        summary.Add($"  {b.Venue}{b.Race}R: 予算/残高超過スキップ");
        history.Save(b, opt, "予算超過見送り", per);   // 買わなくても買い目は残す
        continue;
    }

    var result = page.PlaceBet(b, out int spent);
    races++;

    // ConfirmStop: 確認画面で停止後、ブラウザを開いたまま人が『投票する』を押すのを待つ。
    // Console.ReadLine に依存せずページの完了表示を監視するため、無人ランナーから子プロセスとして
    // 起動されても(=対話的な標準入力が無くても)ブラウザを閉じずに確認できる。
    if (opt.ResolvedMode == BetMode.ConfirmStop && result == BetResult.StoppedForConfirm)
    {
        Console.WriteLine($"  {b.Venue}{b.Race}R 確認画面で停止。ブラウザで内容を確認し『投票する』を押してください(最大{opt.ConfirmWaitSeconds}秒待機)。");
        bool done = sess.WaitForVoteCompleted(opt.CompletedText, opt.ConfirmWaitSeconds);
        if (done)
        {
            result = BetResult.Purchased;
            Console.WriteLine($"  → 投票完了を検知しました({spent:N0}円)。次のレースへ進みます。");
            CommonLogger.Log($"  [確認後完了] {b.Venue}{b.Race}R {spent:N0}円", 1);
        }
        else
        {
            Console.WriteLine($"  → 時間内に『投票する』が押されませんでした。このレースは見送ります。");
            CommonLogger.Log($"  [確認タイムアウト=見送り] {b.Venue}{b.Race}R", 1);
        }
    }

    if (result is BetResult.Purchased or BetResult.Planned)
    {
        spentTotal += spent; placed++;
        summary.Add($"  {b.Venue}{b.Race}R: {result} {spent:N0}円 (軸{b.AxisUma} 相手[{string.Join(",", b.Partners)}])");
    }
    else if (result == BetResult.StoppedForConfirm)
    {
        summary.Add($"  {b.Venue}{b.Race}R: 確認停止のまま未投票(見送り)");
    }
    else if (result == BetResult.Closed)
    {
        summary.Add($"  {b.Venue}{b.Race}R: 発売締切で投票中断(締切)");
    }
    else
    {
        summary.Add($"  {b.Venue}{b.Race}R: {result}");
    }

    // 投票有無に関わらず買い目を履歴に残す(計画/投票完了/見送り/締切/失敗)
    string histLabel = result switch
    {
        BetResult.Purchased => "投票完了",
        BetResult.Planned => "計画",
        BetResult.StoppedForConfirm => "見送り",
        BetResult.Closed => "締切",
        _ => "失敗"
    };
    history.Save(b, opt, histLabel, spent);
}

Console.WriteLine("\n===== 結果 =====");
summary.ForEach(Console.WriteLine);
string verb = opt.ResolvedMode switch
{
    BetMode.Auto => "投票(実課金)",
    BetMode.ConfirmStop => "購入直前まで準備",
    _ => "計画(無投票)"
};
Console.WriteLine($"{verb}: {placed}レース / 合計 {spentTotal:N0}円");
CommonLogger.Log($"=== RakutenVote 終了 {verb} {placed}レース {spentTotal:N0}円 ===", 1);
return 0;

string? GetOpt(string name)
{
    var i = Array.IndexOf(args, name);
    return (i >= 0 && i + 1 < args.Length) ? args[i + 1] : null;
}
