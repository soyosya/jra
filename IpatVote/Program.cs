// 役割: JRA IPAT(即PAT) 自動投票/入金/残高/収支。RakutenVoteのJRA版。
// 使い方:
//   投票: IpatVote <買い目CSV> [--mode DryRun|ConfirmStop|Auto] [--date yyyy-MM-dd]
//   入金: IpatVote deposit [<買い目CSV>] [--amount 10000] [--mode DryRun|ConfirmStop]
//   残高: IpatVote balance
//   収支: IpatVote pl [--from yyyy-MM-dd] [--to yyyy-MM-dd]
// 安全策: 既定DryRun(無投票) / 認証は環境変数 or secrets.local.json / 1日上限ガード /
//         入金とAuto投票は「未較正(TODO)」の間は実行されない / ConfirmStopは人が最終操作。
using Microsoft.Extensions.Configuration;
using 中央競馬.IpatVote;

try { Console.OutputEncoding = System.Text.Encoding.UTF8; } catch { } // 日本語出力の文字化け防止(リダイレクト/各端末)

string? GetOpt(string name) { var i = Array.IndexOf(args, name); return (i >= 0 && i + 1 < args.Length) ? args[i + 1] : null; }
// 位置引数=オプション(--xxx)とその値を除いたトークン。全オプションは値を1つ取る前提でペアでスキップ。
var positional = new List<string>();
for (int ai = 0; ai < args.Length; ai++) { if (args[ai].StartsWith("--")) { ai++; continue; } positional.Add(args[ai]); }
string subcmd = positional.FirstOrDefault() ?? "";
bool isDeposit = subcmd == "deposit", isBalance = subcmd == "balance", isPl = subcmd == "pl";
bool isLive = subcmd == "live";   // ライブ中継(sp.gch.jp/jra)を専用プロファイルの可視Chromeで開く(窓使い回し): live [会場名]
string csvPath = (isDeposit ? positional.Skip(1).FirstOrDefault() : positional.FirstOrDefault()) ?? "";
string dateOverride = GetOpt("--date") ?? DateTime.Today.ToString("yyyy-MM-dd");
int amountOverride = int.TryParse(GetOpt("--amount"), out var _amt) ? _amt : 0;

var cfg = new ConfigurationBuilder().SetBasePath(AppContext.BaseDirectory)
    .AddJsonFile("ipat.json", optional: false).AddEnvironmentVariables().Build();
var opt = cfg.GetSection("IpatVote").Get<IpatOptions>() ?? new IpatOptions();
var modeOverride = GetOpt("--mode"); if (!string.IsNullOrWhiteSpace(modeOverride)) opt.Mode = modeOverride!;
if (!string.IsNullOrWhiteSpace(GetOpt("--bettype"))) opt.BetType = GetOpt("--bettype")!;
if (!string.IsNullOrWhiteSpace(GetOpt("--method"))) opt.Method = GetOpt("--method")!;
if (!string.IsNullOrWhiteSpace(GetOpt("--mode-label"))) opt.ModeLabel = GetOpt("--mode-label")!;   // C1: /buyme手動投票='手動'(ランナーAuto収支と区別)
if (int.TryParse(GetOpt("--partners"), out var _pc) && _pc > 0) opt.PartnerCount = _pc;
if (int.TryParse(GetOpt("--budget"), out var _bud) && _bud > 0) opt.DailyBudgetYen = _bud;
if (int.TryParse(GetOpt("--stake"), out var _sk) && _sk > 0) opt.StakePerPointYen = _sk;

// ===== 収支(読み取り専用・実金操作なし) =====
if (isPl)
{
    string f = GetOpt("--from") ?? new DateTime(DateTime.Today.Year, 1, 1).ToString("yyyy-MM-dd");
    string t = GetOpt("--to") ?? DateTime.Today.ToString("yyyy-MM-dd");
    try { Pnl.Report(f, t); return 0; } catch (Exception ex) { Console.WriteLine($"収支取得に失敗: {ex.Message}"); return 1; }
}

// ===== live(JRAライブ中継=グリーンチャンネルWeb sp.gch.jp/jra を専用プロファイルの可視Chromeで開く。窓は使い回し=リモートデバッグ再接続) =====
// ※実金操作なし(視聴のみ)。会場/画質の自動切替は sp.gch.jp/jra(有料・配信中のみプレーヤー描画)の実DOM調査後に追加。現状=URLを開いて再生のみのサイト非依存版。
if (isLive)
{
    string liveVenue = positional.Skip(1).FirstOrDefault() ?? "";
    const int dbgPort = 9334;                                  // 地方=9333と別(同一マシン同時起動の競合回避)
    const string liveProfile = @"C:\temp\jra-live-profile";    // 投票/地方とは別プロファイル(非競合)
    const string liveUrl = "https://sp.gch.jp/jra";
    System.IO.Directory.CreateDirectory(liveProfile);

    OpenQA.Selenium.Chrome.ChromeDriver? Attach()
    {
        try
        {
            var o = new OpenQA.Selenium.Chrome.ChromeOptions { DebuggerAddress = $"127.0.0.1:{dbgPort}" };
            var sv = OpenQA.Selenium.Chrome.ChromeDriverService.CreateDefaultService();
            sv.HideCommandPromptWindow = true;
            return new OpenQA.Selenium.Chrome.ChromeDriver(sv, o, TimeSpan.FromSeconds(20));
        }
        catch { return null; }
    }

    var drv = Attach();   // 既存のライブ窓に再接続(使い回し)
    if (drv != null) { try { if (drv.WindowHandles.Count == 0) { drv.Dispose(); drv = null; } } catch { try { drv.Dispose(); } catch { } drv = null; } }  // 窓が閉じられていたら破棄→新規
    bool launched = false;
    if (drv == null)
    {
        string chrome = new[] {
            @"C:\Program Files\Google\Chrome\Application\chrome.exe",
            @"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" }
            .FirstOrDefault(System.IO.File.Exists) ?? "chrome.exe";
        var psi = new System.Diagnostics.ProcessStartInfo(chrome) { UseShellExecute = true };
        psi.ArgumentList.Add($"--remote-debugging-port={dbgPort}");
        psi.ArgumentList.Add($"--user-data-dir={liveProfile}");
        psi.ArgumentList.Add("--autoplay-policy=no-user-gesture-required");   // ▶クリック不要で自動再生を許可(サイト非依存で有効)
        psi.ArgumentList.Add("--new-window");
        psi.ArgumentList.Add(liveUrl);
        try { System.Diagnostics.Process.Start(psi); } catch (Exception ex) { Console.WriteLine($"Chrome起動失敗: {ex.Message}"); return 1; }
        launched = true;
        for (int i = 0; i < 25 && drv == null; i++) { System.Threading.Thread.Sleep(700); drv = Attach(); }
    }
    if (drv == null) { Console.WriteLine($"ライブ用Chromeに接続できませんでした(port={dbgPort})。"); return 1; }

    try
    {
        if (launched) System.Threading.Thread.Sleep(2500);
        string cur = ""; try { cur = drv.Url ?? ""; } catch { }
        if (!cur.Contains("gch.jp")) { try { drv.Navigate().GoToUrl(liveUrl); System.Threading.Thread.Sleep(2500); } catch { } }
        var js = (OpenQA.Selenium.IJavaScriptExecutor)drv;
        // 会場/画質切替は gch.jp の実プレーヤーDOM(有料ログイン+配信中のみ描画)を調査後に追加。現状は再生のみ(サイト非依存)。
        var play = js.ExecuteScript(@"
function play(){
  var v=document.querySelector('video');
  if(!v) return 'NO_VIDEO(未ログイン/配信外でプレーヤー未描画の可能性=この窓でグリーンチャンネル会員ログインを)';
  try{
    var pr=v.play();   // --autoplay-policy=no-user-gesture-required 起動なら音声付きで再生
    if(pr&&pr.catch){ pr.catch(function(){ try{ v.muted=true; v.play(); }catch(e){} }); }  // 失敗時はミュート再生
    return 'play paused='+v.paused;
  }catch(e){ try{ v.muted=true; v.play(); return 'play-muted'; }catch(e2){ return 'play-err:'+e2; } }
}
try{return play();}catch(e){return 'ERR:'+e;}
");
        Console.WriteLine($"JRAライブ(sp.gch.jp/jra) 起動{(string.IsNullOrWhiteSpace(liveVenue) ? "" : " 会場指定=" + liveVenue + "(切替は未実装)")} / 再生: {play} (port={dbgPort})");
        Console.WriteLine("※会場/画質の自動切替はgch.jpプレーヤーDOM調査後に対応予定。初回はこの窓でグリーンチャンネル会員ログインを(プロファイルに保持)。");
    }
    catch (Exception ex) { Console.WriteLine($"ライブ操作エラー: {ex.Message}"); }
    finally { try { drv.Quit(); } catch { } }   // attachのQuitは外部Chromeを閉じずchromedriver.exeのみ掃除(窓は使い回せる)。省くとchromedriver漏れ
    return 0;
}

if (string.IsNullOrWhiteSpace(csvPath) && !isBalance && !isLive && !(isDeposit && amountOverride > 0))
{
    Console.WriteLine("使い方:\n  投票: IpatVote <買い目CSV> [--mode DryRun|ConfirmStop|Auto]\n  入金: IpatVote deposit [<CSV>] [--amount N]\n  残高: IpatVote balance\n  収支: IpatVote pl [--from][--to]");
    return 1;
}

Log.Line($"=== IpatVote 開始 verb={(subcmd == "" ? "vote" : subcmd)} mode={opt.ResolvedMode} date={dateOverride} ===");

// ===== 残高(読み取り専用) =====
if (isBalance)
{
    using var bs = new IpatSession(opt);
    if (!bs.Login()) { Console.WriteLine("ログイン不可のため残高を取得できません(未較正/認証情報/2段階認証)。"); Log.Line("balance: ログイン不可で中断。"); return 1; }
    int bal = bs.ReadBalance(opt.Selectors.BalanceText);
    var msg = bal >= 0 ? $"購入可能額(残高) = {bal:N0}円" : "残高を読み取れませんでした(BalanceTextセレクタ較正要・ログインは成功)。";
    Console.WriteLine(msg); Log.Line("balance: " + msg);
    return bal >= 0 ? 0 : 1;
}

Console.WriteLine($"モード: {opt.ResolvedMode} (DryRun=無投票 / ConfirmStop=確認停止で人が最終操作 / Auto=実課金)");
// CSVの相手は買目生成側(jra-export-bets -Partners)で確定済→全て使う(opt.PartnerCountで切詰めない)。
var allBets = string.IsNullOrWhiteSpace(csvPath) ? new List<BetTicket>() : BetsLoader.Load(csvPath, 99);
var bets = allBets.Where(b => string.IsNullOrEmpty(b.Date) || b.Date == dateOverride)
                  .Where(b => opt.Venues.Count == 0 || opt.Venues.Contains(b.Venue)).ToList();
Console.WriteLine($"買い目: 全{allBets.Count}件 → 対象{bets.Count}件");

// ===== 入金(確認停止・Autoなし) =====
if (isDeposit)
{
    Console.WriteLine("=== 入金(確認画面の『入金する』直前で停止) ===");
    using var ds = new IpatSession(opt);
    if (opt.ResolvedMode != BetMode.DryRun && !ds.Login()) Log.Line("ログイン不可。入金は実行されません。");
    var dres = new DepositPage(opt, ds).Run(bets, amountOverride, out int amt);
    Console.WriteLine($"入金結果: {dres}{(amt > 0 ? "  指示額 " + amt.ToString("N0") + "円" : "")}");
    if (dres == DepositResult.StoppedForConfirm)
    {
        // ブラウザ(別窓の確認画面)を開いたまま、人が【実行】+確認OKを押して完了するのを待つ(完了検知で即終了)
        Console.WriteLine($"→ 別窓の確認画面で金額・暗証を確認し【実行】→『入金します。よろしいですか？』OKを押してください(最大{opt.ConfirmWaitSeconds}秒待機)。");
        if (ds.WaitForVoteCompleted(opt.Deposit.CompletedText, opt.ConfirmWaitSeconds))
            { Console.WriteLine("入金指示完了を確認しました。"); Log.Line("deposit: 入金指示完了を確認。"); }
        else
            { Console.WriteLine("完了表示を確認できませんでした(時間切れ/未実行/別窓を閉じた)。"); Log.Line("deposit: 完了未確認で終了。"); }
    }
    return 0;
}

if (bets.Count == 0) { Console.WriteLine("対象の買い目がありません。"); return 0; }

// 予定総額の提示
int planned = DepositPage.ComputePlannedTotal(bets, opt);
Console.WriteLine($"本日予定 = {planned:N0}円 / 上限 1日 {opt.DailyBudgetYen:N0}円 / 最大{(opt.MaxRaces == 0 ? "無制限" : opt.MaxRaces + "R")}");

using var sess = new IpatSession(opt);
bool needBrowser = opt.ResolvedMode != BetMode.DryRun;
if (needBrowser && !sess.Login()) Log.Line("ログイン未確認。投票はスキップされる可能性(未較正/認証/2段階認証)。");

int effBudget = opt.DailyBudgetYen;
if (needBrowser)
{
    int bal = sess.ReadBalance(opt.Selectors.BalanceText);
    if (bal >= 0) { effBudget = Math.Min(opt.DailyBudgetYen, bal); Console.WriteLine($"残高 {bal:N0}円 / 実効予算 {effBudget:N0}円"); }
}

int spentTotal = 0, placed = 0, races = 0;
var summary = new List<string>(); var history = new VoteHistory();
var page = new BettingPage(opt, sess);
foreach (var b in bets)
{
    if (opt.MaxRaces > 0 && races >= opt.MaxRaces) { Console.WriteLine("MaxRaces到達。"); break; }
    if (b.StakeYen > 0) opt.StakePerPointYen = Math.Max(100, b.StakeYen / 100 * 100);
    int pts = Points.ForTicket(b, opt); int per = pts * opt.StakePerPointYen;
    var bt = string.IsNullOrWhiteSpace(b.BetType) ? opt.BetType : b.BetType;
    Console.WriteLine($"  ▶ {b.Venue}{b.Race}R {bt}{(string.IsNullOrWhiteSpace(b.Method) ? "" : " " + b.Method)} {pts}点 × {opt.StakePerPointYen:N0}円 = {per:N0}円");
    if (spentTotal + per > effBudget)
    {
        summary.Add($"  {b.Venue}{b.Race}R: 予算/残高超過スキップ");
        history.Save(b, opt, "予算超過見送り", per, pts, opt.ResolvedMode.ToString());
        continue;
    }
    var result = page.PlaceBet(b, out int spent); races++;
    if (opt.ResolvedMode == BetMode.ConfirmStop && result == BetResult.StoppedForConfirm)
    {
        Console.WriteLine($"  {b.Venue}{b.Race}R 確認停止。ブラウザのカートで内容(場/R/式別/方式/組数/金額)を確認し、合計金額入力→『購入する』→OK をご自身で操作してください。");
        Console.WriteLine("  → 確認/購入が済んだら、このウィンドウで Enter を押すと次へ進みます(押すまでブラウザは開いたまま=自動では閉じません)。");
        try { Console.ReadLine(); } catch { }   // 固定タイムアウトで閉じず、人の操作完了(Enter)まで待つ
        if (sess.PageContains(opt.CompletedText)) result = BetResult.Purchased;
    }
    string label = result switch { BetResult.Purchased => "投票完了", BetResult.Planned => "計画", BetResult.StoppedForConfirm => "見送り", BetResult.Closed => "締切", _ => "失敗" };
    if (result is BetResult.Purchased or BetResult.Planned) { spentTotal += spent; placed++; }
    summary.Add($"  {b.Venue}{b.Race}R: {label} {spent:N0}円 (軸{b.AxisUma} 相手[{string.Join(",", b.Partners)}])");
    history.Save(b, opt, label, spent, pts, opt.ResolvedMode.ToString());
}

Console.WriteLine("\n===== 結果 =====");
summary.ForEach(Console.WriteLine);
string verb = opt.ResolvedMode switch { BetMode.Auto => "投票(実課金)", BetMode.ConfirmStop => "確認停止まで準備", _ => "計画(無投票)" };
Console.WriteLine($"{verb}: {placed}レース / 合計 {spentTotal:N0}円");
Log.Line($"=== IpatVote 終了 {verb} {placed}R {spentTotal:N0}円 ===");
return 0;
