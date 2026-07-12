using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Markdig;

var builder = WebApplication.CreateBuilder(new WebApplicationOptions { Args = args, ContentRootPath = AppContext.BaseDirectory });
var cfg = builder.Configuration;
string U = cfg["Control:User"] ?? "admin";
string P = cfg["Control:Pass"] ?? "changeme";
int PORT = int.TryParse(cfg["Control:Port"], out var pp) ? pp : 5081;
builder.WebHost.UseUrls($"http://0.0.0.0:{PORT}");
var app = builder.Build();

string PSDIR = Path.Combine(AppContext.BaseDirectory, "ps");
string PWSH = @"C:\Program Files\PowerShell\7\pwsh.exe";
if (!File.Exists(PWSH)) PWSH = "pwsh.exe";

string RunPs(string file, params string[] a)
{
    var psi = new ProcessStartInfo
    {
        FileName = PWSH,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        UseShellExecute = false,
        CreateNoWindow = true,
        StandardOutputEncoding = Encoding.UTF8,
        StandardErrorEncoding = Encoding.UTF8
    };
    psi.ArgumentList.Add("-NoProfile");
    psi.ArgumentList.Add("-ExecutionPolicy");
    psi.ArgumentList.Add("Bypass");
    psi.ArgumentList.Add("-File");
    psi.ArgumentList.Add(Path.Combine(PSDIR, file));
    foreach (var x in a) psi.ArgumentList.Add(x);
    try
    {
        var pr = Process.Start(psi)!;
        string o = pr.StandardOutput.ReadToEnd();
        string e = pr.StandardError.ReadToEnd();
        pr.WaitForExit(30000);
        return string.IsNullOrWhiteSpace(e) ? o : (o + "\n[stderr] " + e);
    }
    catch (Exception ex) { return "[error] " + ex.Message; }
}

// パラメータ(JSON)→ set-params.ps1 引数。/api/params と プリセット適用/保存検証で共用。
// JRAランナー jra-weight-loop.ps1 のパラメータ(通知のみ/DryRun/ConfirmStop/Auto・式別・相手頭数・1点金額・Lead・取得間隔・投票窓・メール)。
(string[]? args, string? err) BuildSetArgs(JsonElement d)
{
    string mode = d.TryGetProperty("mode", out var m) ? (m.GetString() ?? "通知のみ") : "通知のみ";
    if (mode is not ("通知のみ" or "DryRun" or "ConfirmStop" or "Auto")) return (null, "mode不正");
    string bet = d.TryGetProperty("betType", out var bt) ? (bt.GetString() ?? "ワイド") : "ワイド";
    if (bet is not ("複勝" or "ワイド" or "馬連" or "三連複" or "単勝")) return (null, "式別不正");
    int partners = d.TryGetProperty("partners", out var pa) ? pa.GetInt32() : 3;
    int stake = d.TryGetProperty("stake", out var sk) ? sk.GetInt32() : 100;
    int lead = d.TryGetProperty("lead", out var le) ? le.GetInt32() : 40;
    int interval = d.TryGetProperty("interval", out var iv) ? iv.GetInt32() : 20;
    int voteWithin = d.TryGetProperty("voteWithin", out var vw) ? vw.GetInt32() : 25;
    int frontFlat = d.TryGetProperty("frontFlat", out var ff) ? ff.GetInt32() : 0;
    int changeLeadMin = d.TryGetProperty("changeLeadMin", out var cl) ? cl.GetInt32() : 30;
    int changeInterval = d.TryGetProperty("changeInterval", out var ci) ? ci.GetInt32() : 3;
    int oddsInterval = d.TryGetProperty("oddsInterval", out var oi) ? oi.GetInt32() : 5;
    bool noMail = d.TryGetProperty("noMail", out var nm) && nm.GetBoolean();
    if (partners < 1 || partners > 7 || stake < 100 || stake > 50000 || lead < 0 || lead > 120
        || interval < 5 || interval > 60 || voteWithin < 5 || voteWithin > 60 || frontFlat < 0 || frontFlat > 12
        || changeLeadMin < 0 || changeLeadMin > 120 || changeInterval < 1 || changeInterval > 30
        || oddsInterval < 1 || oddsInterval > 30)
        return (null, "値が範囲外です");
    var ps = new List<string> {
        "-Mode", mode, "-BetType", bet, "-Partners", partners.ToString(), "-Stake", stake.ToString(),
        "-Lead", lead.ToString(), "-Interval", interval.ToString(), "-VoteWithin", voteWithin.ToString(),
        "-FrontFlat", frontFlat.ToString(), "-ChangeLeadMin", changeLeadMin.ToString(), "-ChangeInterval", changeInterval.ToString(),
        "-OddsInterval", oddsInterval.ToString() };
    if (noMail) ps.Add("-NoMail");
    return (ps.ToArray(), null);
}

// ---- Basic 認証(家庭内LAN用) ----
string BRAND = @"C:\jra\branding";
app.Use(async (ctx, next) =>
{
    // ブランドアイコンは認証前でも配信(ログインダイアログにもfavicon表示)
    var p0 = ctx.Request.Path.Value ?? "";
    if (p0 is "/favicon.ico" or "/apple-touch-icon.png" or "/icon-512.png" or "/icon-32.png") { await next(); return; }
    string? h = ctx.Request.Headers.Authorization;
    if (h != null && h.StartsWith("Basic "))
    {
        try
        {
            var d = Encoding.UTF8.GetString(Convert.FromBase64String(h.Substring(6))).Split(':', 2);
            if (d.Length == 2 && d[0] == U && d[1] == P) { await next(); return; }
        }
        catch { }
    }
    ctx.Response.StatusCode = 401;
    ctx.Response.Headers.WWWAuthenticate = "Basic realm=\"JRA Runner Control\"";
    await ctx.Response.WriteAsync("認証が必要です");
});

app.MapGet("/", () => Results.Content(Html(), "text/html; charset=utf-8"));
// ブランドアイコン(Turfora)
IResult Icon(string file, string ct) { var f = Path.Combine(BRAND, file); return File.Exists(f) ? Results.File(f, ct) : Results.NotFound(); }
app.MapGet("/favicon.ico", () => Icon("favicon.ico", "image/x-icon"));
app.MapGet("/apple-touch-icon.png", () => Icon("apple-touch-icon.png", "image/png"));
app.MapGet("/icon-512.png", () => Icon("icon-512.png", "image/png"));
app.MapGet("/icon-32.png", () => Icon("icon-32.png", "image/png"));
app.MapGet("/history", () => Results.Content(HistoryHtml(), "text/html; charset=utf-8"));
app.MapGet("/api/history", () => Results.Content(RunPs("history.ps1"), "application/json; charset=utf-8"));
app.MapGet("/ledger", () => Results.Content(LedgerHtml(), "text/html; charset=utf-8"));
app.MapGet("/win5", () => Results.Content(Win5Html(), "text/html; charset=utf-8"));  // WIN5 買目点数計算(手動5レース選択・頭数→点数/金額)
// ===== 買目(全頭表)+IPAT投票Lite風(地方 /buyme 移植) =====
app.MapGet("/races", () => Results.Content(RacesHtml(), "text/html; charset=utf-8"));
app.MapGet("/api/races", () => Results.Content(RunPs("races.ps1"), "application/json; charset=utf-8"));
app.MapGet("/shutuba", () => Results.Content(ShutubaHtml(), "text/html; charset=utf-8"));
app.MapGet("/api/shutuba", (string? venue, string? race, string? date, string? umas) =>
{
    // venue/race 未指定でも可(shutuba.ps1 側でその開催日の先頭場/先頭レースに解決)。
    // ★race は string? として手動パース: 日付/場セレクタ変更時は race='' (空文字) で遷移するため、int/int? だとバインド失敗で400になる。date(yyyy-MM-dd)で過去日対応。
    var a = new System.Collections.Generic.List<string>();
    if (!string.IsNullOrWhiteSpace(venue)) { if (venue.Length > 12) venue = venue.Substring(0, 12); a.Add("-Venue"); a.Add(venue); }
    if (int.TryParse(race, out var rn) && rn > 0) { a.Add("-Race"); a.Add(rn.ToString()); }
    if (!string.IsNullOrEmpty(date) && System.Text.RegularExpressions.Regex.IsMatch(date, @"^\d{4}-\d{2}-\d{2}$")) { a.Add("-Date"); a.Add(date); }
    if (!string.IsNullOrWhiteSpace(umas) && System.Text.RegularExpressions.Regex.IsMatch(umas, @"^[0-9,]{1,60}$")) { a.Add("-Umas"); a.Add(umas); }   // 選択馬だけの馬柱(馬番カンマ区切り)
    return Results.Content(RunPs("shutuba.ps1", a.ToArray()), "application/json; charset=utf-8");
});
app.MapGet("/buyme", () => Results.Content(BuymeHtml(), "text/html; charset=utf-8"));
app.MapGet("/api/buyme", (string? venue, int race, string? date) =>
{
    if (string.IsNullOrWhiteSpace(venue) || race <= 0) return Results.Content("{\"error\":\"venue/race必須\"}", "application/json; charset=utf-8");
    if (venue.Length > 12) venue = venue.Substring(0, 12);
    // date(yyyy-MM-dd)指定で過去日の買目も表示(投票履歴の行クリック用)。未指定=当日。書式検証して注入。
    if (!string.IsNullOrEmpty(date) && System.Text.RegularExpressions.Regex.IsMatch(date, @"^\d{4}-\d{2}-\d{2}$"))
        return Results.Content(RunPs("buyme.ps1", "-Venue", venue, "-Race", race.ToString(), "-Date", date), "application/json; charset=utf-8");
    return Results.Content(RunPs("buyme.ps1", "-Venue", venue, "-Race", race.ToString()), "application/json; charset=utf-8");
});
// ★買目選定理由(地方から移植)。買目全頭データ + jra-card評価/総合(バックグラウンドで温めた場単位キャッシュ) + 予想突合。
app.MapGet("/reason", () => Results.Content(ReasonHtml(), "text/html; charset=utf-8"));
app.MapGet("/api/reason", (string? venue, int race, string? date) =>
{
    if (string.IsNullOrWhiteSpace(venue) || race <= 0) return Results.Content("{\"error\":\"venue/race必須\"}", "application/json; charset=utf-8");
    if (venue.Length > 12) venue = venue.Substring(0, 12);
    if (!string.IsNullOrEmpty(date) && System.Text.RegularExpressions.Regex.IsMatch(date, @"^\d{4}-\d{2}-\d{2}$"))
        return Results.Content(RunPs("reason.ps1", "-Venue", venue, "-Race", race.ToString(), "-Date", date), "application/json; charset=utf-8");
    return Results.Content(RunPs("reason.ps1", "-Venue", venue, "-Race", race.ToString()), "application/json; charset=utf-8");
});
// ★日次総括+深掘り一覧(1レースずつ深掘りした振り返りの索引)。keiba-daily-retro-granularity 絶対ルールの締め。
app.MapGet("/retro", () => Results.Content(RetroHtml(), "text/html; charset=utf-8"));
app.MapGet("/api/retro", (string? date) =>
{
    if (!string.IsNullOrEmpty(date) && System.Text.RegularExpressions.Regex.IsMatch(date, @"^\d{4}-\d{2}-\d{2}$"))
        return Results.Content(RunPs("retro.ps1", "-Date", date), "application/json; charset=utf-8");
    return Results.Content(RunPs("retro.ps1"), "application/json; charset=utf-8");
});
// 買目ページからの投票。DryRun=試算同期/ConfirmStop・Auto=デタッチ起動。vote.ps1がIpatVote稼働中ガード等を実施。実金はIPAT実DOM較正後。
app.MapPost("/api/vote", async (HttpContext ctx) =>
{
    string body = await new StreamReader(ctx.Request.Body).ReadToEndAsync();
    JsonElement d; try { d = JsonDocument.Parse(body).RootElement; } catch { return Results.BadRequest("JSON不正"); }
    string venue = d.TryGetProperty("venue", out var v) ? (v.GetString() ?? "") : "";
    int race = d.TryGetProperty("race", out var r) && r.TryGetInt32(out var ri) ? ri : 0;
    string mode = d.TryGetProperty("mode", out var mo) ? (mo.GetString() ?? "DryRun") : "DryRun";
    if (string.IsNullOrWhiteSpace(venue) || race <= 0) return Results.BadRequest("venue/race必須");
    if (mode is not ("DryRun" or "ConfirmStop" or "Auto")) mode = "DryRun";
    bool allowDup = d.TryGetProperty("allowdup", out var ad) && ad.ValueKind == JsonValueKind.True;   // 重複でも投票(上乗せ): 重複ガードを無視
    if (venue.Length > 12) venue = venue.Substring(0, 12);
    var betsOk = new[] { "単勝", "複勝", "馬連", "馬単", "ワイド", "枠連", "三連複", "三連単" };
    var methOk = new[] { "通常", "流し", "ボックス", "フォーメーション" };
    static int[] IntArr(JsonElement b, string name)
    {
        var l = new List<int>();
        if (b.TryGetProperty(name, out var e) && e.ValueKind == JsonValueKind.Array)
            foreach (var x in e.EnumerateArray())
                if (x.ValueKind == JsonValueKind.Number && x.TryGetInt32(out var iv) && iv > 0 && iv <= 99) l.Add(iv);
        return l.Distinct().Take(18).ToArray();
    }
    var cart = new List<Dictionary<string, object>>();
    if (d.TryGetProperty("bets", out var bets) && bets.ValueKind == JsonValueKind.Array)
        foreach (var b in bets.EnumerateArray())
        {
            string bt2 = b.TryGetProperty("bettype", out var bte) ? (bte.GetString() ?? "") : "";
            if (Array.IndexOf(betsOk, bt2) < 0) continue;
            string mth = b.TryGetProperty("method", out var mte) ? (mte.GetString() ?? "") : "";
            if (!string.IsNullOrEmpty(mth) && Array.IndexOf(methOk, mth) < 0) mth = "";
            int axis2 = b.TryGetProperty("axis", out var ae) && ae.TryGetInt32(out var av) && av > 0 && av <= 99 ? av : 0;
            int stake2 = b.TryGetProperty("stake", out var se) && se.TryGetInt32(out var sv) ? sv : 100;
            if (stake2 < 100) stake2 = 100; if (stake2 > 1000000) stake2 = 1000000;
            cart.Add(new Dictionary<string, object> {
                ["bettype"] = bt2, ["method"] = mth, ["axis"] = axis2, ["stake"] = stake2,
                ["partners"] = IntArr(b, "partners"), ["box"] = IntArr(b, "box"),
                ["f1"] = IntArr(b, "f1"), ["f2"] = IntArr(b, "f2"), ["f3"] = IntArr(b, "f3"),
                ["multi"] = (b.TryGetProperty("multi", out var mu) && mu.ValueKind == JsonValueKind.True),   // D:三連単/馬単マルチ
            });
            if (cart.Count >= 40) break;
        }
    if (cart.Count == 0) return Results.Content("{\"ok\":false,\"msg\":\"買い目がありません\"}", "application/json; charset=utf-8");
    Directory.CreateDirectory(@"C:\temp\rc-vote");
    string cartPath = Path.Combine(@"C:\temp\rc-vote", $"cart_{DateTime.Now:yyyyMMddHHmmssfff}.json");
    File.WriteAllText(cartPath, JsonSerializer.Serialize(cart), new UTF8Encoding(false));
    var vargs = new List<string> { "-Venue", venue, "-Race", race.ToString(), "-Mode", mode, "-CartPath", cartPath };
    if (allowDup) vargs.Add("-AllowDup");
    return Results.Content(RunPs("vote.ps1", vargs.ToArray()), "application/json; charset=utf-8");
});
// 手動投票の成否ポーリング(ConfirmStop/Autoはデタッチ起動のため、投票後にここで結果を確認)。
app.MapGet("/api/vote-status", (string? venue, int race, string? since) =>
{
    if (string.IsNullOrWhiteSpace(venue) || race <= 0) return Results.Content("{\"ok\":false}", "application/json; charset=utf-8");
    if (venue.Length > 12) venue = venue.Substring(0, 12);
    // since は yyyy-MM-dd HH:mm:ss のみ許可(SQLパラメータだが念のため書式検証)
    var args = new List<string> { "-Venue", venue, "-Race", race.ToString() };
    if (!string.IsNullOrEmpty(since) && System.Text.RegularExpressions.Regex.IsMatch(since, @"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")) { args.Add("-Since"); args.Add(since); }
    return Results.Content(RunPs("vote-status.ps1", args.ToArray()), "application/json; charset=utf-8");
});
// レース単位 自動投票ON/OFF トグル(B)。当日disabledリストを race-autovote.json に書込(jra-weight-loopが毎レース参照)。
app.MapPost("/api/race-toggle", async (HttpContext ctx) =>
{
    string body = await new StreamReader(ctx.Request.Body).ReadToEndAsync();
    JsonElement d; try { d = JsonDocument.Parse(body).RootElement; } catch { return Results.BadRequest("JSON不正"); }
    string venue = d.TryGetProperty("venue", out var v) ? (v.GetString() ?? "") : "";
    int race = d.TryGetProperty("race", out var r) && r.TryGetInt32(out var ri) ? ri : 0;
    bool enabled = !d.TryGetProperty("enabled", out var en) || en.ValueKind != JsonValueKind.False;
    if (string.IsNullOrWhiteSpace(venue) || race <= 0) return Results.BadRequest("venue/race必須");
    if (venue.Length > 12) venue = venue.Substring(0, 12);
    string today = DateTime.Today.ToString("yyyy-MM-dd"); string key = $"{venue}|{race}";
    string file = @"C:\jra\RunnerControl\race-autovote.json";
    var disabled = new List<string>();
    try { if (File.Exists(file)) { var j = JsonDocument.Parse(File.ReadAllText(file)).RootElement; if (j.TryGetProperty("date", out var dj) && dj.GetString() == today && j.TryGetProperty("disabled", out var ds) && ds.ValueKind == JsonValueKind.Array) foreach (var x in ds.EnumerateArray()) { var s = x.GetString(); if (!string.IsNullOrEmpty(s)) disabled.Add(s); } } } catch { }
    disabled.Remove(key); if (!enabled) disabled.Add(key);
    File.WriteAllText(file, JsonSerializer.Serialize(new Dictionary<string, object> { ["date"] = today, ["disabled"] = disabled.Distinct().ToList() }), new UTF8Encoding(false));
    return Results.Content(JsonSerializer.Serialize(new Dictionary<string, object> { ["ok"] = true, ["venue"] = venue, ["race"] = race, ["autovote"] = enabled }), "application/json; charset=utf-8");
});
// ★自動投票 一括ON/OFF(地方移植)。body={enabled,keys[]}。enabled=true→disabled空(全部する)、false→keys(venue|race)をdisabled(全部しない)。当日分race-autovote.json上書き。
app.MapPost("/api/race-toggle-all", async (HttpContext ctx) =>
{
    string body = await new StreamReader(ctx.Request.Body).ReadToEndAsync();
    JsonElement d; try { d = JsonDocument.Parse(body).RootElement; } catch { return Results.BadRequest("JSON不正"); }
    bool enabled = !d.TryGetProperty("enabled", out var en) || en.ValueKind != JsonValueKind.False;
    var disabled = new List<string>();
    if (!enabled && d.TryGetProperty("keys", out var ks) && ks.ValueKind == JsonValueKind.Array)
        foreach (var x in ks.EnumerateArray()) { var s = x.GetString(); if (!string.IsNullOrWhiteSpace(s) && s!.Length <= 20) disabled.Add(s!); }
    string today2 = DateTime.Today.ToString("yyyy-MM-dd");
    string file2 = @"C:\jra\RunnerControl\race-autovote.json";
    File.WriteAllText(file2, JsonSerializer.Serialize(new Dictionary<string, object> { ["date"] = today2, ["disabled"] = disabled.Distinct().ToList() }), new UTF8Encoding(false));
    return Results.Content(JsonSerializer.Serialize(new Dictionary<string, object> { ["ok"] = true, ["enabled"] = enabled, ["count"] = disabled.Count }), "application/json; charset=utf-8");
});
// 取りやめ(レース中止)トグル(A9)。当日cancelledリストを race-cancel.json に書込(表示/投票ブロック/ランナースキップが参照)。
app.MapPost("/api/race-cancel", async (HttpContext ctx) =>
{
    string body = await new StreamReader(ctx.Request.Body).ReadToEndAsync();
    JsonElement d; try { d = JsonDocument.Parse(body).RootElement; } catch { return Results.BadRequest("JSON不正"); }
    string venue = d.TryGetProperty("venue", out var v) ? (v.GetString() ?? "") : "";
    int race = d.TryGetProperty("race", out var r) && r.TryGetInt32(out var ri) ? ri : 0;
    bool cancelled = d.TryGetProperty("cancelled", out var cn) && cn.ValueKind == JsonValueKind.True;
    if (string.IsNullOrWhiteSpace(venue) || race <= 0) return Results.BadRequest("venue/race必須");
    if (venue.Length > 12) venue = venue.Substring(0, 12);
    string today = DateTime.Today.ToString("yyyy-MM-dd"); string key = $"{venue}|{race}";
    string file = @"C:\jra\RunnerControl\race-cancel.json";
    var list = new List<string>();
    try { if (File.Exists(file)) { var j = JsonDocument.Parse(File.ReadAllText(file)).RootElement; if (j.TryGetProperty("date", out var dj) && dj.GetString() == today && j.TryGetProperty("cancelled", out var cs2) && cs2.ValueKind == JsonValueKind.Array) foreach (var x in cs2.EnumerateArray()) { var s = x.GetString(); if (!string.IsNullOrEmpty(s)) list.Add(s); } } } catch { }
    list.Remove(key); if (cancelled) list.Add(key);
    File.WriteAllText(file, JsonSerializer.Serialize(new Dictionary<string, object> { ["date"] = today, ["cancelled"] = list.Distinct().ToList() }), new UTF8Encoding(false));
    return Results.Content(JsonSerializer.Serialize(new Dictionary<string, object> { ["ok"] = true, ["venue"] = venue, ["race"] = race, ["cancelled"] = cancelled }), "application/json; charset=utf-8");
});
app.MapGet("/api/status", () => Results.Content(RunPs("status.ps1"), "application/json; charset=utf-8"));
// ★全体収支「更新」ボタン。IPAT投票履歴を当日結果と突合して確定/払戻を最新化(jra-ipat-settle)。DBのみ・高速。
app.MapPost("/api/ipat-settle", () => Results.Content(RunPs("ipat-settle.ps1"), "application/json; charset=utf-8"));
// ★IPAT投票可能額(残高) 表示(地方rakuten-balance移植)。更新ボタン=IpatVote balanceをバックグラウンド照会/状態ポーリング/初期は直近値。
app.MapPost("/api/ipat-balance-refresh", () => Results.Content(RunPs("ipat-balance-launch.ps1"), "application/json; charset=utf-8"));
app.MapGet("/api/ipat-balance-status", () =>
{
    try { var f = @"C:\jra\RunnerControl\ipat-balance-status.json"; if (File.Exists(f)) return Results.Content(File.ReadAllText(f, Encoding.UTF8), "application/json; charset=utf-8"); }
    catch { }
    return Results.Content("{\"state\":\"idle\",\"done\":true}", "application/json; charset=utf-8");
});
// 最後に照会したIPAT残高(ipat-balance.txt=時刻\t金額)を返す。投票画面の初期表示用(照会は走らせない)。
app.MapGet("/api/ipat-balance", () =>
{
    try
    {
        var bf = @"C:\jra\RunnerControl\ipat-balance.txt";
        if (File.Exists(bf))
        {
            var parts = File.ReadAllText(bf, Encoding.UTF8).Trim().Split('\t');
            if (parts.Length >= 2 && long.TryParse(parts[1].Trim(), out var amt))
            {
                var t = "";
                if (DateTime.TryParse(parts[0].Trim(), out var dt)) t = dt.ToString("HH:mm");
                return Results.Content("{\"balance\":" + amt + ",\"balT\":\"" + t + "\"}", "application/json; charset=utf-8");
            }
        }
    }
    catch { }
    return Results.Content("{\"balance\":null}", "application/json; charset=utf-8");
});
app.MapGet("/api/params", () => Results.Content(RunPs("get-params.ps1"), "application/json; charset=utf-8"));
app.MapGet("/api/log", () =>
{
    try
    {
        string f = Path.Combine(@"C:\temp", $"jra_weight_loop_{DateTime.Now:yyyyMMdd}.log");
        if (!File.Exists(f)) return Results.Content("本日のランナーログはまだありません", "text/plain; charset=utf-8");
        using var fs = new FileStream(f, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        using var rd = new StreamReader(fs, Encoding.UTF8);
        var lines = rd.ReadToEnd().Replace("\r\n", "\n").Split('\n');
        int n = Math.Min(80, lines.Length);
        return Results.Content(string.Join("\n", lines.Skip(lines.Length - n)), "text/plain; charset=utf-8");
    }
    catch (Exception ex) { return Results.Content("ログ読込エラー: " + ex.Message, "text/plain; charset=utf-8"); }
});

app.MapPost("/api/control/{action}", (string action) =>
{
    if (action is not ("start" or "stop" or "restart")) return Results.BadRequest("不正なアクション");
    return Results.Content(RunPs("control.ps1", "-Action", action), "text/plain; charset=utf-8");
});

// ライブ中継(sp.gch.jp/jra)をサーバの可視Chromeで開く。動画はサーバ機のデスクトップに表示。視聴のみ(実金操作なし)。
app.MapPost("/api/live/{venue?}", (string? venue) => Results.Content(RunPs("live.ps1", "-Venue", venue ?? ""), "text/plain; charset=utf-8"));

app.MapPost("/api/params", async (HttpContext ctx) =>
{
    using var sr = new StreamReader(ctx.Request.Body);
    var body = await sr.ReadToEndAsync();
    JsonElement d;
    try { d = JsonDocument.Parse(body).RootElement; } catch { return Results.BadRequest("JSON不正"); }
    var (a, err) = BuildSetArgs(d);
    if (err != null) return Results.BadRequest(err);
    return Results.Content(RunPs("set-params.ps1", a!), "text/plain; charset=utf-8");
});

// ===== パラメータプリセット(複数保存・呼び出し・編集・コメント) =====
string presetsPath = @"C:\jra\RunnerControl\presets.json";
object presetsLock = new();
string ReadPresets() { try { return File.Exists(presetsPath) ? File.ReadAllText(presetsPath) : "[]"; } catch { return "[]"; } }
JsonArray PresetArray() { try { return JsonNode.Parse(ReadPresets())?.AsArray() ?? new JsonArray(); } catch { return new JsonArray(); } }
// 設定ファイル プリセット(ファイル単位の非機密スナップショット)
string cfgPresetsPath = @"C:\jra\RunnerControl\config-presets.json";
JsonArray CfgPresetArr() { try { return JsonNode.Parse(File.Exists(cfgPresetsPath) ? File.ReadAllText(cfgPresetsPath) : "[]")?.AsArray() ?? new JsonArray(); } catch { return new JsonArray(); } }

app.MapGet("/api/presets", () => Results.Content(ReadPresets(), "application/json; charset=utf-8"));

app.MapPost("/api/presets", async (HttpContext ctx) =>
{
    var body = await new StreamReader(ctx.Request.Body).ReadToEndAsync();
    JsonElement d; try { d = JsonDocument.Parse(body).RootElement; } catch { return Results.BadRequest("JSON不正"); }
    string name = d.TryGetProperty("name", out var nm) ? (nm.GetString() ?? "").Trim() : "";
    if (string.IsNullOrEmpty(name)) return Results.BadRequest("プリセット名が必要です");
    if (name.Length > 40) return Results.BadRequest("プリセット名は40文字以内");
    string comment = d.TryGetProperty("comment", out var cm) ? (cm.GetString() ?? "") : "";
    if (comment.Length > 1000) comment = comment.Substring(0, 1000);
    if (!d.TryGetProperty("params", out var pe) || pe.ValueKind != JsonValueKind.Object) return Results.BadRequest("paramsが必要です");
    var (_, perr) = BuildSetArgs(pe);
    if (perr != null) return Results.BadRequest(perr);
    lock (presetsLock)
    {
        var arr = PresetArray();
        for (int i = arr.Count - 1; i >= 0; i--) if ((string?)arr[i]!["name"] == name) arr.RemoveAt(i);
        arr.Add(new JsonObject {
            ["name"] = name, ["comment"] = comment,
            ["savedAt"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm"),
            ["params"] = JsonNode.Parse(pe.GetRawText())
        });
        try { File.WriteAllText(presetsPath, arr.ToJsonString()); } catch (Exception ex) { return Results.Content("NG: 保存失敗 " + ex.Message, "text/plain; charset=utf-8"); }
    }
    return Results.Content("OK: プリセット「" + name + "」を保存しました", "text/plain; charset=utf-8");
});

app.MapPost("/api/presets/delete", async (HttpContext ctx) =>
{
    var body = await new StreamReader(ctx.Request.Body).ReadToEndAsync();
    JsonElement d; try { d = JsonDocument.Parse(body).RootElement; } catch { return Results.BadRequest("JSON不正"); }
    string name = d.TryGetProperty("name", out var nm) ? (nm.GetString() ?? "").Trim() : "";
    if (string.IsNullOrEmpty(name)) return Results.BadRequest("名前が必要です");
    lock (presetsLock)
    {
        var arr = PresetArray();
        for (int i = arr.Count - 1; i >= 0; i--) if ((string?)arr[i]!["name"] == name) arr.RemoveAt(i);
        try { File.WriteAllText(presetsPath, arr.ToJsonString()); } catch (Exception ex) { return Results.Content("NG: 削除失敗 " + ex.Message, "text/plain; charset=utf-8"); }
    }
    return Results.Content("OK: プリセット「" + name + "」を削除しました", "text/plain; charset=utf-8");
});

app.MapPost("/api/presets/apply", async (HttpContext ctx) =>
{
    var body = await new StreamReader(ctx.Request.Body).ReadToEndAsync();
    JsonElement d; try { d = JsonDocument.Parse(body).RootElement; } catch { return Results.BadRequest("JSON不正"); }
    string name = d.TryGetProperty("name", out var nm) ? (nm.GetString() ?? "").Trim() : "";
    if (string.IsNullOrEmpty(name)) return Results.BadRequest("名前が必要です");
    JsonNode? found = null;
    foreach (var it in PresetArray()) if ((string?)it!["name"] == name) { found = it; break; }
    if (found == null) return Results.NotFound("プリセットが見つかりません");
    JsonElement pe; try { pe = JsonDocument.Parse(found["params"]!.ToJsonString()).RootElement; } catch { return Results.BadRequest("params不正"); }
    var (a2, err2) = BuildSetArgs(pe);
    if (err2 != null) return Results.BadRequest(err2);
    string res = RunPs("set-params.ps1", a2!);
    return Results.Content("[適用:" + name + "] " + res, "text/plain; charset=utf-8");
});

// ===== 設定ファイル 閲覧/編集 =====
app.MapGet("/config", (HttpContext ctx) => { ctx.Response.Headers.CacheControl = "no-store, no-cache, max-age=0"; return Results.Content(ConfigHtml(), "text/html; charset=utf-8"); });
app.MapGet("/profiles", (HttpContext ctx) => { ctx.Response.Headers.CacheControl = "no-store, no-cache, max-age=0"; return Results.Content(ProfilesHtml(), "text/html; charset=utf-8"); });
app.MapGet("/api/config/list", () => Results.Content(CfgListJson(), "application/json; charset=utf-8"));
app.MapGet("/api/config/get", (string id) => Results.Content(CfgGetJson(id), "application/json; charset=utf-8"));
app.MapPost("/api/config/save", async (HttpContext ctx) =>
{
    using var sr = new StreamReader(ctx.Request.Body); var body = await sr.ReadToEndAsync();
    JsonElement d; try { d = JsonDocument.Parse(body).RootElement; } catch { return Results.BadRequest("JSON不正"); }
    return Results.Content(CfgSave(d), "text/plain; charset=utf-8");
});
// 設定ファイル プリセット(一覧/保存/適用/削除)。機密は保存しない(非機密リーフのみ)。
app.MapGet("/api/config/presets", (string id) =>
{
    var list = CfgPresetArr().Where(n => (string?)n?["id"] == id)
        .Select(n => new { name = (string?)n!["name"], comment = (string?)n["comment"], savedAt = (string?)n["savedAt"], count = (n["entries"] as JsonArray)?.Count ?? 0 });
    return Results.Content(JsonSerializer.Serialize(list, new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }), "application/json; charset=utf-8");
});
// 全ファイル横断の保存済みプロファイル(プリセット)一覧
app.MapGet("/api/config/presets/all", () =>
{
    var reg = CfgReg();
    var list = CfgPresetArr().Select(n =>
    {
        var pid = (string?)n?["id"] ?? "";
        var lbl = reg.FirstOrDefault(x => x.id == pid).label ?? pid;
        return new { id = pid, fileLabel = lbl, name = (string?)n!["name"], comment = (string?)n["comment"], savedAt = (string?)n["savedAt"], count = (n["entries"] as JsonArray)?.Count ?? 0 };
    });
    return Results.Content(JsonSerializer.Serialize(list, new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }), "application/json; charset=utf-8");
});
app.MapPost("/api/config/presets", async (HttpContext ctx) =>
{
    using var sr = new StreamReader(ctx.Request.Body); var body = await sr.ReadToEndAsync();
    JsonElement d; try { d = JsonDocument.Parse(body).RootElement; } catch { return Results.BadRequest("JSON不正"); }
    string id = d.TryGetProperty("id", out var ie) ? (ie.GetString() ?? "") : "";
    string name = d.TryGetProperty("name", out var ne) ? (ne.GetString() ?? "").Trim() : "";
    string comment = d.TryGetProperty("comment", out var ce) ? (ce.GetString() ?? "") : "";
    if (CfgReg().FirstOrDefault(x => x.id == id).id == null) return Results.BadRequest("不明な設定ID");
    if (string.IsNullOrEmpty(name)) return Results.BadRequest("プリセット名が必要です");
    if (name.Length > 40) return Results.BadRequest("プリセット名は40文字以内");
    if (comment.Length > 1000) return Results.BadRequest("コメントは1000文字以内");
    lock (presetsLock)
    {
        var leaves = CfgFileLeaves(id);
        var earr = new JsonArray(); foreach (var kv in leaves) earr.Add(new JsonObject { ["path"] = kv.Key, ["value"] = kv.Value });
        var arr = CfgPresetArr();
        for (int i = arr.Count - 1; i >= 0; i--) if ((string?)arr[i]?["id"] == id && (string?)arr[i]?["name"] == name) arr.RemoveAt(i);
        arr.Add(new JsonObject { ["id"] = id, ["name"] = name, ["comment"] = comment, ["savedAt"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm"), ["entries"] = earr });
        try { File.WriteAllText(cfgPresetsPath, arr.ToJsonString(new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping })); }
        catch (Exception ex) { return Results.Content("NG: 保存失敗 " + ex.Message, "text/plain; charset=utf-8"); }
        return Results.Content("OK: プリセット「" + name + "」を保存しました(非機密 " + leaves.Count + " 項目)。", "text/plain; charset=utf-8");
    }
});
app.MapPost("/api/config/presets/apply", async (HttpContext ctx) =>
{
    using var sr = new StreamReader(ctx.Request.Body); var body = await sr.ReadToEndAsync();
    JsonElement d; try { d = JsonDocument.Parse(body).RootElement; } catch { return Results.BadRequest("JSON不正"); }
    string id = d.TryGetProperty("id", out var ie) ? (ie.GetString() ?? "") : "";
    string name = d.TryGetProperty("name", out var ne) ? (ne.GetString() ?? "") : "";
    var found = CfgPresetArr().FirstOrDefault(n => (string?)n?["id"] == id && (string?)n?["name"] == name);
    if (found == null) return Results.NotFound("プリセットが見つかりません");
    var list = new List<(string path, string val)>();
    foreach (var e in (found["entries"] as JsonArray) ?? new JsonArray()) list.Add(((string?)e?["path"] ?? "", (string?)e?["value"] ?? ""));
    return Results.Content("[適用:" + name + "] " + CfgWriteEntries(id, list), "text/plain; charset=utf-8");
});
app.MapPost("/api/config/presets/delete", async (HttpContext ctx) =>
{
    using var sr = new StreamReader(ctx.Request.Body); var body = await sr.ReadToEndAsync();
    JsonElement d; try { d = JsonDocument.Parse(body).RootElement; } catch { return Results.BadRequest("JSON不正"); }
    string id = d.TryGetProperty("id", out var ie) ? (ie.GetString() ?? "") : "";
    string name = d.TryGetProperty("name", out var ne) ? (ne.GetString() ?? "") : "";
    lock (presetsLock)
    {
        var arr = CfgPresetArr();
        for (int i = arr.Count - 1; i >= 0; i--) if ((string?)arr[i]?["id"] == id && (string?)arr[i]?["name"] == name) arr.RemoveAt(i);
        try { File.WriteAllText(cfgPresetsPath, arr.ToJsonString(new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping })); }
        catch (Exception ex) { return Results.Content("NG: 削除失敗 " + ex.Message, "text/plain; charset=utf-8"); }
        return Results.Content("OK: プリセット「" + name + "」を削除しました", "text/plain; charset=utf-8");
    }
});

// ★自動精算ループ: 日中(9-19時)2分毎に当日IPAT投票履歴を結果(払戻金)と突合して確定/払戻を最新化。
// 地方の Keiba_SettleNow_2min 相当。DB突合のみ・冪等・金銭移動なし。結果が取り込まれ次第、全体収支が自動更新される。
_ = Task.Run(async () =>
{
    while (true)
    {
        try { var h = DateTime.Now.Hour; if (h >= 9 && h < 19) RunPs("ipat-settle.ps1"); }
        catch { /* 個別失敗は無視して継続 */ }
        await Task.Delay(TimeSpan.FromSeconds(120));
    }
});

// ★選定理由の評価キャッシュ・ウォーマー: 日中(9-18時)、当日各開催場のjra-card評価/総合を1回1場ずつ温める。
// reason.ps1 はこのキャッシュを読むだけ(157秒級のjra-cardをWebリクエスト同期で回さない)。1場ごとに約150秒→待機180秒。
_ = Task.Run(async () =>
{
    while (true)
    {
        try { var h = DateTime.Now.Hour; if (h >= 9 && h < 19) RunPs("reason-warm.ps1"); }
        catch { /* 個別失敗は無視して継続 */ }
        await Task.Delay(TimeSpan.FromSeconds(180));
    }
});

app.Run();

// ===== 設定ファイル ヘルパ(JRA=C:\jra) =====
(string id, string label, string path)[] CfgReg() => new (string, string, string)[]
{
    ("common", "共通設定 — DB接続/極ウマ (共通\\appsettings.json)",         @"C:\jra\共通\appsettings.json"),
    ("webctl", "コントロール盤 設定 (ポート/Basic認証)",                    @"C:\jra\RunnerControl\appsettings.json"),
    ("runner", "ランナー設定 (runner-params.json: モード/式別/相手/金額/Lead)", @"C:\jra\RunnerControl\runner-params.json"),
    ("ipat",   "IPAT投票設定 (ipat.json: モード/券種/セレクタ)",            @"C:\jra\IpatVote\ipat.json"),
    ("secrets","認証情報 secrets.local.json ※機密",                        @"C:\jra\secrets.local.json"),
};
bool CfgIsSecret(string path)
{
    var seg = (path.Contains(':') ? path.Substring(path.LastIndexOf(':') + 1) : path).ToLowerInvariant();
    return seg.EndsWith("pass") || seg.EndsWith("password") || seg.EndsWith("pwd") || seg.EndsWith("pin")
        || seg.EndsWith("connection") || seg.Contains("connectionstring")
        || seg.Contains("secret") || seg.Contains("token") || seg.Contains("apikey") || seg.Contains("api_key")
        || seg.Contains("webhook") || seg == "sig"
        || seg.EndsWith("inetid") || seg.EndsWith("subscriber") || seg.EndsWith("pars");   // IPAT即PAT認証(INET-ID/加入者番号/P-ARS)=金融情報。末尾一致でセレクタ名(LoginInetIdInput等)の誤マスク回避
}
string CfgTip(string path)
{
    var tips = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["ConnectionStrings:DefaultConnection"] = "中央競馬DB(JRA)への接続文字列。※サーバ/ID/パスワードを含む機密。",
        ["GokuUma:ProfileDir"] = "極ウマ(コンピ指数取得)のChromeプロファイル。地方と別パスにし競合回避。",
        ["GokuUma:User"] = "極ウマ ログインID。",
        ["GokuUma:Pass"] = "極ウマ ログインパスワード。※機密。",
        ["GokuUma:Password"] = "極ウマ ログインパスワード。※機密。",
        ["Control:Port"] = "このコントロール盤の待受ポート(JRA=5081)。",
        ["Control:User"] = "コントロール盤のBasic認証ユーザー名。",
        ["Control:Pass"] = "コントロール盤のBasic認証パスワード。※機密。変更後は再ログインが必要。",
        // runner-params.json (JRAランナー jra-weight-loop)
        ["mode"] = "ランナー動作モード。通知のみ=実投票しない(安全既定)／DryRun／ConfirmStop／Auto=実課金。",
        ["betType"] = "券種(ワイド/馬連/三連複)。既定ワイド(軸流し相手3が回収最良)。",
        ["partners"] = "相手の頭数(1-7)。",
        ["stake"] = "1点あたりの購入額(円)。",
        ["lead"] = "初レースの何分前にランナーを起動するか(分)。",
        ["interval"] = "馬体重取得/再分析の間隔(分)。",
        ["voteWithin"] = "発走の何分前まで投票するか(投票窓・分)。",
        ["noMail"] = "true=メール通知を送らない。",
        ["savedAt"] = "この設定を保存した日時(自動)。",
        // ipat.json (IpatVote)
        ["IpatVote:Mode"] = "IPAT投票モード。DryRun=無投票(既定)／ConfirmStop=確認で停止／Auto=実課金(DOMセレクタ較正後のみ実動)。",
        ["IpatVote:BetType"] = "券種(三連複/ワイド/馬連 等)。",
        ["IpatVote:Method"] = "方式(流し/ボックス/フォーメーション)。",
        ["IpatVote:PartnerCount"] = "相手の頭数。",
        ["IpatVote:StakePerPointYen"] = "1点あたりの購入額(円・100円単位)。",
        ["IpatVote:DailyBudgetYen"] = "1日の投票上限額(円)。",
        ["IpatVote:MaxRaces"] = "投票する最大レース数(0=無制限)。",
        ["IpatVote:Venues"] = "投票対象競馬場(カンマ区切り・空=全場)。",
        ["IpatVote:Headless"] = "true=ブラウザ非表示(DryRunのみ)。実課金は表示必須。",
        ["IpatVote:ManualLoginAssistSeconds"] = "2段階/約定同意等の手動操作を待つ最大秒数。",
        ["IpatVote:ConfirmWaitSeconds"] = "確認画面で完了表示を待つ最大秒数。",
        ["IpatVote:Urls:Top"] = "IPAT(即PAT)トップURL。",
        // secrets.local.json
        ["IpatInetId"] = "即PAT(IPAT)のINET-ID。※機密(口座アクセス)。",
        ["IpatSubscriber"] = "即PATの加入者番号。※機密。",
        ["IpatPin"] = "即PATの暗証番号(P-ARSとともに投票/入金に使用)。※機密。",
        ["IpatPars"] = "即PATのP-ARS番号。※機密。",
        ["RakutenUser"] = "楽天競馬(楽天ID)のログインID。※機密。",
        ["RakutenPass"] = "楽天競馬のログインパスワード。※機密。",
        ["RakutenPin"] = "楽天競馬の暗証番号。※機密。",
        ["GokuUmaUser"] = "極ウマ ログインID。※機密。",
        ["GokuUmaPass"] = "極ウマ ログインパスワード。※機密。",
        ["KeibabookUser"] = "競馬ブック ログインID。",
        ["KeibabookPass"] = "競馬ブック ログインパスワード。※機密。",
        ["MailPass"] = "メール送信パスワード。※機密。",
        ["GraphClientSecret"] = "Microsoft Graph(メール送信)のクライアントシークレット。※機密。",
        ["TeamsWebhook"] = "Teams通知のWebhook URL(署名付き)。※機密。",
        ["MailUser"] = "メール送信アカウント。",
        ["MailFrom"] = "メールの差出人アドレス。",
        ["MailTo"] = "通知メールの宛先アドレス。",
        ["GraphTenantId"] = "Microsoft Graph のテナントID。",
        ["GraphClientId"] = "Microsoft Graph のアプリ(クライアント)ID。",
        ["KeibabookUser"] = "競馬ブック ログインID。",
        ["EventLogSource"] = "Windowsイベントログのソース名。",
        ["LogFilePath"] = "ログ出力先ファイルのパス。",
        ["場名マスタ"] = "競馬場の名称マスタ(コード/名称対応表)。通常は変更不要。",
        ["GokuUma:LoginUrl"] = "極ウマのログインページURL。",
        ["GokuUma:CompiUrl"] = "極ウマ コンピ指数ページのURL。",
        ["GokuUma:DumpDir"] = "極ウマ取得データの保存フォルダ。",
        ["GokuUma:Headless"] = "極ウマ取得をブラウザ非表示で行うか(true/false)。",
        ["GokuUma:ManualLoginAssistSeconds"] = "極ウマ 手動ログインを待つ秒数。",
        ["IpatVote:_comment"] = "ファイル内の説明コメント(動作に影響なし)。",
    };
    if (tips.TryGetValue(path, out var t)) return t;
    var seg = path.Contains(':') ? path.Substring(path.LastIndexOf(':') + 1) : path;
    if (tips.TryGetValue(seg, out var t2)) return t2;
    return CfgTipFallback(path, seg);
}
// 辞書に無い項目もパターンから役割を生成(全項目に説明を付ける)。
string CfgTipFallback(string path, string seg)
{
    var low = path.ToLowerInvariant();
    var sl = seg.ToLowerInvariant();
    if (seg.StartsWith("_") || low.Contains("_comment") || low.Contains("_options") || low.Contains("_note")) return "ファイル内の説明用コメント(動作には影響しません)。";
    if (low.Contains(":selectors:")) return "自動操作で使う画面要素のCSSセレクタ。通常は変更不要(サイト構造の変更時のみ較正)。";
    if (low.Contains(":deposit:")) return "入金処理に使う設定/画面セレクタ。";
    if (sl.EndsWith("url") || low.Contains(":urls:")) return "アクセス先のURL。";
    if (sl.EndsWith("dir") || sl.EndsWith("path")) return "使用するフォルダ/ファイルのパス。";
    if (sl.EndsWith("seconds")) return "待ち時間(秒)。";
    if (sl.EndsWith("yen")) return "金額(円)。";
    if (sl.EndsWith("pct")) return "割合(%)。";
    if (sl.EndsWith("text")) return "判定に使う文言(この文字を含むかで判定)。";
    if (sl.Contains("headless")) return "true=ブラウザ非表示。実課金は描画が必要なため通常false。";
    if (sl.Contains("venue")) return "対象の競馬場(カンマ区切り・空=全場)。";
    if (sl == "savedat") return "保存した日時(自動記録)。";
    if (sl.EndsWith("count") || sl.EndsWith("partners")) return "頭数/件数。";
    return "設定項目「" + seg + "」。";
}
// 値が固定の項目(Mode/Method/BetType等)はドロップダウン選択肢を返す。該当なし=空配列。
string[] CfgChoices(string path)
{
    var seg = path.Contains(':') ? path.Substring(path.LastIndexOf(':') + 1) : path;
    return path switch
    {
        "RakutenVote:Mode" => new[] { "DryRun", "ConfirmStop", "Auto" },
        "IpatVote:Mode" => new[] { "DryRun", "ConfirmStop", "Auto" },
        "RakutenVote:Method" => new[] { "Nagashi", "Box", "Formation" },
        "IpatVote:Method" => new[] { "流し", "ボックス", "フォーメーション" },
        "RakutenVote:BetType" => new[] { "SanrentanMulti", "SanrenpukuNagashi", "Umaren", "Umatan", "Wide", "Wakuren", "Tan", "Fuku" },
        "IpatVote:BetType" => new[] { "三連複", "三連単", "馬連", "馬単", "ワイド", "枠連", "単勝", "複勝" },
        _ => seg switch
        {
            "mode" => new[] { "通知のみ", "DryRun", "ConfirmStop", "Auto" },
            "betType" => new[] { "ワイド", "馬連", "三連複" },
            _ => System.Array.Empty<string>()
        }
    };
}
string CfgListJson()
{
    var list = CfgReg().Select(f => new { id = f.id, label = f.label, path = f.path, exists = File.Exists(f.path) });
    return JsonSerializer.Serialize(list, new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
}
string CfgGetJson(string id)
{
    var jopt = new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
    var f = CfgReg().FirstOrDefault(x => x.id == id);
    if (f.id == null) return "{\"error\":\"unknown id\"}";
    if (!File.Exists(f.path)) return JsonSerializer.Serialize(new { error = "ファイルが見つかりません", path = f.path }, jopt);
    JsonNode? root;
    try { root = JsonNode.Parse(File.ReadAllText(f.path), null, new JsonDocumentOptions { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true }); }
    catch (Exception ex) { return JsonSerializer.Serialize(new { error = "JSON解析失敗: " + ex.Message }, jopt); }
    var entries = new List<object>();
    var comments = new List<object>();   // _comment等(キー先頭"_")=ファイル内説明。編集対象にせず別途まとめて表示。
    static string Seg(string p) => p.Contains(':') ? p.Substring(p.LastIndexOf(':') + 1) : p;
    void Walk(JsonNode? node, string path)
    {
        var seg = Seg(path);
        if (node is JsonObject o) { foreach (var kv in o) Walk(kv.Value, path == "" ? kv.Key : path + ":" + kv.Key); }
        else if (node is JsonArray a)
        {
            if (seg.StartsWith("_")) return;
            bool allPrim = a.All(e => e is JsonValue);
            bool sec = CfgIsSecret(path);
            if (allPrim) entries.Add(new { path, type = "array", value = sec ? "" : string.Join(", ", a.Select(e => e?.ToString() ?? "")), secret = sec, hasval = a.Count > 0, desc = CfgTip(path) });
            else entries.Add(new { path, type = "json", value = sec ? "" : node!.ToJsonString(jopt), secret = sec, hasval = true, desc = CfgTip(path) });
        }
        else if (node is JsonValue v)
        {
            var je = v.GetValue<JsonElement>();
            string sval = je.ValueKind switch { JsonValueKind.String => je.GetString() ?? "", JsonValueKind.True => "true", JsonValueKind.False => "false", _ => je.GetRawText() };
            if (seg.StartsWith("_")) { comments.Add(new { path, text = sval }); return; }
            string type = je.ValueKind switch { JsonValueKind.True or JsonValueKind.False => "bool", JsonValueKind.Number => "number", _ => "string" };
            bool sec = CfgIsSecret(path);
            entries.Add(new { path, type, value = sec ? "" : sval, secret = sec, hasval = !string.IsNullOrEmpty(sval), desc = CfgTip(path), choices = CfgChoices(path) });
        }
    }
    Walk(root, "");
    return JsonSerializer.Serialize(new { id = f.id, label = f.label, path = f.path, comments, entries }, jopt);
}
string CfgSave(JsonElement d)
{
    string id = d.TryGetProperty("id", out var ie) ? (ie.GetString() ?? "") : "";
    if (!d.TryGetProperty("entries", out var ents) || ents.ValueKind != JsonValueKind.Array) return "NG: entriesが必要です";
    var list = new List<(string path, string val)>();
    foreach (var e in ents.EnumerateArray())
        list.Add((e.TryGetProperty("path", out var pe) ? (pe.GetString() ?? "") : "", e.TryGetProperty("value", out var ve) ? (ve.GetString() ?? "") : ""));
    return CfgWriteEntries(id, list);
}
string CfgWriteEntries(string id, List<(string path, string val)> entries)
{
    var f = CfgReg().FirstOrDefault(x => x.id == id);
    if (f.id == null) return "NG: 不明な設定ID";
    if (!File.Exists(f.path)) return "NG: ファイルが見つかりません: " + f.path;
    JsonNode root;
    try { root = JsonNode.Parse(File.ReadAllText(f.path), null, new JsonDocumentOptions { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true })!; }
    catch (Exception ex) { return "NG: 既存JSON解析失敗: " + ex.Message; }
    int n = 0;
    foreach (var (path, val) in entries)
    {
        if (path == "") continue;
        bool sec = CfgIsSecret(path);
        if (sec && val == "") continue;   // 機密は空欄=変更なし(既存値を保持)
        var segs = path.Split(':');
        JsonNode? cur = root;
        for (int i = 0; i < segs.Length - 1 && cur != null; i++) cur = cur[segs[i]];
        if (cur == null) continue;
        var key = segs[^1];
        var existing = cur[key];
        try
        {
            if (existing is JsonArray) { var arr = new JsonArray(); foreach (var part in val.Split(',')) { var t = part.Trim(); if (t != "") arr.Add(JsonValue.Create(t)); } cur[key] = arr; }
            else if (existing is JsonObject) { cur[key] = JsonNode.Parse(val); }
            else if (existing is JsonValue jv)
            {
                var k = jv.GetValue<JsonElement>().ValueKind;
                if (k == JsonValueKind.Number) { if (long.TryParse(val, out var lv)) cur[key] = JsonValue.Create(lv); else if (double.TryParse(val, out var dv)) cur[key] = JsonValue.Create(dv); else cur[key] = JsonValue.Create(val); }
                else if (k == JsonValueKind.True || k == JsonValueKind.False) cur[key] = JsonValue.Create(val == "true" || val == "1" || val.ToLowerInvariant() == "on");
                else cur[key] = JsonValue.Create(val);
            }
            else cur[key] = JsonValue.Create(val);
            n++;
        }
        catch (Exception ex) { return "NG: 設定失敗 " + path + ": " + ex.Message; }
    }
    string outText;
    try { outText = root.ToJsonString(new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }); }
    catch (Exception ex) { return "NG: 直列化失敗: " + ex.Message; }
    try { File.Copy(f.path, f.path + ".bak_" + DateTime.Now.ToString("yyyyMMdd_HHmmss"), true); } catch { }
    try { File.WriteAllText(f.path, outText, new System.Text.UTF8Encoding(false)); } catch (Exception ex) { return "NG: 書込失敗: " + ex.Message; }
    return "OK: " + n + " 項目を保存しました(.bakバックアップ作成済)。設定の反映には対象アプリ/ランナーの再起動が必要な場合があります。";
}
List<KeyValuePair<string, string>> CfgFileLeaves(string id)
{
    var res = new List<KeyValuePair<string, string>>();
    var f = CfgReg().FirstOrDefault(x => x.id == id);
    if (f.id == null || !File.Exists(f.path)) return res;
    JsonNode? root;
    try { root = JsonNode.Parse(File.ReadAllText(f.path), null, new JsonDocumentOptions { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true }); }
    catch { return res; }
    void Walk(JsonNode? node, string path)
    {
        var seg = path.Contains(':') ? path.Substring(path.LastIndexOf(':') + 1) : path;
        if (node is JsonObject o) { foreach (var kv in o) Walk(kv.Value, path == "" ? kv.Key : path + ":" + kv.Key); }
        else if (node is JsonArray a) { if (!CfgIsSecret(path) && !seg.StartsWith("_")) { bool allPrim = a.All(e => e is JsonValue); res.Add(new(path, allPrim ? string.Join(", ", a.Select(e => e?.ToString() ?? "")) : node!.ToJsonString())); } }
        else if (node is JsonValue v) { if (!CfgIsSecret(path) && !seg.StartsWith("_")) { var je = v.GetValue<JsonElement>(); string sval = je.ValueKind switch { JsonValueKind.String => je.GetString() ?? "", JsonValueKind.True => "true", JsonValueKind.False => "false", _ => je.GetRawText() }; res.Add(new(path, sval)); } }
    }
    Walk(root, "");
    return res;
}

string ConfigHtml() => """
<!DOCTYPE html>
<html lang="ja"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="icon" href="/favicon.ico"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<title>設定ファイル編集(JRA)</title>
<style>
*{box-sizing:border-box} body{font-family:system-ui,sans-serif;margin:0;background:#0f1216;color:#e6e9ef;font-size:16px}
.wrap{max-width:720px;margin:0 auto;padding:14px}
h1{font-size:18px;margin:6px 0 12px}
a.back{color:#7aa2ff;text-decoration:none;font-size:14px}
.card{background:#1a1f27;border-radius:12px;padding:14px;margin-bottom:14px;border:1px solid #2a313c}
label{display:block;margin:12px 0 4px;color:#cdd3dd;font-size:13px}
.path{color:#8a93a3;font-size:11px;font-family:Consolas,monospace}
.tip{color:#7aa2ff;cursor:help;margin-left:6px}
input,select,textarea{width:100%;padding:9px;border-radius:8px;border:1px solid #39414d;background:#0f1216;color:#e6e9ef;font-size:15px;font-family:inherit}
textarea{min-height:60px}
.sec{border-left:3px solid #c2a23b;padding-left:8px}
.secbadge{display:inline-block;background:#3a3320;color:#e8c860;font-size:10px;padding:1px 6px;border-radius:10px;margin-left:6px}
button{padding:13px;border:none;border-radius:10px;font-size:16px;font-weight:700;color:#fff;cursor:pointer;width:100%}
.save{background:#7a5cff;margin-top:14px}
.msg{margin-top:10px;font-size:14px;min-height:18px}
.ok{color:#5fd38a}.bad{color:#ff6b6b}
.note{color:#8a93a3;font-size:12px;line-height:1.5;margin:6px 0}
</style></head><body><div class="wrap">
<h1><img src="/logo-128.png" alt="Turfora" style="height:28px;vertical-align:middle;margin-right:8px">設定ファイル編集 (JRA)</h1>
<a class="back" href="/">← コントロールに戻る</a>　<a class="back" href="/profiles">📋 プロファイル一覧 →</a>
<div class="card">
  <label>設定ファイル</label>
  <select id="file"></select>
  <p class="note" id="fpath"></p>
  <p class="note">🔒 機密項目(パスワード/PIN/INET-ID/接続文字列)は安全のため値を表示しません。変更する時だけ新しい値を入力してください(空欄=現状維持)。保存時は自動で <code>.bak</code> バックアップを作成します。各項目名の <span class="tip">ⓘ</span> にカーソルを当てると説明が出ます。</p>
</div>
<div class="card">
  <h2 style="font-size:15px;margin:0 0 8px">このファイルをプロファイル保存</h2>
  <label>プロファイル名</label><input id="pname" maxlength="40" placeholder="例: 攻め設定 / 守り設定">
  <label>コメント</label><textarea id="pcomment" maxlength="1000" placeholder="メモ(任意)"></textarea>
  <button class="save" style="background:#1f9d55" onclick="savePreset()">現在のファイル内容をプロファイル保存</button>
  <p class="note">保存=このファイルの非機密項目を名前付きで控える。保存したプロファイルの<b>一覧・呼び出し(適用)・削除</b>は <a href="/profiles" style="color:#7aa2ff">📋 プロファイル一覧ページ →</a></p>
  <div class="msg" id="pmsg"></div>
</div>
<div class="card" id="form"></div>
<button class="save" id="saveBtn" onclick="save()">保存する</button>
<div class="msg" id="msg"></div>
<script>
var CUR=null;
function esc(s){return (s==null?'':(''+s)).replace(/[&<>"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];});}
async function loadList(){
  var r=await fetch('/api/config/list'); var files=await r.json();
  var sel=document.getElementById('file'); sel.innerHTML='';
  files.forEach(function(f){ var o=document.createElement('option'); o.value=f.id; o.textContent=f.label+(f.exists?'':' (無し)'); sel.appendChild(o); });
  sel.onchange=loadFile; if(files.length) loadFile();
}
async function loadFile(){
  var id=document.getElementById('file').value; document.getElementById('msg').textContent='';
  var r=await fetch('/api/config/get?id='+encodeURIComponent(id)); var d=await r.json();
  var form=document.getElementById('form'); document.getElementById('fpath').textContent=d.path||'';
  if(d.error){ form.innerHTML='<span class="bad">'+esc(d.error)+(d.path?(' ('+esc(d.path)+')'):'')+'</span>'; CUR=null; return; }
  CUR=d; var h='';
  if(d.comments && d.comments.length){
    var tipText=d.comments.map(function(c){ return c.path.split(':').pop()+': '+c.text; }).join('\n\n');
    h+='<div style="margin-bottom:10px"><span class="tip" title="'+esc(tipText)+'" style="font-size:13px;color:#9ec1ff">📄 このファイルの説明（ⓘ にカーソルを当てると表示）</span></div>';
  }
  d.entries.forEach(function(en,i){
    var tip=en.desc?(' <span class="tip" title="'+esc(en.desc)+'">ⓘ</span>'):'';
    var sb=en.secret?'<span class="secbadge">機密</span>':'';
    h+='<div class="'+(en.secret?'sec':'')+'">';
    h+='<label>'+esc(en.path.split(':').pop())+sb+tip+'<br><span class="path">'+esc(en.path)+'</span></label>';
    var idAttr='f'+i;
    if(en.type==='bool'){
      h+='<select id="'+idAttr+'"><option value="true"'+(en.value==='true'?' selected':'')+'>true</option><option value="false"'+(en.value!=='true'?' selected':'')+'>false</option></select>';
    } else if(en.secret){
      h+='<input id="'+idAttr+'" type="password" autocomplete="new-password" placeholder="'+(en.hasval?'●●●●(設定済・変更時のみ入力)':'(未設定)')+'">';
    } else if(en.choices && en.choices.length){
      var opts=en.choices.slice(); if(en.value && opts.indexOf(en.value)<0) opts.unshift(en.value);
      h+='<select id="'+idAttr+'">'+opts.map(function(o){return '<option'+(o===en.value?' selected':'')+'>'+esc(o)+'</option>';}).join('')+'</select>';
    } else if(en.type==='json'||(en.value&&en.value.length>60)){
      h+='<textarea id="'+idAttr+'">'+esc(en.value)+'</textarea>';
    } else if(en.type==='number'){
      h+='<input id="'+idAttr+'" type="text" inputmode="numeric" value="'+esc(en.value)+'">';
    } else {
      h+='<input id="'+idAttr+'" type="text" value="'+esc(en.value)+'">';
    }
    h+='</div>';
  });
  form.innerHTML=h;
}
async function loadPresets(){
  if(!CUR){return;}
  var r=await fetch('/api/config/presets?id='+encodeURIComponent(CUR.id)); var ps=await r.json();
  var el=document.getElementById('plist');
  if(!ps.length){ el.innerHTML='<p class="note">(このファイルのプロファイルなし)</p>'; return; }
  var h='';
  ps.forEach(function(p){
    h+='<div style="border:1px solid #2a313c;border-radius:8px;padding:8px 10px;margin-bottom:6px;background:#0f1216">';
    h+='<div style="display:flex;justify-content:space-between;gap:8px"><b style="font-size:14px">'+esc(p.name)+'</b><span class="note" style="margin:0;white-space:nowrap">'+esc(p.savedAt||'')+' / '+p.count+'項目</span></div>';
    if(p.comment){ h+='<div class="note" style="margin:3px 0;cursor:help;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="'+esc(p.comment)+'">'+esc(p.comment)+'</div>'; }
    h+='<div style="display:flex;gap:6px;margin-top:6px">';
    h+='<button style="flex:1;padding:7px;font-size:13px;background:#2b6cb0;border-radius:6px" onclick="applyPreset('+JSON.stringify(p.name)+')">適用(呼び出し)</button>';
    h+='<button style="flex:1;padding:7px;font-size:13px;background:#3a2530;color:#ff9a9a;border-radius:6px" onclick="delPreset('+JSON.stringify(p.name)+')">削除</button>';
    h+='</div></div>';
  });
  el.innerHTML=h;
}
async function loadAllProfiles(){
  var r=await fetch('/api/config/presets/all'); var ps=await r.json();
  var el=document.getElementById('allprofiles'); if(!el){return;}
  if(!ps.length){ el.innerHTML='<p class="note">(保存済みプロファイルなし)</p>'; return; }
  var groups={}, order=[];
  ps.forEach(function(p){ var k=p.fileLabel||'(不明)'; if(!groups[k]){ groups[k]=[]; order.push(k); } groups[k].push(p); });
  var h='<p class="note" style="margin:0 0 8px">各プロファイルは「対象ファイル」の設定のみを保存します。ファイル別に表示：</p>';
  order.forEach(function(fl){
    h+='<div style="margin-bottom:8px"><div style="font-size:12px;color:#9ec1ff;font-weight:700;border-bottom:1px solid #2a313c;padding-bottom:3px;margin-bottom:5px">'+esc(fl)+'</div>';
    groups[fl].forEach(function(p){
      h+='<div style="border:1px solid #2a313c;border-radius:8px;padding:7px 10px;margin-bottom:5px;background:#0f1216">';
      h+='<div style="display:flex;justify-content:space-between;gap:8px"><b style="font-size:14px">'+esc(p.name)+'</b><span class="note" style="margin:0;white-space:nowrap">'+esc(p.savedAt||'')+' / '+p.count+'項目</span></div>';
      if(p.comment){ h+='<div class="note" style="margin:3px 0;cursor:help;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="'+esc(p.comment)+'">'+esc(p.comment)+'</div>'; }
      h+='<div style="display:flex;gap:6px;margin-top:5px">';
      h+='<button style="flex:1;padding:6px;font-size:12px;background:#2b6cb0;border-radius:6px" onclick="applyProfile('+JSON.stringify(p.id)+','+JSON.stringify(p.name)+')">適用</button>';
      h+='<button style="flex:1;padding:6px;font-size:12px;background:#3a2530;color:#ff9a9a;border-radius:6px" onclick="delProfile('+JSON.stringify(p.id)+','+JSON.stringify(p.name)+')">削除</button>';
      h+='</div></div>';
    });
    h+='</div>';
  });
  el.innerHTML=h;
}
async function applyProfile(id,name){
  if(!confirm('プロファイル「'+name+'」を適用しますか？(.bakバックアップを作成します)')){return;}
  var r=await fetch('/api/config/presets/apply',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:id,name:name})});
  var t=await r.text(); alert(t);
  if(CUR && CUR.id===id){ loadFile(); } else { loadAllProfiles(); }
}
async function delProfile(id,name){
  if(!confirm('プロファイル「'+name+'」を削除しますか？')){return;}
  await fetch('/api/config/presets/delete',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:id,name:name})});
  if(CUR && CUR.id===id){ loadPresets(); } else { loadAllProfiles(); }
}
async function savePreset(){
  if(!CUR){return;}
  var name=document.getElementById('pname').value.trim();
  var comment=document.getElementById('pcomment').value;
  var pm=document.getElementById('pmsg'); if(!name){ pm.textContent='プリセット名を入力してください'; pm.className='msg bad'; return; }
  pm.textContent='保存中…'; pm.className='msg';
  var r=await fetch('/api/config/presets',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:CUR.id,name:name,comment:comment})});
  var t=await r.text(); pm.textContent=t; pm.className='msg '+(t.indexOf('OK')===0?'ok':'bad');
  if(t.indexOf('OK')===0){ document.getElementById('pname').value=''; document.getElementById('pcomment').value=''; }
}
async function applyPreset(name){
  if(!CUR || !confirm('プリセット「'+name+'」をこのファイルに適用しますか？(.bakバックアップを作成します)')){return;}
  var pm=document.getElementById('pmsg'); pm.textContent='適用中…'; pm.className='msg';
  var r=await fetch('/api/config/presets/apply',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:CUR.id,name:name})});
  var t=await r.text(); pm.textContent=t; pm.className='msg '+(t.indexOf('[適用')===0&&t.indexOf('OK')>0?'ok':'bad');
  loadFile();
}
async function delPreset(name){
  if(!CUR || !confirm('プリセット「'+name+'」を削除しますか？')){return;}
  var r=await fetch('/api/config/presets/delete',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:CUR.id,name:name})});
  var t=await r.text(); var pm=document.getElementById('pmsg'); pm.textContent=t; pm.className='msg '+(t.indexOf('OK')===0?'ok':'bad'); loadPresets();
}
async function save(){
  if(!CUR){return;}
  var msg=document.getElementById('msg'); msg.textContent='保存中…'; msg.className='msg';
  var entries=[];
  CUR.entries.forEach(function(en,i){
    var el=document.getElementById('f'+i); if(!el) return;
    var v=el.value;
    if(en.secret && v==='') return;
    if(v===en.value) return;
    entries.push({path:en.path, value:v});
  });
  if(entries.length===0){ msg.textContent='変更はありません。'; return; }
  var r=await fetch('/api/config/save',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:CUR.id,entries:entries})});
  var t=await r.text(); msg.textContent=t; msg.className='msg '+(t.indexOf('OK')===0?'ok':'bad');
  if(t.indexOf('OK')===0){ loadFile(); }
}
loadList();
</script>
</div></body></html>
""";

string ProfilesHtml() => """
<!DOCTYPE html>
<html lang="ja"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="icon" href="/favicon.ico"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<title>プロファイル一覧</title>
<style>
*{box-sizing:border-box} body{font-family:system-ui,sans-serif;margin:0;background:#0f1216;color:#e6e9ef;font-size:16px}
.wrap{max-width:720px;margin:0 auto;padding:14px}
h1{font-size:18px;margin:6px 0 12px}
a.back{color:#7aa2ff;text-decoration:none;font-size:14px}
.card{background:#1a1f27;border-radius:12px;padding:14px;margin-bottom:14px;border:1px solid #2a313c}
.note{color:#8a93a3;font-size:12px;line-height:1.5;margin:6px 0}
button{padding:7px;border:none;border-radius:6px;font-size:13px;font-weight:700;color:#fff;cursor:pointer}
.msg{margin-top:8px;font-size:14px;min-height:18px}.ok{color:#5fd38a}.bad{color:#ff6b6b}
</style></head><body><div class="wrap">
<h1><img src="/logo-128.png" alt="Turfora" style="height:28px;vertical-align:middle;margin-right:8px">📋 プロファイル一覧 (JRA)</h1>
<a class="back" href="/config">← 設定ファイル編集に戻る</a>　<a class="back" href="/">コントロール</a>
<p class="note">各プロファイルは「対象ファイル」の非機密設定のみを保存しています。適用(呼び出し)＝その内容を対象ファイルへ書戻し(.bakバックアップ作成・機密は現状維持)。保存は設定ファイル編集ページで行います。</p>
<div class="card" id="list"><p class="note">読込中…</p></div>
<div class="msg" id="msg"></div>
<script>
function esc(s){return (s==null?'':(''+s)).replace(/[&<>"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];});}
async function load(){
  var r=await fetch('/api/config/presets/all'); var ps=await r.json();
  var el=document.getElementById('list');
  if(!ps.length){ el.innerHTML='<p class="note">(保存済みプロファイルなし)</p>'; return; }
  var groups={},order=[];
  ps.forEach(function(p){ var k=p.fileLabel||'(不明)'; if(!groups[k]){ groups[k]=[]; order.push(k); } groups[k].push(p); });
  var palette=[['#3b82f6','rgba(59,130,246,0.10)'],['#10b981','rgba(16,185,129,0.10)'],['#f59e0b','rgba(245,158,11,0.10)'],['#a78bfa','rgba(167,139,250,0.10)'],['#ec4899','rgba(236,72,153,0.10)'],['#22d3ee','rgba(34,211,238,0.10)']];
  var h='';
  order.forEach(function(fl,gi){
    var c=palette[gi % palette.length];
    h+='<div style="border:2px solid '+c[0]+';border-radius:10px;padding:10px 12px;margin-bottom:14px;background:'+c[1]+'">';
    h+='<div style="color:'+c[0]+';font-weight:700;font-size:14px;margin-bottom:8px">'+esc(fl)+'</div>';
    groups[fl].forEach(function(p){
      h+='<div style="border:1px solid '+c[0]+';border-radius:8px;padding:8px 10px;margin-bottom:6px;background:#0f1216">';
      h+='<div style="display:flex;justify-content:space-between;gap:8px"><b style="font-size:14px">'+esc(p.name)+'</b><span class="note" style="margin:0;white-space:nowrap">'+esc(p.savedAt||'')+' / '+p.count+'項目</span></div>';
      if(p.comment){ h+='<div class="note" style="margin:3px 0;white-space:pre-wrap">'+esc(p.comment)+'</div>'; }
      h+='<div style="display:flex;gap:6px;margin-top:6px">';
      h+='<button style="flex:1;background:#2b6cb0" onclick="applyP('+JSON.stringify(p.id)+','+JSON.stringify(p.name)+')">適用(呼び出し)</button>';
      h+='<button style="flex:1;background:#3a2530;color:#ff9a9a" onclick="delP('+JSON.stringify(p.id)+','+JSON.stringify(p.name)+')">削除</button>';
      h+='</div></div>';
    });
    h+='</div>';
  });
  el.innerHTML=h;
}
async function applyP(id,name){
  if(!confirm('プロファイル「'+name+'」を対象ファイルへ適用しますか？(.bakバックアップを作成します)')){return;}
  var m=document.getElementById('msg'); m.textContent='適用中…'; m.className='msg';
  var r=await fetch('/api/config/presets/apply',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:id,name:name})});
  var t=await r.text(); m.textContent=t; m.className='msg '+(t.indexOf('OK')>0?'ok':'bad'); load();
}
async function delP(id,name){
  if(!confirm('プロファイル「'+name+'」を削除しますか？')){return;}
  var r=await fetch('/api/config/presets/delete',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:id,name:name})});
  var t=await r.text(); var m=document.getElementById('msg'); m.textContent=t; m.className='msg '+(t.indexOf('OK')===0?'ok':'bad'); load();
}
load();
</script>
</div></body></html>
""";

string Html() => """
<!DOCTYPE html>
<html lang="ja"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>中央競馬(JRA) 自動投票 コントロール</title>
<link rel="icon" href="/favicon.ico"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<style>
*{box-sizing:border-box} body{font-family:system-ui,sans-serif;margin:0;background:#0f1216;color:#e6e9ef;font-size:16px}
.wrap{max-width:640px;margin:0 auto;padding:14px}
h1{font-size:18px;margin:6px 0 12px}
.card{background:#1a1f27;border-radius:12px;padding:14px;margin-bottom:14px;border:1px solid #2a313c}
.row{display:flex;justify-content:space-between;padding:4px 0;border-bottom:1px solid #232a34}
.row:last-child{border:none}
.k{color:#9aa4b2} .v{font-weight:600}
.big{font-size:22px}
.btns{display:flex;gap:10px;margin-top:10px}
button{flex:1;padding:14px;border:none;border-radius:10px;font-size:16px;font-weight:700;color:#fff;cursor:pointer}
.start{background:#1f9d55} .stop{background:#c23b3b} .restart{background:#2b6cb0}
label{display:block;margin:10px 0 4px;color:#9aa4b2;font-size:14px}
input,select,textarea{width:100%;padding:10px;border-radius:8px;border:1px solid #39414d;background:#0f1216;color:#e6e9ef;font-size:16px;box-sizing:border-box;font-family:inherit}
.chk{display:flex;align-items:center;gap:8px;margin:8px 0}.chk input{width:auto}
.save{background:#7a5cff;margin-top:14px}
.prow{border:1px solid #2a313c;border-radius:8px;padding:8px 10px;margin-top:8px;background:#0f1216}
.phead{display:flex;justify-content:space-between;align-items:baseline;gap:8px}.phead b{font-size:14px}
.pdate{color:#8a93a3;font-size:11px;white-space:nowrap}
.pcom{color:#cdd3dd;font-size:12px;margin-top:3px;cursor:help;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.psum{color:#8a93a3;font-size:11px;margin-top:3px}
.pbtn{margin-top:6px;display:flex;gap:6px}
.pbtn button{flex:1;margin-top:0;padding:7px;font-size:13px;background:#2a313c;border:none;border-radius:6px;color:#e6e9ef}
.pbtn button.del{background:#3a2530;color:#ff9a9a}
pre{background:#0a0d11;border-radius:8px;padding:10px;overflow:auto;max-height:300px;font-size:12px;line-height:1.5;white-space:pre-wrap}
.msg{margin-top:8px;font-size:14px;min-height:18px}
.ok{color:#5fd38a}.bad{color:#ff6b6b}
.pl-plus{color:#5fd38a}.pl-minus{color:#ff6b6b}
.pill{display:inline-block;padding:2px 10px;border-radius:20px;font-size:13px;font-weight:700}
.run{background:#13402a;color:#5fd38a}.idle{background:#3a2530;color:#ff9a9a}
.warn{background:#3a3120;color:#ffd479;padding:8px 10px;border-radius:8px;font-size:12px;margin-bottom:10px}
</style></head><body><div class="wrap">
<h1 style="display:flex;align-items:center;gap:10px"><img src="/icon-32.png" width="30" height="30" style="border-radius:7px" alt="Turfora">中央競馬(JRA) 自動投票 コントロール</h1>
<div style="margin:-4px 0 10px"><a href="/history" style="color:#7aa2ff;text-decoration:none;font-size:14px">📋 投票履歴を見る →</a>　<a href="/ledger" style="color:#7aa2ff;text-decoration:none;font-size:14px">📒 台帳を見る →</a>　<a href="/retro" style="color:#7aa2ff;text-decoration:none;font-size:14px">📒 日次総括・深掘り →</a>　<a href="/races" style="color:#7aa2ff;text-decoration:none;font-size:14px">🐎 買目・投票 →</a>　<a href="/win5" style="color:#7aa2ff;text-decoration:none;font-size:14px">🎯 WIN5点数 →</a>　<a href="/config" style="color:#7aa2ff;text-decoration:none;font-size:14px">🛠 設定ファイル →</a>　<a href="/profiles" style="color:#7aa2ff;text-decoration:none;font-size:14px">📋 プロファイル →</a></div>
<div class="warn">Mode「通知のみ」=買目作成＋通知のみで<b>実投票しません</b>。DryRun/ConfirmStop/Autoで実投票が有効化されます(Auto=無人で実金が動く)。IPAT実DOM較正前は通知のみで運用してください。</div>

<div class="card">
  <div class="row"><span class="k">ランナー</span><span class="v big" id="st-runner">…</span></div>
  <div class="row"><span class="k">確定収支(本日・自動)</span><span class="v" id="st-pl">…</span></div>
  <div class="row"><span class="k">手動投票(本日)</span><span class="v" id="st-mpl">…</span></div>
  <div class="row"><span class="k">全体収支(本日・自動+手動) <a href="#" onclick="refreshIpatPl(event)" style="font-size:12px;color:#7aa2ff;text-decoration:none;font-weight:600" title="IPAT投票履歴を当日の結果と突合して収支を最新化">🔄更新</a></span><span class="v" id="st-apl">…</span></div>
  <div class="row"><span class="k">投票可能額(残高) <a href="#" onclick="refreshHomeBal(event)" style="font-size:12px;color:#7aa2ff;text-decoration:none;font-weight:600" title="IPATにログインして残高を照会・最新化">🔄更新</a></span><span class="v" id="st-bal">…</span></div>
  <div class="row"><span class="k">現在の設定</span><span class="v" id="st-mode">…</span></div>
  <div class="row"><span class="k">タスク</span><span class="v" id="st-task">…</span></div>
  <div class="row"><span class="k">最終起動</span><span class="v" id="st-last">…</span></div>
  <div class="row"><span class="k">次レース</span><span class="v" id="st-next">…</span></div>
  <div class="row"><span class="k">投票内容</span><span class="v" id="st-nextbet">…</span></div>
  <div class="btns">
    <button class="start" onclick="ctl('start')">起動</button>
    <button class="stop" onclick="ctl('stop')">停止</button>
    <button class="restart" onclick="ctl('restart')">再起動</button>
  </div>
  <div class="msg" id="ctl-msg"></div>
</div>

<div class="card">
  <div class="row"><span class="k">ライブ中継</span><span class="v" style="font-size:12px;color:#8a93a3">サーバのデスクトップに表示・視聴のみ</span></div>
  <button onclick="openLive()" style="background:#2b6cb0;margin-top:8px">📺 サーバでライブを開く（sp.gch.jp/jra）</button>
  <div class="msg" id="live-msg"></div>
</div>

<div class="card">
  <div class="row"><span class="k">ランナーログ（自動更新）</span><span class="v" id="st-now"></span></div>
  <pre id="log">…</pre>
</div>

<div class="card">
  <h1 style="font-size:15px">パラメータ（保存→次の起動/再起動で有効）</h1>
  <label>Mode（通知のみ=無投票 / DryRun / ConfirmStop / Auto=実課金）</label>
  <select id="p-mode"><option>通知のみ</option><option>DryRun</option><option>ConfirmStop</option><option>Auto</option></select>
  <label>式別（買目）／検証=複勝が全帯で回収最高(79-90%)・ワイド相手3も堅で86%</label>
  <select id="p-bet"><option>複勝</option><option>ワイド</option><option>馬連</option><option>三連複</option><option>単勝</option></select>
  <label>相手頭数（軸1頭流し / 絞るほど回収↑・的中↓。検証=ワイド相手3が最良）</label><input id="p-partners" type="number" min="1" max="7">
  <label>1点金額（円）</label><input id="p-stake" type="number" step="100">
  <label>Lead（初R発走の何分前にループ開始）</label><input id="p-lead" type="number">
  <label>取得間隔（馬体重の再取得間隔・分）</label><input id="p-interval" type="number">
  <label>投票窓（発走の何分前から投票対象に・分）</label><input id="p-votewithin" type="number">
  <label>前半フラット100円（≤このRを1点100円固定 / 0=無効）</label><input id="p-frontflat" type="number" min="0" max="12">
  <label>変更情報 取得開始（初R発走の何分前から・分）</label><input id="p-changelead" type="number" min="0" max="120">
  <label>変更情報 取得間隔（分）</label><input id="p-changeint" type="number" min="1" max="30">
  <label>オッズ 取得間隔（分・開催中に単複/人気を定期取得）</label><input id="p-oddsint" type="number" min="1" max="30">
  <div class="chk"><input id="p-nomail" type="checkbox"><span>メール通知を送らない（NoMail）</span></div>
  <button class="save" onclick="saveParams()">パラメータ保存</button>
  <div class="msg" id="p-msg"></div>
</div>

<div class="card">
  <h1 style="font-size:15px">プリセット（複数保存・呼び出し）</h1>
  <label>プリセット名</label><input id="pr-name" type="text" maxlength="40" placeholder="例: 通知のみ / 本番Auto">
  <label>コメント（任意・長文可。一覧ではツールチップで全文表示）</label>
  <textarea id="pr-comment" rows="2" maxlength="1000" placeholder="メモ"></textarea>
  <button class="save" onclick="savePreset()">現在のパラメータをプリセット保存</button>
  <div class="msg" id="pr-msg"></div>
  <div id="pr-list" style="margin-top:10px"></div>
</div>

<script>
async function jget(u){ const r=await fetch(u); return r.ok? r.json():null; }
async function ttext(u,m,b){ const o={method:m||'GET'}; if(b){o.body=JSON.stringify(b);o.headers={'Content-Type':'application/json'};} const r=await fetch(u,o); return r.text(); }
function setMsg(id,t,cls){ const e=document.getElementById(id); e.textContent=t; e.className='msg '+(cls||''); }
async function loadStatus(){
  const s=await jget('/api/status'); if(!s)return;
  const rc=s.runnerCount;
  document.getElementById('st-runner').innerHTML = rc==1 ? '<span class="pill run">稼働中 1本</span>' : (rc==0 ? '<span class="pill idle">停止中</span>' : '<span class="pill idle">⚠ '+rc+'本(二重)</span>');
  (function(){ const e=document.getElementById('st-pl'); const pl=s.plToday;
    const sg=(n)=>(n>=0?'+':'-')+'¥'+Math.abs(n).toLocaleString();
    if(pl==null){ e.textContent=(s.plTotal!=null?'— ／ 累計'+sg(s.plTotal):'—'); e.className='v'; return; }  // 本日0でも累計は表示(全体=自動+手動の整合が見えるように)
    let t=sg(pl);
    if(s.plInv>0){ t+=' (的中'+s.plHit+'/'+s.plDone+'・回収'+Math.round(100*s.plRet/s.plInv)+'%)'; }
    else if(s.plDone>0){ t+=' (的中'+s.plHit+'/'+s.plDone+')'; }
    if(s.plTotal!=null){ t+=' ／ 累計'+sg(s.plTotal); }
    e.textContent=t; e.className='v '+(pl>=0?'pl-plus':'pl-minus'); })();
  // 手動投票(本日)・全体収支(本日・自動+手動)=地方と同じ構成。pl=払戻-投票(計画ペーパー含む確定分)。
  function fillPL(id,pl,inv,ret,hit,done,total){ const e=document.getElementById(id); if(!e)return;
    const sg=(n)=>(n>=0?'+':'-')+'¥'+Math.abs(n).toLocaleString();
    if(pl==null||done==0){ e.textContent=(total!=null?'— ／ 累計'+sg(total):'—'); e.className='v'; return; }  // 本日0でも累計は表示
    let t=sg(pl)+' ('+(inv>0?'的中'+hit+'/'+done+'・回収'+Math.round(100*ret/inv)+'%':'的中'+hit+'/'+done)+')';
    if(total!=null){ t+=' ／ 累計'+sg(total); }
    e.textContent=t; e.className='v '+(pl>=0?'pl-plus':'pl-minus'); }
  fillPL('st-mpl',s.plManToday,s.plManInv,s.plManRet,s.plManHit,s.plManDone,s.plManTotal);
  fillPL('st-apl',s.plAllToday,s.plAllInv,s.plAllRet,s.plAllHit,s.plAllDone,s.plAllTotal);
  document.getElementById('st-mode').textContent = (s.curMode||'—')+' / '+(s.curBet||'')+' 相手'+(s.curPartners!=null?s.curPartners:'')+' ¥'+(s.curStake!=null?Number(s.curStake).toLocaleString():'');
  document.getElementById('st-task').textContent = s.taskState+' / '+s.lastResult;
  document.getElementById('st-last').textContent = s.lastRun||'—';
  (function(){ const e=document.getElementById('st-next');
    e.textContent = s.nextVenue ? (s.nextVenue+s.nextRace+'R '+(s.nextPost||'')+'発走'+(s.nextVoteAt?'（投票 '+s.nextVoteAt+'〜）':'')+(s.nextConf?' [軸確度:'+s.nextConf+']':'')) : '—（本日の未発走レースなし）'; })();
  (function(){ const e=document.getElementById('st-nextbet');
    if(s.nextVoted && s.nextActual){ e.textContent = s.nextActual; }
    else if(s.nextAxis){ e.textContent='◎'+s.nextAxis+(s.nextAxisName?' '+s.nextAxisName:'')+'→相手 '+(s.nextPartners||'')+' ['+(s.nextBet||'')+']（投票前）'; }
    else { e.textContent = s.nextVenue ? '—（買目CSV未生成・ランナー起動で作成）' : '—'; } })();
  window.__nextVenue = s.nextVenue || '';
  document.getElementById('st-now').textContent = s.now;
}
// 全体収支「更新」: IPAT投票履歴を当日結果と突合(精算)→状態を再読込して収支を最新化。
async function refreshIpatPl(ev){ if(ev){ev.preventDefault();ev.stopPropagation();}
  var a=(ev&&ev.target&&ev.target.tagName==='A')?ev.target:null; if(a){a.textContent='更新中…';a.style.pointerEvents='none';}
  try{ var r=await fetch('/api/ipat-settle',{method:'POST'}); var j=await r.json();
    await loadStatus();
    if(j&&j.ok===false){ alert('更新失敗: '+(j.message||'')); }
    else if(a){ a.textContent='🔄更新'+((j&&j.settled>0)?'（'+j.settled+'件精算）':''); }
  }catch(e){ alert('更新に失敗しました'); }
  finally{ if(a){a.style.pointerEvents=''; setTimeout(function(){ a.textContent='🔄更新'; },4000);} }
  return false;
}
// 投票可能額(残高)。初期/tick=直近値(照会せず)、更新ボタン=IpatVote balance照会→ポーリング。買目画面と同じAPI。
async function loadHomeBal(){
  try{ var j=await (await fetch('/api/ipat-balance')).json(); var el=document.getElementById('st-bal'); if(!el)return;
    if(('' +el.textContent).indexOf('照会中')>=0)return;   // 照会中は上書きしない
    if(j&&j.balance!=null){ el.textContent=Number(j.balance).toLocaleString()+'円'+(j.balT?'（'+j.balT+'）':''); el.className='v'; el.style.color='#e6e9ef'; }
    else { el.textContent='未取得'; el.style.color='#8a93a3'; } }catch(e){}
}
async function refreshHomeBal(ev){ if(ev){ev.preventDefault();ev.stopPropagation();}
  var el=document.getElementById('st-bal'), a=(ev&&ev.target&&ev.target.tagName==='A')?ev.target:null;
  if(el){el.textContent='照会中…（IPATログイン）';el.style.color='#e6e9ef';} if(a){a.style.pointerEvents='none';}
  try{ await fetch('/api/ipat-balance-refresh',{method:'POST'}); }catch(e){}
  var tries=0; var timer=setInterval(async function(){ tries++;
    try{ var s=await (await fetch('/api/ipat-balance-status')).json();
      if(s&&s.done){ clearInterval(timer); if(a){a.style.pointerEvents='';}
        if(s.balance!=null){ el.textContent=Number(s.balance).toLocaleString()+'円'; el.style.color='#7ee787'; }
        else { el.textContent=(s.message||'未取得'); el.style.color='#ffb454'; el.title=s.message||''; } } }catch(e){}
    if(tries>45){ clearInterval(timer); if(a){a.style.pointerEvents='';} if((''+el.textContent).indexOf('照会中')>=0){ el.textContent='タイムアウト'; el.style.color='#ff8a8a'; } }
  },2000);
  return false;
}
function applyToForm(p){
  document.getElementById('p-mode').value=p.mode;
  document.getElementById('p-bet').value=p.betType;
  document.getElementById('p-partners').value=p.partners;
  document.getElementById('p-stake').value=p.stake;
  document.getElementById('p-lead').value=p.lead;
  document.getElementById('p-interval').value=p.interval;
  document.getElementById('p-votewithin').value=p.voteWithin;
  document.getElementById('p-frontflat').value=(p.frontFlat==null?0:p.frontFlat);
  document.getElementById('p-changelead').value=(p.changeLeadMin==null?30:p.changeLeadMin);
  document.getElementById('p-changeint').value=(p.changeInterval==null?3:p.changeInterval);
  document.getElementById('p-oddsint').value=(p.oddsInterval==null?5:p.oddsInterval);
  document.getElementById('p-nomail').checked=p.noMail;
}
function formParams(){ return { mode:document.getElementById('p-mode').value, betType:document.getElementById('p-bet').value,
  partners:+document.getElementById('p-partners').value, stake:+document.getElementById('p-stake').value,
  lead:+document.getElementById('p-lead').value, interval:+document.getElementById('p-interval').value,
  voteWithin:+document.getElementById('p-votewithin').value, frontFlat:+document.getElementById('p-frontflat').value,
  changeLeadMin:+document.getElementById('p-changelead').value, changeInterval:+document.getElementById('p-changeint').value,
  oddsInterval:+document.getElementById('p-oddsint').value, noMail:document.getElementById('p-nomail').checked }; }
async function loadParams(){ const p=await jget('/api/params'); if(!p)return; applyToForm(p); }
async function saveParams(){ setMsg('p-msg','保存中…'); const t=await ttext('/api/params','POST',formParams()); setMsg('p-msg',t, t.startsWith('OK')?'ok':'bad'); }
var PRESETS=[];
function esc(s){ return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
async function loadPresets(){
  try{ const r=await fetch('/api/presets'); PRESETS=await r.json(); }catch(e){ PRESETS=[]; }
  const el=document.getElementById('pr-list');
  if(!PRESETS.length){ el.innerHTML='<div style="color:#888;font-size:12px">保存済みプリセットはありません</div>'; return; }
  el.innerHTML=PRESETS.map(function(p,i){
    var c=p.comment||''; var short=c.length>36?c.slice(0,36)+'…':c; var pm=p.params||{};
    var sum='Mode'+esc(pm.mode)+'/'+esc(pm.betType)+'相手'+esc(pm.partners)+'/¥'+esc(pm.stake)+(pm.noMail?'/通知OFF':'');
    return '<div class="prow"><div class="phead"><b>'+esc(p.name)+'</b> <span class="pdate">'+esc(p.savedAt)+'</span></div>'
      +(c?'<div class="pcom" title="'+esc(c)+'">'+esc(short)+'</div>':'')
      +'<div class="psum">'+sum+'</div>'
      +'<div class="pbtn"><button onclick="applyPreset('+i+')">適用</button> <button onclick="editPreset('+i+')">編集</button> <button class="del" onclick="deletePreset('+i+')">削除</button></div></div>';
  }).join('');
}
async function savePreset(){
  var name=document.getElementById('pr-name').value.trim();
  if(!name){ setMsg('pr-msg','プリセット名を入力してください','bad'); return; }
  setMsg('pr-msg','保存中…');
  var t=await ttext('/api/presets','POST',{name:name,comment:document.getElementById('pr-comment').value,params:formParams()});
  setMsg('pr-msg',t, t.startsWith('OK')?'ok':'bad'); loadPresets();
}
async function applyPreset(i){ var p=PRESETS[i]; if(!confirm('プリセット「'+p.name+'」を適用しますか？\n(次回の起動/再起動から有効)')) return;
  setMsg('pr-msg','適用中…'); var t=await ttext('/api/presets/apply','POST',{name:p.name}); setMsg('pr-msg',t, t.indexOf('OK')>=0?'ok':'bad'); loadParams(); }
function editPreset(i){ var p=PRESETS[i]; if(p.params) applyToForm(p.params); document.getElementById('pr-name').value=p.name; document.getElementById('pr-comment').value=p.comment||'';
  setMsg('pr-msg','「'+p.name+'」を編集用に読込みました。値を変えて「プリセット保存」で上書き／「パラメータ保存」で即適用。'); window.scrollTo(0,0); }
async function deletePreset(i){ var p=PRESETS[i]; if(!confirm('プリセット「'+p.name+'」を削除しますか？')) return;
  var t=await ttext('/api/presets/delete','POST',{name:p.name}); setMsg('pr-msg',t, t.startsWith('OK')?'ok':'bad'); loadPresets(); }
async function ctl(a){
  if(a!=='stop' && document.getElementById('p-mode').value==='Auto'){ if(!confirm('Mode=Auto（実課金）で'+a+'します。よろしいですか？')) return; }
  setMsg('ctl-msg', a+'中…');
  const t=await ttext('/api/control/'+a,'POST');
  setMsg('ctl-msg',t,'ok');
  setTimeout(loadStatus,1500);
}
async function openLive(){
  setMsg('live-msg','起動中…（サーバのデスクトップにChromeが開きます。初回はグリーンチャンネル会員ログインを）');
  const v = window.__nextVenue || '';
  const t = await ttext('/api/live/'+encodeURIComponent(v),'POST');
  setMsg('live-msg', t, t.indexOf('OK')>=0?'ok':'bad');
}
async function loadLog(){
  const el=document.getElementById('log');
  const atBottom = (el.scrollHeight - el.scrollTop - el.clientHeight) < 40; // 更新前に最下部付近か
  const t=await (await fetch('/api/log')).text();
  el.textContent=t;
  if(atBottom){ el.scrollTop = el.scrollHeight; } // 最下部にいた時だけ最新へ追従(過去ログ閲覧中は追従しない)
}
function tick(){ loadStatus(); loadLog(); loadHomeBal(); }
loadParams(); loadPresets(); tick(); setInterval(tick,5000);
</script>
</div></body></html>
""";

string HistoryHtml() => """
<!doctype html><html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>投票履歴(JRA)</title>
<link rel="icon" href="/favicon.ico"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<style>
*{box-sizing:border-box}body{margin:0;background:#0b0e13;color:#e6e9ef;font-family:system-ui,'Segoe UI',sans-serif}
.wrap{max-width:1000px;margin:0 auto;padding:14px}
h1{font-size:18px;margin:6px 0}
a.back{color:#7aa2ff;text-decoration:none;font-size:14px}
.note{color:#8a93a3;font-size:12px;margin:6px 0 8px}
.filters{display:flex;flex-wrap:wrap;gap:6px;margin:8px 0}
.filters select,.filters input,.filters button{padding:6px 8px;border-radius:6px;border:1px solid #39414d;background:#0f1216;color:#e6e9ef;font-size:13px}
.filters button{background:#2a313c;cursor:pointer}
table{width:100%;border-collapse:collapse;font-size:12px}
th,td{padding:6px 5px;border-bottom:1px solid #222a35;text-align:left;white-space:nowrap}
th{color:#8a93a3;font-weight:600;position:sticky;top:0;background:#0b0e13}
td.r,th.r{text-align:right}
tr.grp td{background:#161b22;color:#cdd3dd;font-weight:600;font-size:12px}
tr.rc:hover td{background:#1b2230}
.hit{color:#5fd38a;font-weight:700}.miss{color:#9aa3b2}
.plus{color:#5fd38a}.minus{color:#ff6b6b}.pend{color:#8a93a3}
.badge{display:inline-block;padding:1px 7px;border-radius:10px;font-size:11px}
.b-run{background:#13402a;color:#5fd38a}.b-man{background:#3a3120;color:#ffd479}
</style></head><body><div class="wrap">
<a class="back" href="/">← コントロールに戻る</a>
<h1>投票履歴(JRA)</h1>
<div class="note">dbo.IPAT投票履歴（ランナーの全投票・直近300件）。的中=確定済かつ払戻金額&gt;0。</div>
<div class="filters">
  <select id="f-venue" onchange="render()"></select>
  <select id="f-type" onchange="render()"></select>
  <select id="f-date" onchange="render()"></select>
  <select id="f-state" onchange="render()"><option value="">状態(全)</option><option>的中</option><option>不的中</option><option>結果待ち</option></select>
  <select id="f-src" onchange="render()"><option value="">元(全)</option><option value="runner">🤖ランナー</option><option value="manual">✋手動</option></select>
  <input id="f-q" type="search" placeholder="買い目/馬番で絞込" oninput="render()" size="12">
  <select id="f-group" onchange="render()"><option value="">グループ化なし</option><option value="date">開催日で</option><option value="venue">場で</option><option value="type">式別で</option><option value="state">状態で</option></select>
  <button onclick="clearF()">クリア</button>
</div>
<div id="sum" class="note"></div>
<table><thead><tr><th>日時</th><th>開催</th><th>式別</th><th>買い目</th><th class="r">投票</th><th>結果</th><th class="r">払戻</th><th class="r">収支</th><th>元</th></tr></thead><tbody id="tb"></tbody></table>
<script>
var ALL=[];
function esc(s){return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function val(id){return document.getElementById(id).value;}
function uniq(a){return a.filter(function(v,i){return v!=null&&v!==''&&a.indexOf(v)===i;});}
function fillSel(id,vals,label){document.getElementById(id).innerHTML='<option value="">'+label+'</option>'+vals.map(function(v){return '<option>'+esc(v)+'</option>';}).join('');}
function stateOf(v){return v.done===1?(v.hit===1?'的中':'不的中'):'結果待ち';}
function srcOf(v){return v.src==='manual'?'manual':'runner';}
function stats(rows){var o={n:rows.length,done:0,hit:0,inv:0,ret:0};rows.forEach(function(v){if(v.result==='投票完了'&&v.done===1){o.done++;o.inv+=(v.amt||0);if(v.hit===1){o.hit++;o.ret+=(v.pay||0);}}});return o;}
function sumLine(s){var roi=s.inv>0?Math.round(100*s.ret/s.inv):0;var pl=s.ret-s.inv;return s.n+'件(確定'+s.done+'/的中'+s.hit+') 投票'+s.inv.toLocaleString()+' 払戻'+s.ret.toLocaleString()+' 回収'+roi+'% 収支'+(pl>=0?'+':'')+pl.toLocaleString();}
var TODAY_MD=(function(){var d=new Date();return ('0'+(d.getMonth()+1)).slice(-2)+'/'+('0'+d.getDate()).slice(-2);})();
function rowHtml(v){
  var settled=(v.result==='投票完了'&&v.done===1);var pl=settled?((v.pay||0)-(v.amt||0)):null;
  var me=(v.axis||'')+(v.opp?('-'+v.opp):'');
  var res=esc(v.result)+(v.done===1?(v.hit===1?' <span class="hit">的中</span>':' <span class="miss">不的中</span>'):' <span class="pend">(結果待ち)</span>');
  var plc=pl==null?'<span class="pend">—</span>':('<span class="'+(pl>=0?'plus':'minus')+'">'+(pl>=0?'+':'')+pl.toLocaleString()+'</span>');
  var badge=v.src==='manual'?'<span class="badge b-man">✋手動</span>':'<span class="badge b-run">🤖ランナー</span>';
  // 各投票履歴は行クリックで買目ページへ(地方と同じUX)。当日は当日データ、過去日は&date=で当日以外の買目+着順+確定払戻を表示。
  var u='/buyme?venue='+encodeURIComponent(v.venue)+'&race='+v.race+(v.fdate?('&date='+encodeURIComponent(v.fdate)):'');
  var clk=' class="rc" style="cursor:pointer" title="買目を見る" data-u="'+u+'" onclick="location.href=this.dataset.u"';
  var bm='<a href="'+u+'" onclick="event.stopPropagation()">買目</a>';
  return '<tr'+clk+'><td>'+esc(v.dt)+'</td><td>'+esc(v.date)+' '+esc(v.venue)+esc(v.race)+'R</td><td>'+esc(v.type)+'</td><td>'+esc(me)+'</td><td class="r">'+(v.amt||0).toLocaleString()+'</td><td>'+res+'</td><td class="r">'+(v.hit===1?(v.pay||0).toLocaleString():'-')+'</td><td class="r">'+plc+'</td><td>'+badge+' '+bm+'</td></tr>';
}
function gkey(v,by){if(by==='date')return v.date;if(by==='venue')return v.venue;if(by==='type')return v.type;if(by==='state')return stateOf(v);return '';}
function render(){
  var fv=val('f-venue'),ft=val('f-type'),fd=val('f-date'),fs=val('f-state'),fc=val('f-src'),gb=val('f-group'),q=val('f-q').trim();
  var rows=ALL.filter(function(v){
    if(fv&&v.venue!==fv)return false; if(ft&&v.type!==ft)return false; if(fd&&v.date!==fd)return false;
    if(fs&&stateOf(v)!==fs)return false; if(fc&&srcOf(v)!==fc)return false;
    if(q){var me=(v.axis||'')+'-'+(v.opp||'');if(me.indexOf(q)<0)return false;}
    return true;
  });
  document.getElementById('sum').textContent=sumLine(stats(rows));
  var tb=document.getElementById('tb');
  if(!rows.length){tb.innerHTML='<tr><td colspan="9" class="pend">該当なし</td></tr>';return;}
  if(!gb){tb.innerHTML=rows.map(rowHtml).join('');return;}
  var keys=uniq(rows.map(function(v){return gkey(v,gb);}));keys.sort();if(gb==='date')keys.reverse();
  tb.innerHTML=keys.map(function(k){
    var gr=rows.filter(function(v){return gkey(v,gb)===k;});
    return '<tr class="grp"><td colspan="9">'+esc(k||'(なし)')+' — '+sumLine(stats(gr))+'</td></tr>'+gr.map(rowHtml).join('');
  }).join('');
}
function clearF(){['f-venue','f-type','f-date','f-state','f-src','f-group'].forEach(function(id){document.getElementById(id).value='';});document.getElementById('f-q').value='';render();}
var _hfirst=true;
async function load(){
  try{ALL=await (await fetch('/api/history')).json();}catch(e){ALL=[];}
  if(_hfirst){  // 初回のみ: フィルタ選択肢の構築と既定日設定(自動更新でユーザの絞り込み選択をリセットしないため)
    fillSel('f-venue',uniq(ALL.map(function(v){return v.venue;})).sort(),'場(全)');
    fillSel('f-type',uniq(ALL.map(function(v){return v.type;})).sort(),'式別(全)');
    var dates=uniq(ALL.map(function(v){return v.date;}));
    fillSel('f-date',dates,'日付(全)');
    // 馬柱/履歴クリックから来た場合(?venue=&date=yyyy-MM-dd)はその場・日付で確実に絞る。投票が無くてもオプションを足して固定(=該当なし表示)。無ければ本日/最新。
    function ensureOpt(id,val){ if(!val) return; var s=document.getElementById(id); if(!Array.prototype.some.call(s.options,function(o){return o.value===val;})){ var o=document.createElement('option'); o.value=val; o.textContent=val; s.appendChild(o); } }
    var sp=new URLSearchParams(location.search); var qv=sp.get('venue')||''; var qd=sp.get('date')||'';
    if(qv){ ensureOpt('f-venue',qv); document.getElementById('f-venue').value=qv; }
    var m=qd.match(/(\d{4})-(\d{2})-(\d{2})/); var mmdd=m?(m[2]+'/'+m[3]):'';
    if(mmdd){ ensureOpt('f-date',mmdd); document.getElementById('f-date').value=mmdd; }
    else {
      // ★初期値=当日の開催日に絞る。当日の投票が無ければ「最新の開催日」(fdate=yyyy-MM-ddで日付順比較=投票日時順に依存しない)。全件は「日付(全)」で。
      var def=TODAY_MD;
      if(dates.indexOf(TODAY_MD)<0){
        var mx=null; ALL.forEach(function(v){ if(v.fdate && (!mx || v.fdate>mx.fdate)) mx=v; });
        def = mx?mx.date:(dates[0]||'');
      }
      document.getElementById('f-date').value=def;
    }
    _hfirst=false;
  }
  render();
}
load();
setInterval(load,5000);  // ★5秒間隔で自動更新(再取得→再描画・フィルタ選択は保持)
</script>
</div></body></html>
""";

string Win5Html() => """
<!doctype html><html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="icon" href="/favicon.ico"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<title>WIN5 点数計算</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#0b0e13;color:#e6e9ef;font-family:system-ui,'Segoe UI',sans-serif}
.wrap{max-width:760px;margin:0 auto;padding:14px}
h1{font-size:19px;margin:6px 0}h2{font-size:15px;margin:16px 0 6px;color:#cbd2dc}
a.back{color:#7aa2ff;text-decoration:none;font-size:14px}
.note{color:#8a93a3;font-size:12px;margin:6px 0}
table{width:100%;border-collapse:collapse;font-size:13px;margin:6px 0}
th,td{padding:7px 6px;border-bottom:1px solid #222a35;text-align:left}
th{color:#8a93a3;font-weight:600}td.r,th.r{text-align:right}
select,input{background:#11151c;color:#e6e9ef;border:1px solid #39414d;border-radius:6px;padding:5px 7px;font-size:13px}
input.cnt{width:64px;text-align:center}
.big{background:#161b22;border:1px solid #2a313c;border-radius:10px;padding:12px 14px;margin:10px 0;font-size:15px}
.pt{color:#ffd479;font-weight:700;font-size:22px}.yen{color:#5fd38a;font-weight:700}
button{padding:6px 10px;border:1px solid #39414d;border-radius:6px;background:#2a313c;color:#e6e9ef;cursor:pointer;font-size:12px}
.muted{color:#8a93a3;font-size:12px}
</style></head><body><div class="wrap">
<a class="back" href="/">← コントロール</a>　<a class="back" href="/races">🐎 買目・投票</a>　<a class="back" href="/history">📋 投票履歴</a>
<h1>🎯 WIN5 買目点数計算</h1>
<div class="note">WIN5対象の5レースを手動で選び(任意)、各レースの<b>選択頭数</b>を入れると<b>点数＝頭数の積</b>と<b>金額(1点100円)</b>を計算します。1点購入が必須=100円単位。</div>
<table><thead><tr><th>WIN5</th><th>レース（任意・今日の一覧）</th><th class="r">選択頭数</th><th class="r">累積点数</th></tr></thead><tbody id="tb"></tbody></table>
<div class="big">合計点数 <span class="pt" id="tot">1</span> 点　／　購入金額 <span class="yen" id="amt">¥100</span>　<span class="muted" id="brk"></span></div>
<div><button onclick="reset1()">全て1頭にリセット</button> <button onclick="setAll(2)">全て2頭</button> <button onclick="setAll(3)">全て3頭</button></div>
<h2>早見表（全5レース同じ頭数で買った場合）</h2>
<table><thead><tr><th class="r">各レース頭数</th><th class="r">点数</th><th class="r">金額</th></tr></thead><tbody id="ref"></tbody></table>
<div class="note" style="margin-top:8px">※点数は各レースの選択頭数の積（n1×n2×n3×n4×n5）。頭数を増やすほど点数・金額は急増します（例: 全レース3頭=243点=¥24,300）。</div>
<script>
function esc(s){return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function yen(n){return '¥'+Number(n).toLocaleString();}
var RACES=[];
function optHtml(){ var o='<option value="">— 選択 —</option>'; RACES.forEach(function(r,i){ o+='<option value="'+i+'">'+esc((r.post||'')+' '+r.venue+r.race+'R'+(r.raceName?(' '+r.raceName):''))+'</option>'; }); return o; }
function buildRows(){ var h=''; for(var i=0;i<5;i++){ h+='<tr><td>'+(i+1)+'走目</td><td><select id="r'+i+'">'+optHtml()+'</select></td>'
  +'<td class="r"><input class="cnt" id="n'+i+'" type="number" min="1" max="18" value="1" oninput="calc()"></td><td class="r" id="c'+i+'">1</td></tr>'; }
  document.getElementById('tb').innerHTML=h; }
function calc(){ var prod=1, parts=[]; for(var i=0;i<5;i++){ var v=parseInt(document.getElementById('n'+i).value,10); if(!(v>=1)){v=1;} if(v>18)v=18; prod*=v; parts.push(v); document.getElementById('c'+i).textContent=prod.toLocaleString(); }
  document.getElementById('tot').textContent=prod.toLocaleString();
  document.getElementById('amt').textContent=yen(prod*100);
  document.getElementById('brk').textContent='（'+parts.join(' × ')+'）'; }
function reset1(){ setAll(1); }
function setAll(v){ for(var i=0;i<5;i++){ document.getElementById('n'+i).value=v; } calc(); }
function buildRef(){ var h=''; for(var k=1;k<=6;k++){ var p=Math.pow(k,5); h+='<tr><td class="r">'+k+'頭</td><td class="r">'+p.toLocaleString()+'点</td><td class="r">'+yen(p*100)+'</td></tr>'; } document.getElementById('ref').innerHTML=h; }
async function load(){ try{ var j=await (await fetch('/api/races')).json(); RACES=(j.races||[]).slice().sort(function(a,b){ return String(a.post||'').localeCompare(String(b.post||''))||String(a.venue).localeCompare(String(b.venue))||(a.race-b.race); }); }catch(e){ RACES=[]; } buildRows(); buildRef(); calc(); }
load();
</script>
</div></body></html>
""";

string LedgerHtml()
{
    var pipeline = new MarkdownPipelineBuilder().UseAdvancedExtensions().Build();
    string Render(string path, string fallback)
    {
        try
        {
            if (!File.Exists(path)) return "<p class=\"muted\">" + fallback + " が見つかりません: " + path + "</p>";
            var html = Markdown.ToHtml(File.ReadAllText(path, Encoding.UTF8), pipeline);
            return html.Replace("href=\"eval-criteria.md\"", "href=\"#eval\"").Replace("href=\"bet-strategies.md\"", "href=\"#bet\"");
        }
        catch (Exception ex) { return "<p class=\"muted\">読込エラー: " + ex.Message + "</p>"; }
    }
    string bet = Render(@"C:\jra\tools\bet-strategies.md", "買目ロジック台帳");
    string eval = Render(@"C:\jra\tools\eval-criteria.md", "評価基準台帳");
    string css = "*{box-sizing:border-box}body{margin:0;background:#0b0e13;color:#e6e9ef;font-family:system-ui,'Segoe UI',sans-serif;line-height:1.65}"
      + ".wrap{max-width:1000px;margin:0 auto;padding:12px 16px 60px}a{color:#7aa2ff}.back{text-decoration:none;font-size:14px}"
      + ".nav{position:sticky;top:0;background:#0b0e13;padding:9px 0;margin-bottom:6px;border-bottom:1px solid #222a35;z-index:5}.nav a{margin-right:16px;text-decoration:none;font-size:14px}"
      + ".md h1{font-size:20px;border-bottom:2px solid #2a313c;padding-bottom:6px;margin:30px 0 10px}.md h2{font-size:17px;margin:26px 0 8px;color:#cdd3dd}.md h3{font-size:15px;margin:20px 0 6px;color:#b6bdc9}.md h4{font-size:13.5px;margin:16px 0 4px;color:#9aa3b2}"
      + ".md p,.md li{font-size:13.5px}.md code{background:#1a1f27;padding:1px 5px;border-radius:5px;font-size:12px;color:#ffd479}.md a{text-decoration:none}"
      + ".md table{border-collapse:collapse;width:100%;margin:10px 0;font-size:12.5px;display:block;overflow-x:auto}.md th,.md td{border:1px solid #2a313c;padding:6px 8px;text-align:left;vertical-align:top}.md th{background:#1a1f27;color:#cdd3dd;white-space:nowrap}.md tr:nth-child(even) td{background:#0f1216}"
      + ".md strong{color:#fff}.md hr{border:none;border-top:1px solid #222a35;margin:18px 0}hr.big{border:none;border-top:2px dashed #2a313c;margin:40px 0}.muted{color:#8a93a3}";
    return "<!doctype html><html lang=\"ja\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>中央競馬(JRA) 台帳</title>"
      + "<link rel=\"icon\" href=\"/favicon.ico\"><link rel=\"apple-touch-icon\" href=\"/apple-touch-icon.png\"><style>"
      + css + "</style></head><body><div class=\"wrap\">"
      + "<a class=\"back\" href=\"/\">← コントロールに戻る</a>"
      + "<div class=\"nav\"><a href=\"#bet\">買目ロジック</a><a href=\"#eval\">評価基準</a></div>"
      + "<section id=\"bet\" class=\"md\">" + bet + "</section>"
      + "<hr class=\"big\"><section id=\"eval\" class=\"md\">" + eval + "</section>"
      + "</div></body></html>";
}

string RacesHtml() => """
<!doctype html><html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="icon" href="/favicon.ico"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<title>今日のレース・買目</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#0b0e13;color:#e6e9ef;font-family:system-ui,'Segoe UI',sans-serif}
.wrap{max-width:1000px;margin:0 auto;padding:14px}
h1{font-size:18px;margin:6px 0}
a.back{color:#7aa2ff;text-decoration:none;font-size:14px}
.note{color:#8a93a3;font-size:12px;margin:6px 0 8px}
table{width:100%;border-collapse:collapse;font-size:13px}
th,td{padding:7px 6px;border-bottom:1px solid #222a35;text-align:left;white-space:nowrap}
th{color:#8a93a3;font-weight:600}
tr.rc:hover td{background:#161b22}
.plus{color:#5fd38a;font-weight:700}.minus{color:#ff6b6b;font-weight:700}.pend{color:#8a93a3}.hit{color:#5fd38a}
.badge{display:inline-block;padding:1px 7px;border-radius:10px;font-size:11px;background:#3a3120;color:#ffd479}
.filters{display:flex;flex-wrap:wrap;gap:6px;margin:8px 0}
.filters select,.filters button{padding:6px 8px;border-radius:6px;border:1px solid #39414d;background:#0f1216;color:#e6e9ef;font-size:13px}
.filters button{background:#2a313c;cursor:pointer}
</style></head><body><div class="wrap">
<a class="back" href="/">← コントロール</a>　<a class="back" href="/history">📋 投票履歴 →</a>　<a class="back" href="/ledger">📒 台帳</a>
<h1>📅 今日のレース・買目</h1>
<div class="note" id="hd">読込中...</div>
<div class="note" id="refnote"></div>
<div class="filters">
  <select id="f-venue" onchange="render()"></select>
  <select id="f-conf" onchange="render()"><option value="">確度(全)</option><option>鉄板</option><option>標準</option><option>警戒</option></select>
  <select id="f-kind" onchange="render()"><option value="">式別(全)</option><option>ワイド</option><option>複勝</option><option>馬連</option><option>三連複</option></select>
  <select id="f-state" onchange="render()"><option value="">状態(全)</option><option value="fin">確定済</option><option value="pre">未確定</option><option value="voted">投票済</option></select>
  <button onclick="clearF()">クリア</button>
</div>
<div class="note">初期並びは現在時刻で自動（前半＝発走昇順▲／後半＝降順▼・本日発走の中央値で判定）。列見出し（発走/開催/確度/状態）クリックで昇順・降順ソート。行クリックで出馬表（馬柱）へ。「自動投票 一括」は未確定・未発走の全レースをまとめて切替。</div>
<div style="margin:6px 0;display:flex;align-items:center;gap:8px;flex-wrap:wrap">
  <span style="font-size:12px;color:#8a93a3">自動投票 一括:</span>
  <button onclick="toggleAll(true)" title="未確定の全レースを自動投票「する」に" style="background:#16331f;color:#7ee0a0;border:1px solid #2f5a3a;border-radius:6px;padding:4px 11px;cursor:pointer;font-weight:600">🟢 全部する</button>
  <button onclick="toggleAll(false)" title="未確定の全レースを自動投票「しない」に" style="background:#331616;color:#ff9b9b;border:1px solid #5a2f37;border-radius:6px;padding:4px 11px;cursor:pointer;font-weight:600">🔴 全部しない</button>
</div>
<table><thead><tr><th id="h-post" onclick="sortBy('post')" style="cursor:pointer">発走</th><th id="h-venue" onclick="sortBy('venue')" style="cursor:pointer">開催</th><th>軸(◎)</th><th id="h-conf" onclick="sortBy('conf')" style="cursor:pointer">確度</th><th>式別</th><th id="h-state" onclick="sortBy('state')" style="cursor:pointer">状態</th><th>自動投票</th></tr></thead><tbody id="tb"></tbody></table>
<div class="note" id="cnt"></div>
<script>
var ALL=[];
function esc(s){return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function val(id){return document.getElementById(id).value;}
function confCls(c){return c==='鉄板'?'plus':(c==='警戒'?'minus':'');}
function confRank(c){return c==='鉄板'?0:(c==='標準'?1:(c==='警戒'?2:3));}
function uniq(a){return a.filter(function(v,i){return v!=null&&v!==''&&a.indexOf(v)===i;});}
function fillSel(id,vals,label){document.getElementById(id).innerHTML='<option value="">'+label+'</option>'+vals.map(function(v){return '<option>'+esc(v)+'</option>';}).join('');}
function rowHtml(r){
  var u='/buyme?venue='+encodeURIComponent(r.venue)+'&race='+r.race;
  var canceled=(r.cancelled===true);
  var st=[];
  if(canceled){ st.push('<span style="color:#ff6b6b;font-weight:700">🚫取りやめ</span>'); }
  else { if(r.finished)st.push('<span class="hit">確定</span>'); if(r.voted)st.push('<span class="hit">投票済</span>'); if(!r.finished&&!r.voted)st.push('<span class="pend">—</span>'); }
  var canLink = canceled
    ? ' <a href="#" onclick="toggleCancel(event,\''+esc(r.venue)+'\','+r.race+',false);return false" style="color:#7aa2ff;font-size:11px">戻す</a>'
    : (isOver(r)?'':' <a href="#" onclick="toggleCancel(event,\''+esc(r.venue)+'\','+r.race+',true);return false" style="color:#8a93a3;font-size:11px">取りやめにする</a>');
  var av=(r.autovote!==false);
  var avSty=av?'background:#16341f;color:#5fd38a;border:1px solid #2f5a40':'background:#341616;color:#ff8a8a;border:1px solid #5a2f2f';
  var avBtn=(isOver(r)||canceled)
    ? '<span title="終了/発走済/取りやめのため変更不可" style="'+avSty+';border-radius:6px;padding:3px 9px;font-size:12px;opacity:0.45">'+(av?'🟢する':'🔴しない')+'</span>'
    : '<button onclick="toggleAV(event,\''+esc(r.venue)+'\','+r.race+','+(!av)+')" style="'+avSty+';border-radius:6px;padding:3px 9px;font-size:12px;cursor:pointer">'+(av?'🟢する':'🔴しない')+'</button>';
  var isNext=((r.venue+'|'+r.race)===NEXTKEY);
  var postCell=(isNext?'<span style="color:#ffd479;font-weight:700">▶次 </span>':'')+esc(r.post);
  return '<tr class="rc'+(isNext?' nextrace':'')+'" style="cursor:pointer'+(isNext?';background:#17263e':'')+(canceled?';opacity:0.6':'')+'" data-u="'+u+'" onclick="location.href=this.dataset.u">'
    +'<td>'+postCell+'</td><td>'+esc(r.venue)+esc(r.race)+'R</td>'
    +'<td>'+(r.axis?esc(r.axis)+' '+esc(r.axisName):'')+'</td>'
    +'<td><span class="'+confCls(r.conf)+'">'+esc(r.conf)+'</span></td>'
    +'<td>'+esc(r.kind)+'</td><td>'+st.join(' ')+canLink+'</td>'
    +'<td>'+avBtn+'</td></tr>';
}
async function toggleAV(ev,venue,race,enable){
  ev.stopPropagation();
  try{ var res=await (await fetch('/api/race-toggle',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({venue:venue,race:race,enabled:enable})})).json();
    if(res&&res.ok){ for(var i=0;i<ALL.length;i++){ if(ALL[i].venue===venue&&(''+ALL[i].race)===(''+race)){ ALL[i].autovote=res.autovote; break; } } render(); }
    else alert('切替に失敗しました'); }catch(e){ alert('通信に失敗しました'); }
}
// 自動投票 一括する/しない(地方移植): 未確定・未発走(=変更が意味を持つ)レースをまとめて切替。取りやめ・終了レースは対象外。
async function toggleAll(enable){
  var elig=(ALL||[]).filter(function(r){ return !isOver(r) && !r.cancelled; });
  if(elig.length===0){ alert('対象(未確定・未発走)のレースがありません'); return; }
  if(!confirm('未確定・未発走の '+elig.length+' レースを 自動投票「'+(enable?'する':'しない')+'」 に一括設定しますか？')) return;
  var keys=enable?[]:elig.map(function(r){ return r.venue+'|'+r.race; });
  try{ var res=await (await fetch('/api/race-toggle-all',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({enabled:enable,keys:keys})})).json();
    if(res&&res.ok){ for(var i=0;i<ALL.length;i++){ if(!isOver(ALL[i]) && !ALL[i].cancelled){ ALL[i].autovote=enable; } } render(); }
    else alert('一括切替に失敗しました'); }catch(e){ alert('通信に失敗しました'); }
}
async function toggleCancel(ev,venue,race,cancel){
  ev.stopPropagation();
  if(cancel && !confirm(venue+race+'R を取りやめ(中止)にしますか？\n表示が「🚫取りやめ」になり、自動投票・手動投票ともできなくなります。')) return;
  try{ var res=await (await fetch('/api/race-cancel',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({venue:venue,race:race,cancelled:cancel})})).json();
    if(res&&res.ok){ for(var i=0;i<ALL.length;i++){ if(ALL[i].venue===venue&&(''+ALL[i].race)===(''+race)){ ALL[i].cancelled=res.cancelled; break; } } render(); }
    else alert('切替に失敗しました'); }catch(e){ alert('通信に失敗しました'); }
}
var sortKey='post', sortDir=1;
function sortVal(r,k){ if(k==='post')return r.post||''; if(k==='venue')return (r.venue||'')+('00'+r.race).slice(-3); if(k==='conf')return confRank(r.conf); if(k==='state')return (r.finished?2:0)+(r.voted?1:0); return ''; }
function cmp(a,b){ var x=sortVal(a,sortKey),y=sortVal(b,sortKey),c; c=(typeof x==='number')?(x-y):String(x).localeCompare(String(y)); if(c===0){c=String(a.post||'').localeCompare(String(b.post||''))||(a.race-b.race);} return c*sortDir; }
function sortBy(k){ if(sortKey===k){sortDir=-sortDir;}else{sortKey=k;sortDir=1;} render(); }
function hdrMark(k){ return sortKey===k?(sortDir>0?' ▲':' ▼'):''; }
var NEXTKEY=null;
function parsePostMin(s){ var m=/^(\d{1,2}):(\d{2})$/.exec(String(s||'')); return m?(parseInt(m[1],10)*60+parseInt(m[2],10)):null; }
// 初期並び方向: 現在時刻が本日全レースの発走中央値より前=前半(昇順1)、以降=後半(降順-1)。データ(ALL)から算出。
function defaultDir(){ var a=(ALL||[]).map(function(r){return parsePostMin(r.post);}).filter(function(x){return x!=null;}).sort(function(x,y){return x-y;}); if(!a.length)return 1; var mid=a[Math.floor(a.length/2)]; var d=new Date(); return (d.getHours()*60+d.getMinutes())>=mid?-1:1; }
function computeNextKey(){ var d=new Date(); var nowMin=d.getHours()*60+d.getMinutes(); var best=null,bm=1e9; (ALL||[]).forEach(function(r){ if(r.finished||r.cancelled)return; var p=parsePostMin(r.post); if(p==null)return; if(p>nowMin-3 && p<bm){bm=p;best=r.venue+'|'+r.race;} }); return best; }
function isOver(r){ if(r.finished)return true; var p=parsePostMin(r.post); if(p==null)return false; var d=new Date(); return p<=(d.getHours()*60+d.getMinutes()); }
function render(){
  var fv=val('f-venue'),fc=val('f-conf'),fk=val('f-kind'),fs=val('f-state');
  var rows=ALL.filter(function(r){
    if(fv&&r.venue!==fv)return false; if(fc&&r.conf!==fc)return false; if(fk&&r.kind!==fk)return false;
    if(fs==='fin'&&!r.finished)return false; if(fs==='pre'&&r.finished)return false; if(fs==='voted'&&!r.voted)return false;
    return true;
  });
  rows.sort(cmp); NEXTKEY=computeNextKey();
  document.getElementById('tb').innerHTML=rows.length?rows.map(rowHtml).join(''):'<tr><td colspan="7" class="pend">該当なし</td></tr>';
  document.getElementById('cnt').textContent=rows.length+' / '+ALL.length+'レース';
  document.getElementById('h-post').textContent='発走'+hdrMark('post');
  document.getElementById('h-venue').textContent='開催'+hdrMark('venue');
  document.getElementById('h-conf').textContent='確度'+hdrMark('conf');
  document.getElementById('h-state').textContent='状態'+hdrMark('state');
}
function clearF(){['f-venue','f-conf','f-kind','f-state'].forEach(function(id){document.getElementById(id).value='';});sortKey='post';sortDir=defaultDir();render();}
var _first=true;
async function load(){
  var j; try{ j=await (await fetch('/api/races')).json(); }catch(e){ document.getElementById('hd').textContent='読込失敗'; return; }
  ALL=j.races||[];
  document.getElementById('hd').textContent=esc(j.date)+' / '+j.count+'レース'+(j.hasCache?'（買目あり・行クリックで詳細）':'（買目CSV未生成＝ランナー起動で作成）');
  if(_first){ fillSel('f-venue',uniq(ALL.map(function(r){return r.venue;})).sort(),'場(全)'); sortDir=defaultDir(); _first=false; }
  render();
}
function refMs(){ var m=(location.search.match(/[?&]refresh=(\d+)/)||[])[1]; var s=(m==null?5:parseInt(m,10)); return (isNaN(s)||s<=0)?0:s*1000; }
load();
(function(){ var ms=refMs(); var n=document.getElementById('refnote'); if(ms){ if(n)n.textContent='🔄 '+(ms/1000)+'秒ごとに自動更新（?refresh=秒数 で変更・0で停止）'; setInterval(load,ms); } else if(n){ n.textContent='自動更新オフ（?refresh=5 で有効化）'; } })();
</script>
</div></body></html>
""";

// ★日次総括+深掘り一覧(JRA)。その日の _総括.md と 各レース深掘りへのリンクを表示。日付切替つき。
string RetroHtml() => """
<!doctype html><html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="icon" href="/favicon.ico"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<title>日次総括・深掘り一覧(JRA)</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#0b0e13;color:#e6e9ef;font-family:system-ui,'Segoe UI',sans-serif}
.wrap{max-width:1000px;margin:0 auto;padding:14px}
h1{font-size:18px;margin:6px 0}h2{font-size:15px;margin:16px 0 6px;color:#ffd479;border-bottom:1px solid #2a313c;padding-bottom:4px}
a.back{color:#7aa2ff;text-decoration:none;font-size:14px}
.note{color:#8a93a3;font-size:12px;margin:6px 0}
.narr{background:#11151c;border:1px solid #2a313c;border-radius:8px;padding:12px 14px;white-space:pre-wrap;font-size:13px;line-height:1.8}
select{background:#161b22;color:#e6e9ef;border:1px solid #39414d;border-radius:6px;padding:4px 8px;font-size:14px}
.rlist{display:flex;flex-direction:column;gap:4px;margin:6px 0}
.rcard{display:block;background:#161b22;border:1px solid #2a313c;border-radius:8px;padding:8px 11px;text-decoration:none;color:#e6e9ef;font-size:13px}
.rcard:hover{border-color:#5b6472;background:#1b212b}
.rcard b{color:#7db4ff}
.rkspin{display:inline-block;width:15px;height:15px;border:2px solid #7aa2ff;border-top-color:transparent;border-radius:50%;animation:rkspinA .8s linear infinite;vertical-align:-2px;margin-right:5px}
@keyframes rkspinA{to{transform:rotate(360deg)}}
</style></head><body><div class="wrap">
<a class="back" href="/">🏠 コントロールに戻る</a>　<a class="back" href="/races">← 今日のレース一覧</a>
<h1 id="hd"><span class="rkspin"></span>読込中...</h1>
<div style="margin:6px 0"><label class="note">開催日：</label> <select id="dsel" onchange="location.href='/retro?date='+this.value"></select></div>
<h2>日次総括</h2>
<div id="sum" class="narr">（未作成）</div>
<h2>各レース深掘り（クリックで選定理由・振り返りへ）</h2>
<div id="rlist" class="rlist"></div>
<script>
function esc(s){return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function qp(k){return new URLSearchParams(location.search).get(k)||'';}
async function load(){
  var d=qp('date'),dq=d?'?date='+encodeURIComponent(d):'';
  var j; try{ j=await (await fetch('/api/retro'+dq)).json(); }catch(e){ document.getElementById('hd').textContent='読込失敗'; return; }
  document.getElementById('hd').textContent='📒 日次総括・深掘り一覧　'+j.date+'（'+(j.count||0)+'レース）';
  var ds=document.getElementById('dsel'); ds.innerHTML=(j.dates||[]).map(function(x){ return '<option value="'+x+'"'+(x===j.date?' selected':'')+'>'+x+'</option>'; }).join('')||('<option>'+j.date+'</option>');
  document.getElementById('sum').textContent=j.summary||'（未作成）この日の日次総括はまだありません。';
  document.getElementById('rlist').innerHTML=(j.races||[]).map(function(r){
    return '<a class="rcard" href="/reason?venue='+encodeURIComponent(r.venue)+'&race='+r.race+'&date='+encodeURIComponent(j.date)+'"><b>'+esc(r.venue)+' '+r.race+'R</b>　'+esc(r.title)+'</a>';
  }).join('')||'<div class="note">この日の深掘りはまだありません。</div>';
}
load();
</script>
</div></body></html>
""";

// ★買目選定理由(JRA)。買目全頭データ(コンピ/h2h/予測脚質/Δ指数/定性/印/結果)に jra-card評価/総合を重ね、予想突合を表示。
string ReasonHtml() => """
<!doctype html><html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="icon" href="/favicon.ico"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<title>選定理由(JRA)</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#0b0e13;color:#e6e9ef;font-family:system-ui,'Segoe UI',sans-serif}
.wrap{max-width:1100px;margin:0 auto;padding:14px}
h1{font-size:18px;margin:6px 0}h2{font-size:15px;margin:16px 0 6px;color:#ffd479;border-bottom:1px solid #2a313c;padding-bottom:4px}
a.back{color:#7aa2ff;text-decoration:none;font-size:14px}
.note{color:#8a93a3;font-size:12px;margin:6px 0}
.sum{background:#161b22;border:1px solid #2a313c;border-radius:8px;padding:8px 10px;margin:8px 0;font-size:13px;line-height:1.7}
.badge{display:inline-block;background:#222a35;border:1px solid #39414d;border-radius:6px;padding:1px 8px;margin:1px 3px 1px 0;font-size:12px}
.badge b{color:#ffd479}
table{width:100%;border-collapse:collapse;font-size:12.5px}
th,td{padding:5px 6px;border-bottom:1px solid #222a35;text-align:left;white-space:nowrap}
th{color:#8a93a3;font-weight:600}
td.r,th.r{text-align:right}
.scroll{overflow-x:auto}
tr.axisrow td{background:#15130a}
tr.rank1 td{background:#33290a}tr.rank2 td{background:#23282f}tr.rank3 td{background:#2c2113}
.chk1,.chk2,.chk3{font-weight:800;padding:1px 7px;border-radius:10px;color:#15130a}
.chk1{background:#f3c63a}.chk2{background:#c7cdd6}.chk3{background:#d29a55}
.mk-axis{color:#ffd479;font-weight:700}.mk-rel{color:#7aa2ff;font-weight:700}
.stg{display:inline-block;min-width:16px;padding:0 3px;border-radius:3px;font-size:10px;font-weight:700;text-align:center;vertical-align:1px}
.st-nige{background:#5a2222;color:#ff9d9d}.st-senko{background:#54401e;color:#ffce7a}.st-sashi{background:#1e4630;color:#7ee0a5}.st-oikomi{background:#1e3350;color:#8ec2ff}
.sig-pos{color:#7ee0a5;font-weight:600}.sig-neg{color:#ff8a8a;font-weight:600}.sig-mid{color:#c7cdd6}
.hit{color:#7ee0a5;font-weight:700}.miss{color:#ff8a8a;font-weight:700}
.qual{color:#8a93a3;font-size:11px;white-space:normal}
.narr{background:#11151c;border:1px solid #2a313c;border-radius:8px;padding:12px 14px;white-space:pre-wrap;font-size:13px;line-height:1.8}
.rkspin{display:inline-block;width:12px;height:12px;border:2px solid #7aa2ff;border-top-color:transparent;border-radius:50%;animation:rkspinA .8s linear infinite;vertical-align:-2px;margin-right:5px}
@keyframes rkspinA{to{transform:rotate(360deg)}}
</style></head><body><div class="wrap">
<a class="back" href="/">🏠 コントロールに戻る</a>　<a id="bbk" class="back" href="#">🎯 買目へ →</a>　<a id="sbk" class="back" href="#">🐎 馬柱へ →</a>　<a class="back" href="/retro">📒 日次総括 →</a>　<a class="back" href="/races">← レース一覧</a>
<h1 id="hd"><span class="rkspin" style="width:15px;height:15px"></span>読込中...</h1>
<div id="badges" class="note"></div>
<h2>各馬評価（jra-card 総合スコア順）</h2>
<div class="note">総合 = h2h0.4 + V3(調教)0.35 + コンピ0.25 + シグナル補正。シグナル=検証済みの加点/減点ラベル(適/不適/⚡単/前敗/長休/完 等)。着列は確定後に表示。</div>
<div class="scroll"><table><thead><tr><th>印</th><th class="r">馬</th><th>馬名</th><th class="r">指数</th><th class="r">コ順</th><th class="r">総合</th><th>シグナル(選定/消しの理由)</th><th>脚質</th><th class="r">Δ指数</th><th>h2h</th><th class="r">ベイズ複</th><th class="r">人気</th><th class="r">単勝</th><th class="r">着</th></tr></thead><tbody id="tb"></tbody></table></div>
<div id="qualbox"></div>
<div id="result"></div>
<h2>深掘り振り返り（確定後に1レースずつ深掘り）</h2>
<div id="narr" class="narr">（未作成）</div>
<script>
function esc(s){return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function qp(k){return new URLSearchParams(location.search).get(k)||'';}
var stMap={'逃げ':['逃','st-nige'],'先行':['先','st-senko'],'差し':['差','st-sashi'],'追込':['追','st-oikomi']};
function styTag(s){ var m=s&&stMap[s]; return m?('<span class="stg '+m[1]+'">'+m[0]+'</span>'):esc(s||''); }
function chBadge(c){ return (c>=1&&c<=3)?('<span class="chk'+c+'">'+c+'</span>'):(c>0?esc(c):''); }
function badge(k,v){ return (v===''||v==null)?'':('<span class="badge">'+esc(k)+' <b>'+esc(v)+'</b></span>'); }
// シグナル(jra-card評価)を+/-で色分け。消し系=赤/確度加点系=緑。
function sigHtml(ev){ if(!ev)return '<span class="note" style="margin:0">—</span>';
  var neg=/危|不適|前敗|長休|相悪|不調|種替|▼|▽/, pos=/適|⚡|完|両1位|地力|注(?!危)/;
  var cls = neg.test(ev)?'sig-neg':(pos.test(ev)?'sig-pos':'sig-mid');
  return '<span class="'+cls+'">'+esc(ev)+'</span>'; }
async function load(){
  var v=qp('venue'),r=qp('race'),d=qp('date'),dq=d?'&date='+encodeURIComponent(d):'';
  document.getElementById('bbk').href='/buyme?venue='+encodeURIComponent(v)+'&race='+encodeURIComponent(r)+dq;
  document.getElementById('sbk').href='/shutuba?venue='+encodeURIComponent(v)+'&race='+encodeURIComponent(r)+dq;
  var j; try{ j=await (await fetch('/api/reason?venue='+encodeURIComponent(v)+'&race='+encodeURIComponent(r)+dq)).json(); }catch(e){ document.getElementById('hd').textContent='読込失敗'; return; }
  if(j.error){ document.getElementById('hd').textContent=j.error; return; }
  var m=j.meta||{};
  document.getElementById('hd').textContent=j.venue+' '+j.race+'R｜'+(j.dist?j.dist+'m':'')+(j.raceName?' '+j.raceName:'')+'（'+(j.tou||'?')+'頭）'+(j.post?'｜発走'+j.post:'')+'｜'+j.date;
  var evNote = j.cardSrc==='cache' ? '' : '<span class="badge" style="border-color:#5b4a1e">評価キャッシュ生成待ち（数分後に自動反映）</span>';
  document.getElementById('badges').innerHTML=
    badge('軸確度',m.conf)+badge('波乱度',m.seg)+badge('券種',m.kind)
    +badge('先行予測',(j.senkoCnt>=0?j.senkoCnt+'頭':''))+badge('軸',(j.axis?j.axis+'番'+(j.axisLab?'('+j.axisLab+')':''):''))
    +badge('相手',j.partners)+evNote;
  var out=[];
  (j.horses||[]).forEach(function(h){
    var cls=(h.chaku>=1&&h.chaku<=3)?('rank'+h.chaku):(h.mark==='◎'?'axisrow':'');
    out.push('<tr class="'+cls+'"'+(h.scratched?' style="opacity:.5;text-decoration:line-through"':'')+'>'
      +'<td class="'+(h.mark==='◎'?'mk-axis':'mk-rel')+'">'+esc(h.mark)+'</td>'
      +'<td class="r"><b>'+h.uma+'</b></td><td>'+esc(h.name)+'</td>'
      +'<td class="r">'+(h.idx||'')+'</td><td class="r">'+(h.rk||'')+'</td>'
      +'<td class="r"><b>'+(h.sougou!==''&&h.sougou!=null?(+h.sougou).toFixed(2):'—')+'</b></td>'
      +'<td>'+sigHtml(h.eval)+'</td>'
      +'<td>'+styTag(h.style)+'</td>'
      +'<td class="r">'+(h.dz===''||h.dz==null?'':((+h.dz>=0?'+':'')+h.dz))+'</td>'
      +'<td>'+esc(h.h2h||'')+'</td>'
      +'<td class="r">'+(h.pfuku!==''&&h.pfuku!=null?Math.round(h.pfuku*100)+'%':'')+'</td>'
      +'<td class="r">'+(h.pop>0?h.pop:'')+'</td><td class="r">'+(h.tan>0?(+h.tan).toFixed(1):'')+'</td>'
      +'<td class="r">'+chBadge(h.chaku)+'</td></tr>');
  });
  document.getElementById('tb').innerHTML=out.join('')||'<tr><td colspan="14" class="note">全頭データなし（コンピ/出馬未取得）</td></tr>';
  // 定性(調教・厩舎)まとめ
  var qs=(j.horses||[]).filter(function(h){return h.qual;}).map(function(h){ return '<div style="margin:2px 0"><b class="'+(h.mark==='◎'?'mk-axis':'mk-rel')+'">'+esc(h.mark||('#'+h.uma))+'</b> '+esc(h.name)+'：<span class="qual">'+esc(h.qual)+'</span></div>'; });
  if(qs.length){ document.getElementById('qualbox').innerHTML='<h2>定性メモ（調教・厩舎の話）</h2><div class="sum">'+qs.join('')+'</div>'; }
  // 結果・予想突合
  if(j.finished){
    var t=j.taikou||{};
    function tk(lbl,o){ if(!o||!o.uma)return ''; var ok=(o.chaku>=1&&o.chaku<=3); return '<span class="badge">'+lbl+' <b>'+o.uma+'番</b>'+(o.lab?'('+esc(o.lab)+')':'')+'→'+(o.chaku>0?o.chaku+'着':'?')+' <span class="'+(ok?'hit':'miss')+'">'+(ok?'複勝圏':'圏外')+'</span></span>'; }
    var vt=(j.voted||[]).map(function(x){ return '<span class="badge">'+esc(x.bt)+(x.method?esc(x.method):'')+' '+x.amt.toLocaleString()+'円→'+(x.hit?('<span class="hit">的中 '+x.pay.toLocaleString()+'円</span>'):'<span class="miss">外れ</span>')+'</span>'; }).join('');
    document.getElementById('result').innerHTML='<h2>結果・予想突合</h2><div class="sum">'
      +tk('◎システム軸',t.axis)+tk('コンピ1位',t.compi1)+tk('1番人気',t.ninki1)
      +(vt?('<div style="margin-top:6px">IPAT投票: '+vt+'</div>'):'<div class="note" style="margin:6px 0 0">IPAT投票なし(手動運用または見送り)</div>')+'</div>';
  }
  if(j.narrative){ document.getElementById('narr').textContent=j.narrative; }
  else{ document.getElementById('narr').innerHTML='<span class="note" style="margin:0">（未作成）確定後に1レースずつ深掘りした振り返りがここに表示されます。源: C:\\jra\\reasons\\'+esc(j.date)+'\\'+esc(j.venue)+'_'+esc(j.race)+'.md</span>'; }
}
load();
</script>
</div></body></html>
""";

string BuymeHtml() => """
<!doctype html><html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="icon" href="/favicon.ico"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<title>買目（全頭表）</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#0b0e13;color:#e6e9ef;font-family:system-ui,'Segoe UI',sans-serif}
.wrap{max-width:1000px;margin:0 auto;padding:14px}
h1{font-size:18px;margin:6px 0}
a.back{color:#7aa2ff;text-decoration:none;font-size:14px}
.note{color:#8a93a3;font-size:12px;margin:6px 0}
.sum{background:#161b22;border:1px solid #2a313c;border-radius:8px;padding:8px 10px;margin:8px 0;font-size:13px}
table{width:100%;border-collapse:collapse;font-size:13px}
th,td{padding:6px 6px;border-bottom:1px solid #222a35;text-align:left;white-space:nowrap}
th{color:#8a93a3;font-weight:600}
td.r,th.r{text-align:right}
.mk-axis{color:#ffd479;font-weight:700}.mk-rel{color:#7aa2ff;font-weight:700}.mk-oshi{color:#9aa3b2}
.tag-good{color:#5fd38a;font-weight:600}.tag-warn{color:#ffae57}
.stg{display:inline-block;min-width:16px;padding:0 3px;border-radius:3px;font-size:10px;font-weight:700;text-align:center;margin-left:4px;vertical-align:1px}
.st-nige{background:#5a2222;color:#ff9d9d}.st-senko{background:#54401e;color:#ffce7a}.st-sashi{background:#1e4630;color:#7ee0a5}.st-oikomi{background:#1e3350;color:#8ec2ff}
.memo{color:#8a93a3;font-size:12px}.pend{color:#8a93a3}
.hinfo{color:#9aa3b2;font-size:11px;margin-left:5px}.hinfo .bwp{color:#f0a868}.hinfo .bwm{color:#7aa2ff}
/* 式別/方式/モードのラジオ群 */
.rbs{display:inline-flex;flex-wrap:wrap;gap:3px 6px;vertical-align:middle}
.rb{display:inline-flex;align-items:center;gap:3px;cursor:pointer;white-space:nowrap;padding:2px 7px;border:1px solid #39414d;border-radius:6px;background:#11151c}
.rb:has(input:checked){background:#2a313c;border-color:#5b6472;color:#fff;font-weight:600}
.rb input{margin:0;cursor:pointer}
/* 枠色の囲い馬番(囲い数字) */
.wk{display:inline-block;min-width:22px;padding:1px 4px;border-radius:4px;font-weight:800;font-size:13px;text-align:center;border:1px solid rgba(0,0,0,.35)}
.f1{background:#f3f3f3;color:#111}.f2{background:#1a1a1a;color:#fff}.f3{background:#e23b3b;color:#fff}.f4{background:#3b6fe2;color:#fff}
.f5{background:#f3d03a;color:#111}.f6{background:#3aae54;color:#fff}.f7{background:#e8862a;color:#fff}.f8{background:#e86fa0;color:#111}.f0{background:#222a35;color:#fff}
tr.axisrow td{background:#15130a}
tr.danso td{text-align:center;color:#ffd479;background:#1a1508;font-size:12px;padding:2px;letter-spacing:3px;border-bottom:1px solid #4a3d10}
</style></head><body><div class="wrap">
<a class="back" href="/races">← 今日のレース一覧</a>　<a id="sbk" class="back" href="#">🐎 出馬表へ戻る</a>　<a id="rbk" class="back" href="#">🧠 選定理由 →</a>　<a class="back" href="/">🏠 コントロール</a>　<a class="back" href="/history">📋 投票履歴</a>
<div id="rnav" class="note" style="margin:6px 0;font-size:14px">　</div>
<h1 id="hd">読込中...</h1>
<div class="note" id="meta"></div>
<div class="sum" id="sum"></div>
<div class="note" id="voted" style="margin:2px 0"></div>
<div class="note">列見出し（印/指数/h2h確度/単勝/複勝/人気/着）クリックで昇順・降順ソート</div>
<div style="margin:6px 0;display:flex;gap:8px;align-items:center;flex-wrap:wrap">
  <button onclick="showSelectedShutuba()" style="padding:4px 12px;border-radius:6px;border:1px solid #39414d;background:#2a313c;color:#e6e9ef;cursor:pointer;font-weight:600">📋 選択馬の馬柱</button>
  <a href="#" onclick="selAll(true);return false" class="back" style="font-size:12px">全選択</a>
  <a href="#" onclick="selAll(false);return false" class="back" style="font-size:12px">全解除</a>
  <span class="note" style="margin:0">※馬名左のチェックで選び「選択馬の馬柱」をクリック</span>
</div>
<table><thead><tr><th id="bh-mark" data-l="印" onclick="hSortBy('mark')" style="cursor:pointer">印</th><th class="r">馬</th><th>馬名</th><th id="bh-idx" data-l="指数(Δ)" onclick="hSortBy('idx')" style="cursor:pointer">指数(Δ)</th><th id="bh-h2h" data-l="h2h確度" onclick="hSortBy('h2h')" style="cursor:pointer">h2h確度</th><th id="bh-pf" data-l="複勝確率" onclick="hSortBy('pf')" style="cursor:pointer" title="ベイズ較正モデルA(コンピ順位+指数+h2h)の複勝確率(表示用・確度)">複勝確率</th><th id="bh-tan" class="r" data-l="単勝(現)" onclick="hSortBy('tan')" style="cursor:pointer">単勝(現)</th><th id="bh-fuku" data-l="複勝(現)" onclick="hSortBy('fuku')" style="cursor:pointer">複勝(現)</th><th id="bh-pop" class="r" data-l="人気" onclick="hSortBy('pop')" style="cursor:pointer">人気</th><th id="bh-chaku" class="r" data-l="着" onclick="hSortBy('chaku')" style="cursor:pointer">着</th><th>確定払戻</th><th>メモ</th></tr></thead><tbody id="tb"></tbody></table>
<div class="note">◎軸/○▲△相手/押=押さえ。h2h確度=同条件限定h2hの順位+タグ(両1位=鉄板/h2h不支持=注意/h2h実力馬=h2h上位×コンピ4-7位=市場過小評価の実力上位馬・複勝率26-35%)。↑指数×短縮=堅め/×延長=やや割引。確度であり+EVではありません。</div>
<div class="sum">
  <div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:6px;margin-bottom:6px">
    <div style="font-weight:600">🎯 IPAT投票Lite風（買い目を作成→リストに追加→まとめて投票）</div>
    <div style="font-size:13px;display:flex;align-items:center;gap:8px" title="IPATの投票可能額。「更新」でIpatVoteが残高照会します(IPATにログイン)。">
      <span class="note">投票可能額</span><span id="ipat-bal" style="font-weight:700;color:#8a93a3">—</span>
      <button id="ipat-bal-btn" onclick="refreshIpatBal()" style="background:#1f2a3a;color:#9ec1ff;border:1px solid #2f4560;border-radius:6px;padding:2px 8px;font-size:11px;cursor:pointer" title="IPATにログインして残高を照会">更新</button>
    </div>
  </div>
  <div style="font-size:13px;margin-bottom:4px">
    <div style="display:flex;flex-wrap:wrap;gap:4px 10px;align-items:center;margin-bottom:4px"><b style="min-width:34px">式別</b><span id="v-bt" class="rbs"></span></div>
    <div style="display:flex;flex-wrap:wrap;gap:4px 10px;align-items:center;margin-bottom:4px"><b style="min-width:34px">方式</b><span id="v-method" class="rbs"></span></div>
    <div id="v-ax2row" style="display:none;flex-wrap:wrap;gap:4px 10px;align-items:center;margin-bottom:4px"><b style="min-width:34px">着順</b><span id="v-ax2pos" class="rbs"></span><span class="note" style="margin-left:2px">※軸2頭が入る2着順（マルチON時は無視）</span></div>
    <div id="v-multirow" style="display:none;flex-wrap:wrap;gap:4px 10px;align-items:center;margin-bottom:4px"></div>
    <div style="display:flex;flex-wrap:wrap;gap:10px;align-items:center"><label>1点 <input id="v-st" size="6" value="100" style="text-align:right" oninput="calc()">円</label><span id="v-calc" class="note"></span></div>
  </div>
  <div id="v-pick" style="margin:4px 0"></div>
  <div style="margin:6px 0 4px"><button id="v-add" onclick="addBet()" style="padding:5px 12px;border-radius:6px;border:1px solid #39414d;background:#2a313c;color:#e6e9ef;cursor:pointer;font-weight:600">＋ リストに追加</button></div>
  <div id="cart" style="margin-top:8px"></div>
  <div style="margin-top:8px;display:flex;gap:8px;align-items:center;flex-wrap:wrap">
    <label style="display:inline-flex;align-items:center;gap:6px">モード <span id="v-mode" class="rbs"><label class="rb"><input type="radio" name="vmode" value="DryRun"> DryRun(試算)</label><label class="rb"><input type="radio" name="vmode" value="ConfirmStop"> ConfirmStop(確認停止)</label><label class="rb"><input type="radio" name="vmode" value="Auto" checked> Auto(実投票)</label></span></label>
    <button id="v-go" onclick="doVote()" style="padding:6px 14px;border-radius:6px;border:1px solid #39414d;background:#2a313c;color:#e6e9ef;cursor:pointer;font-weight:600">リストを投票</button>
    <label title="既投票と同一の買目でも上乗せ投票する(重複ガードを無視)" style="font-size:12px;cursor:pointer"><input type="checkbox" id="v-allowdup"> 重複でも投票(上乗せ)</label>
    <span id="cart-sum" class="note" style="font-weight:600"></span>
  </div>
  <div id="v-res" class="note" style="margin-top:8px;white-space:pre-wrap"></div>
  <div class="note" style="margin-top:2px">※流し=軸→相手（三連単/馬単=着順あり→ / 順不同券種=-）/ ボックス=選択馬の総当り / フォーメーション=1着群×2着群(×3着群)。2着流し/3着流し/2頭軸流しは内部でフォメ/ボックスに分解。枠連は枠番1-8で選択（JRAは枠単なし）。DryRun=無投票の試算 / ConfirmStop=サーバのIPATブラウザで最後に購入を押す / Auto=無人で実投票。★IPAT実DOM較正後に実動・未較正は安全中断。</div>
</div>
<div id="qpop" onclick="this.style.display='none'" title="タップで閉じる" style="display:none;position:fixed;left:8px;right:8px;bottom:8px;z-index:50;background:#1b2230;border:1px solid #3a4658;border-radius:10px;padding:12px 14px;font-size:14px;line-height:1.7;color:#e6e9ef;box-shadow:0 4px 20px rgba(0,0,0,.55);white-space:pre-wrap;max-height:50vh;overflow:auto"></div>
<script>
function esc(s){return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function escA(s){return esc(s).replace(/"/g,'&quot;');}
// 💬(定性データ=調教/厩舎の話)をクリック/タップで画面下に表示。スマホはhoverが無くtitleツールチップが出ないための対応。
function showQual(el){ var p=document.getElementById('qpop'); if(!p)return; p.textContent=el.dataset.q; p.style.display='block'; }
// 馬名の右に 騎手・斤量・馬体重(増減) を小さく表示。増減は+橙/-青で色分け。
function hMeta(h){ var p=[];
  if(h.jk)p.push(esc(h.jk));
  if(h.kin)p.push(esc(h.kin)+'kg');
  if(h.bw){ var d=''; if(h.bwd!==''&&h.bwd!=null){ var n=+h.bwd; var sg=(n>0?'+':(n<0?'':'±')); var cls=(n>0?'bwp':(n<0?'bwm':'')); d='(<span class="'+cls+'">'+sg+esc(h.bwd)+'</span>)'; } p.push(esc(h.bw)+d); }
  return p.length?('<span class="hinfo">'+p.join(' ')+'</span>'):''; }
function o1(x){ return (x&&x>0)?Number(x).toFixed(1):''; }
function qp(k){return new URLSearchParams(location.search).get(k)||'';}
function dq(){return qp('date')?('&date='+encodeURIComponent(qp('date'))):'';}  // 過去日買目(投票履歴クリック)用。当日は空。
function markCls(m){return m==='◎'?'mk-axis':(m==='押'?'mk-oshi':'mk-rel');}
function h2hHtml(s){ if(!s)return ''; var c=''; if(s.indexOf('両1位')>=0||s.indexOf('h2h実力馬')>=0)c='tag-good'; else if(s.indexOf('不支持')>=0)c='tag-warn'; return '<span class="'+c+'">'+esc(s)+'</span>'; }
// v-bt/v-method/v-mode/v-ax2pos はラジオ群(SPANコンテナ)、v-st等はinput。両対応で値を読む。
function val(id){ var el=document.getElementById(id); if(!el)return ''; if(el.tagName==='SPAN'){ var r=el.querySelector('input[type=radio]:checked'); return r?r.value:''; } return el.value; }
// ラジオ群を生成(opts=文字列 or {v,l})。cur=初期チェック値。oc=変更時ハンドラ。
function setRadios(id,name,opts,cur,oc){ var el=document.getElementById(id); if(!el)return; el.innerHTML=opts.map(function(o){ var v=(o&&o.v!=null)?o.v:o, lb=(o&&o.l!=null)?o.l:o; return '<label class="rb"><input type="radio" name="'+name+'" value="'+esc(v)+'"'+(v===cur?' checked':'')+(oc?' onchange="'+oc+'"':'')+'> '+esc(lb)+'</label>'; }).join(''); }
function setRadio(id,v){ var el=document.getElementById(id); if(!el)return; var r=el.querySelector('input[type=radio][value="'+v+'"]'); if(r)r.checked=true; }
var HORSES=[], hSortKey='rk', hSortDir=1, CART=[], SHUTUBASEL={}, FRAME={};
// 馬番/枠番を枠色の囲い数字に(枠連は番号=枠、他は当該馬の実枠FRAME[馬番])。JRAは枠単なし。
function wkN(bt,u){ var n=+u; if(!n)return esc(''+u); var f=(bt==='枠連')?((n>=1&&n<=8)?n:0):((window.FRAME&&FRAME[n]>0)?FRAME[n]:0); return '<span class="wk f'+f+'" style="min-width:17px;padding:0 3px;font-size:12px">'+n+'</span>'; }
function wkNums(bt,s){ return (''+s).split(/[,\-]/).filter(function(x){return x!==''&&x!=null;}).map(function(u){return wkN(bt,u);}).join(' '); }
// 投票済み馬券の式別/軸/相手を整形。順不同(馬連/枠連/ワイド/三連複)=「-」/着順あり(三連単/馬単)=「→」。馬番は枠色。
function fmtVoted(b){
  var bt=b.bt||'', ax=(''+(b.axis||'')).trim?(''+(b.axis||'')).trim():(''+(b.axis||'')), aite=b.aite||'', kumi=b.kumi||'';
  var mp=(b.method&&b.method!=='通常')?(esc(b.method)+' '):'';
  var sep=(/馬連|枠連|ワイド|三連複/.test(bt))?' - ':' → ';
  if(ax&&aite){ return mp+wkN(bt,ax)+sep+wkNums(bt,aite)+(b.pts>1?'（'+b.pts+'点）':''); }
  if(kumi){ return mp+wkNums(bt,kumi)+(b.pts>1?'（'+b.pts+'点）':''); }
  if(ax){ return mp+wkN(bt,ax); }
  return mp+wkNums(bt,aite);
}
// 🎫 投票済み(IPAT 実投票=IPAT投票履歴・結果'投票完了')。本線の下。データはbuyme.ps1のj.voted。
function renderVoted(j){
  var vd=document.getElementById('voted'); if(!vd)return;
  var vlist=j.voted||[];
  if(!vlist.length){ vd.innerHTML=''; return; }
  var tot=0,totPay=0;
  var rows=vlist.map(function(b){ tot+=(b.amt||0); totPay+=(b.pay||0);
    return '<span style="display:inline-block;margin:1px 6px 1px 0;padding:1px 7px;border-radius:4px;background:#1b2230;border:1px solid #2c3647">'
      +'<b>'+esc(b.bt)+'</b> '+fmtVoted(b)
      +(b.amt?' <span style="color:#9aa3b2">'+Number(b.amt).toLocaleString()+'円</span>':'')
      +(b.hit?' <span class="tag-good">的中'+(b.pay?' '+Number(b.pay).toLocaleString()+'円':'')+'</span>':'')
      +'</span>'; }).join('');
  vd.innerHTML='<div class="note" style="margin:0 0 2px">🎫 投票済み（IPAT 実投票）計'+Number(tot).toLocaleString()+'円'
    +(j.finished?' ／ 払戻'+Number(totPay).toLocaleString()+'円・収支'+(totPay-tot>=0?'+':'')+Number(totPay-tot).toLocaleString()+'円':'')+'</div>'+rows;
}
function toggleSel(el){ var u=el.getAttribute('data-uma'); if(el.checked){SHUTUBASEL[u]=true;}else{delete SHUTUBASEL[u];} }
function showSelectedShutuba(){ var us=Object.keys(SHUTUBASEL).filter(function(u){return SHUTUBASEL[u];}); if(!us.length){ alert('馬柱に表示する馬を（馬名の左のチェックで）選択してください'); return; } us.sort(function(a,b){return a-b;}); var v=qp('venue'),r=qp('race'),d=qp('date'),dq=d?'&date='+encodeURIComponent(d):''; location.href='/shutuba?venue='+encodeURIComponent(v)+'&race='+encodeURIComponent(r)+dq+'&umas='+encodeURIComponent(us.join(',')); }
function selAll(on){ (HORSES||[]).forEach(function(h){ if(h.scratched)return; if(on){SHUTUBASEL[h.uma]=true;}else{delete SHUTUBASEL[h.uma];} }); renderHorses(); }
function postPassed(p){ if(!p)return false; var hm=(''+p).split(':'); if(hm.length<2)return false; var d=new Date(); d.setHours(+hm[0],+hm[1],0,0); return new Date()>=d; }
function h2hP(s){ var m=(''+s).match(/h2h(\d+)/); return m?(+m[1]):99; }
function markOrd(m){ var o={'◎':0,'○':1,'▲':2,'△':3,'押':4}; return (o[m]!==undefined)?o[m]:9; }
function pfHtml(v){ if(v===''||v==null)return ''; var p=Math.round(v*100); var c=v>=0.70?'#ffd479':(v>=0.55?'#8fd0ff':'#8a93a3'); return '<span style="color:'+c+';font-weight:600">'+p+'%</span>'; }
function hSortVal(h,k){ if(k==='mark')return markOrd(h.mark); if(k==='idx')return -(h.idx||0); if(k==='h2h')return h2hP(h.h2h); if(k==='pf')return -((h.pfuku===''||h.pfuku==null)?-1:(+h.pfuku)); if(k==='tan')return (h.tan>0?h.tan:99999); if(k==='fuku')return (h.fmin>0?h.fmin:99999); if(k==='pop')return (h.pop>0?h.pop:99); if(k==='chaku')return (h.chaku>0?h.chaku:99); return h.rk; }
function hCmp(a,b){ var c=hSortVal(a,hSortKey)-hSortVal(b,hSortKey); if(c===0)c=a.rk-b.rk; return c*hSortDir; }
function hSortBy(k){ if(hSortKey===k){hSortDir=-hSortDir;}else{hSortKey=k;hSortDir=1;} renderHorses(); }
function hMark(k){ return hSortKey===k?(hSortDir>0?' ▲':' ▼'):''; }
function renderHorses(){
  var rows=HORSES.slice().sort(hCmp);
  var showDanso=(hSortKey==='rk'||hSortKey==='idx');
  var out=[];
  for(var i=0;i<rows.length;i++){
    var h=rows[i];
    if(h.scratched){ out.push('<tr style="opacity:.45"><td>'+(h.mark?esc(h.mark):'')+'</td><td class="r"><span class="wk f'+(h.frame||0)+'">'+esc(h.uma)+'</span></td><td>'+esc(h.name)+' <span class="tag-warn">取消</span></td><td>'+esc(h.idx)+'</td><td colspan="8" class="memo">出走取消／除外</td></tr>'); continue; }
    var dz=(h.dz===''||h.dz==null)?'':(' Δ'+(h.dz>=0?'+':'')+h.dz);
    var memo=[]; if(h.distNote)memo.push(h.distNote); if(h.senpu)memo.push('⚡乗替'+h.senpu); if(h.keshi)memo.push('消:'+h.keshi);
    var fk=(h.fmin||h.fmax)?(o1(h.fmin)+'〜'+o1(h.fmax)):'—';
    var tn=h.tan?o1(h.tan):'—';
    var mk=h.mark?('<span class="'+markCls(h.mark)+'">'+esc(h.mark)+'</span>'):'';
    var selchk='<input type="checkbox" class="umck" data-uma="'+h.uma+'" onchange="toggleSel(this)"'+(SHUTUBASEL[h.uma]?' checked':'')+' style="margin-right:5px;vertical-align:middle" title="馬柱に表示する馬を選択">';
    var stMap={'逃げ':['逃','st-nige'],'先行':['先','st-senko'],'差し':['差','st-sashi'],'追込':['追','st-oikomi']};
    var stTag=(h.style&&stMap[h.style])?('<span class="stg '+stMap[h.style][1]+'" title="予測脚質(直近5走の平均通過・買目/馬柱/通知と同一定義): '+esc(h.style)+'">'+stMap[h.style][0]+'</span>'):'';
    var nmInner=selchk+esc(h.name)+stTag+hMeta(h);
    var nameCell=h.qual?('<td class="qcell" data-q="'+escA(h.qual)+'" title="'+escA(h.qual)+'" style="cursor:pointer" onclick="showQual(this)">'+nmInner+' <span style="text-decoration:underline dotted">💬</span></td>'):('<td>'+nmInner+'</td>');
    var chk=h.chaku?('<span class="'+(h.chaku===1?'mk-axis':'')+'">'+esc(h.chaku)+'</span>'):'';
    var conf=[]; if(h.tanPay)conf.push('単'+Number(h.tanPay).toLocaleString()); if(h.fukuPay)conf.push('複'+Number(h.fukuPay).toLocaleString());
    out.push('<tr class="'+(h.mark==='◎'?'axisrow':'')+'"><td>'+mk+'</td><td class="r"><span class="wk f'+(h.frame||0)+'">'+esc(h.uma)+'</span></td>'+nameCell
      +'<td>'+esc(h.idx)+esc(dz)+'</td><td>'+h2hHtml(h.h2h)+'</td><td>'+pfHtml(h.pfuku)+'</td>'
      +'<td class="r">'+tn+'</td><td>'+fk+'</td><td class="r">'+(h.pop?esc(h.pop)+'人':'')+'</td>'
      +'<td class="r">'+chk+'</td><td class="memo">'+esc(conf.join(' '))+'</td>'
      +'<td class="memo">'+esc(memo.join(' / '))+'</td></tr>');
    if(showDanso && !h.scratched){ var j=i+1; while(j<rows.length && rows[j].scratched) j++; if(j<rows.length){ var gap=(h.idx||0)-(rows[j].idx||0); if(gap>=10){ out.push('<tr class="danso"><td colspan="12">━━━ 指数断層（差 '+gap+'） ━━━</td></tr>'); } } }
  }
  document.getElementById('tb').innerHTML=out.join('');
  ['mark','idx','h2h','pf','tan','fuku','pop','chaku'].forEach(function(k){ var el=document.getElementById('bh-'+k); if(el)el.textContent=el.getAttribute('data-l')+hMark(k); });
}
// ===== IPAT投票Lite風 買い目ビルダー(地方RunnerControl移植・JRA適応:枠単なし) =====
var BT_ALL=['単勝','複勝','馬連','馬単','ワイド','枠連','三連複','三連単'];
// 発売可否: 枠連=登録9頭以上(8頭以下は枠番連勝式なし=馬連と同一)。JRAは枠単(枠番二連単)を発売しない。他=常時。
function betSold(bt,venue,tou){ if(bt==='枠連')return tou>=9; return true; }
function single(bt){ return bt==='単勝'||bt==='複勝'; }
function sizeOf(bt){ return (bt==='三連複'||bt==='三連単')?3:2; }
function ordered(bt){ return bt==='三連単'||bt==='馬単'; }   // JRA: 枠単なし(着順ありは三連単/馬単のみ)
function methodsFor(bt){ if(single(bt))return['通常']; if(sizeOf(bt)===3) return ordered(bt)?['流し','2着流し','3着流し','2頭軸流し','ボックス','フォーメーション']:['流し','2頭軸流し','ボックス','フォーメーション']; return ['流し','ボックス','フォーメーション']; }
function universe(bt){ if(bt==='枠連'){ var a=[]; for(var i=1;i<=8;i++)a.push({uma:i,name:'枠',mark:''}); return a; } return HORSES.filter(function(x){return !x.scratched;}).slice().sort(function(a,b){return a.uma-b.uma;}); }
function jcombos(items,k){ var res=[]; (function rec(s,acc){ if(acc.length===k){res.push(acc.slice());return;} for(var i=s;i<items.length;i++){acc.push(items[i]);rec(i+1,acc);acc.pop();} })(0,[]); return res; }
function jperms(arr){ if(arr.length<=1)return [arr.slice()]; var res=[]; for(var i=0;i<arr.length;i++){ var rest=arr.slice(0,i).concat(arr.slice(i+1)); jperms(rest).forEach(function(p){res.push([arr[i]].concat(p));}); } return res; }
function jproduct(groups){ var acc=[[]]; groups.forEach(function(g){ var ng=[]; acc.forEach(function(a){ g.forEach(function(x){ ng.push(a.concat([x])); }); }); acc=ng; }); return acc; }
function enumCombos(bt,m,sel){
  if(single(bt)){ return sel.singles.map(function(u){return [u];}); }
  var ord=ordered(bt), sz=sizeOf(bt), multi=(ord&&m==='流し'&&sel&&sel.multi), raw=[];   // マルチ=三連単/馬単の流し(軸の着順不問)
  if(m==='ボックス'){ jcombos(sel.box,sz).forEach(function(c){ if(ord) jperms(c).forEach(function(p){raw.push(p);}); else raw.push(c); }); }
  else if(m==='フォーメーション'){ var gs=sz===3?[sel.f1,sel.f2,sel.f3]:[sel.f1,sel.f2]; jproduct(gs).forEach(function(p){raw.push(p);}); }
  else if(m==='2着流し'||m==='3着流し'){ if(sel.axis>0){ var g1,g2,g3; if(m==='2着流し'){ g1=sel.partners; g2=[sel.axis]; g3=sel.partners; } else { g1=sel.partners; g2=sel.partners; g3=[sel.axis]; } jproduct([g1,g2,g3]).forEach(function(p){raw.push(p);}); } }   // N着流し=軸をN着に固定した1頭軸流し(フォーメーション相当)
  else if(m==='2頭軸流し'){ if(sel.axis2&&sel.axis2.length===2){ var A2=sel.axis2[0],B2=sel.axis2[1];
    if(!ord){ sel.partners.forEach(function(pn){ raw.push([A2,B2,pn]); }); }   // 三連複2頭軸=各相手の三連複(1点/相手)
    else if(sel.multi){ sel.partners.forEach(function(pn){ jperms([A2,B2,pn]).forEach(function(p){raw.push(p);}); }); }   // マルチ=軸2頭の着順不問(6点/相手)
    else { var pos=sel.ax2pos||'1-2';   // 着順パターン(軸2頭の入る2着順・軸間順不同=2点/相手)
      if(pos==='1-2'){ jproduct([[A2,B2],[A2,B2],sel.partners]).forEach(function(p){raw.push(p);}); }   // 軸2頭で1-2着
      else if(pos==='2-3'){ jproduct([sel.partners,[A2,B2],[A2,B2]]).forEach(function(p){raw.push(p);}); }   // 軸2頭で2-3着
      else { jproduct([[A2,B2],sel.partners,[A2,B2]]).forEach(function(p){raw.push(p);}); }   // 軸2頭で1-3着
    } } }
  else { if(sel.axis>0) jcombos(sel.partners,sz-1).forEach(function(sub){
    if(ord){ if(multi){ jperms([sel.axis].concat(sub)).forEach(function(p){raw.push(p);}); }   // マルチ=軸の着順不問
             else { jperms(sub).forEach(function(p){raw.push([sel.axis].concat(p));}); } }       // 1着流し=軸1着固定・相手を2(3)着で並べ替え
    else { raw.push([sel.axis].concat(sub)); } }); }
  var seen={},res=[];
  raw.forEach(function(c){ var u={},dup=false; for(var i=0;i<c.length;i++){ if(!c[i]||u[c[i]]){dup=true;break;} u[c[i]]=1; } if(dup)return; var key=ord?c.join('-'):c.slice().sort(function(a,b){return a-b;}).join('-'); if(!seen[key]){seen[key]=1;res.push(key);} });
  return res;
}
function getSel(){
  var bt=val('v-bt'),m=val('v-method'),sel={axis:0,axis2:[],partners:[],box:[],f1:[],f2:[],f3:[],singles:[],multi:true,ax2pos:'マルチ'};
  function ck(cls){ return Array.prototype.slice.call(document.querySelectorAll('#v-pick .'+cls+':checked')).map(function(e){return +e.getAttribute('data-uma');}); }
  var mc=document.getElementById('v-multi'); if(mc) sel.multi=mc.checked;   // マルチ切替(三連単/馬単の流し)
  if(single(bt)){ sel.singles=ck('pk'); }
  else if(m==='流し'){ var a=document.querySelector('#v-pick .pkax:checked'); sel.axis=a?+a.getAttribute('data-uma'):0; sel.partners=ck('pk').filter(function(u){return u!==sel.axis;}); }
  else if(m==='2着流し'||m==='3着流し'){ var a2=document.querySelector('#v-pick .pkax:checked'); sel.axis=a2?+a2.getAttribute('data-uma'):0; sel.partners=ck('pk').filter(function(u){return u!==sel.axis;}); }
  else if(m==='2頭軸流し'){ sel.axis2=ck('pkax2'); sel.partners=ck('pk').filter(function(u){return sel.axis2.indexOf(u)<0;}); sel.ax2pos=val('v-ax2pos')||'1-2'; }
  else if(m==='ボックス'){ sel.box=ck('pk'); }
  else { sel.f1=ck('pf1'); sel.f2=ck('pf2'); sel.f3=ck('pf3'); }
  return sel;
}
function frameOf(u){ var bt=val('v-bt'); if(bt==='枠連')return (u>=1&&u<=8)?u:0;   // 枠連は番号=枠番そのもの
  if(window.FRAME&&FRAME[u]!=null&&FRAME[u]>0)return FRAME[u]; return 0; }   // 馬番系は当該馬の実枠(無ければ無色)
function chip(u,cls,type,label){ var oc=(cls==='pkax2')?'onAx2()':(cls==='pkax')?'onAx1()':'calc()';   // 軸(pkax=1頭/pkax2=2頭)変更時は相手グリッドを軸除外で再描画
  return '<label style="display:inline-block;margin:2px;padding:3px 7px;border:1px solid #39414d;border-radius:6px;background:#11151c;cursor:pointer;font-size:12px"><input type="'+type+'" class="'+cls+'" data-uma="'+u+'"'+(type==='radio'?' name="pkax"':'')+' onchange="'+oc+'"> <span class="wk f'+frameOf(u)+'">'+u+'</span>'+(label?'<span style="color:#8a93a3"> '+esc(label)+'</span>':'')+'</label>'; }
function lbl0(x){ return (x.mark||'')+(x.name&&x.name!=='枠'?(' '+x.name):''); }
function pickUmas(cls){ return Array.prototype.slice.call(document.querySelectorAll('#v-pick .'+cls+':checked')).map(function(e){return +e.getAttribute('data-uma');}); }
// 2頭軸流し: 軸に選んだ馬を相手グリッドから除外して再描画(軸∩相手を防止=相手が無言で減る不具合の対策)。相手の既存チェックは保持。
function onAx2(){ var wrap=document.getElementById('v-partners'); if(wrap){ var axes=pickUmas('pkax2'),keep=pickUmas('pk'),bt=val('v-bt'); wrap.innerHTML=universe(bt).filter(function(x){return axes.indexOf(x.uma)<0;}).map(function(x){return chip(x.uma,'pk','checkbox',lbl0(x));}).join(''); keep.forEach(function(u){ if(axes.indexOf(u)<0){ var e=wrap.querySelector('.pk[data-uma="'+u+'"]'); if(e)e.checked=true; } }); } calc(); }
// 1頭軸系(流し/2着流し/3着流し): 軸に選んだ1頭を相手グリッドから除外して再描画。相手の既存チェックは保持。
function onAx1(){ var wrap=document.getElementById('v-partners'); if(wrap){ var a=document.querySelector('#v-pick .pkax:checked'),ax=a?+a.getAttribute('data-uma'):0,keep=pickUmas('pk'),bt=val('v-bt'); wrap.innerHTML=universe(bt).filter(function(x){return x.uma!==ax;}).map(function(x){return chip(x.uma,'pk','checkbox',lbl0(x));}).join(''); keep.forEach(function(u){ if(u!==ax){ var e=wrap.querySelector('.pk[data-uma="'+u+'"]'); if(e)e.checked=true; } }); } calc(); }
function onBt(){ var bt=val('v-bt'),ms=methodsFor(bt),cur=val('v-method'); setRadios('v-method','vmethod',ms,(ms.indexOf(cur)>=0?cur:ms[0]),'renderPick()'); renderPick(); }
function renderPick(){
  var bt=val('v-bt'),m=val('v-method'),uni=universe(bt),h='';
  function lbl(x){ return (x.mark||'')+(x.name&&x.name!=='枠'?(' '+x.name):''); }
  function grid(cls){ return uni.map(function(x){ return chip(x.uma,cls,'checkbox',lbl(x)); }).join(''); }
  if(single(bt)){ h='<div class="note">馬を選択（複数可・各1点）</div>'+grid('pk'); }
  else if(m==='流し'){ h='<div class="note">軸（1頭）</div>'+uni.map(function(x){return chip(x.uma,'pkax','radio',lbl(x));}).join('')+'<div class="note" style="margin-top:4px">相手（複数・軸馬は除外）</div><div id="v-partners">'+grid('pk')+'</div>'; }
  else if(m==='2着流し'||m==='3着流し'){ h='<div class="note">軸（1頭・'+(m==='2着流し'?'2着':'3着')+'に固定）</div>'+uni.map(function(x){return chip(x.uma,'pkax','radio',lbl(x));}).join('')+'<div class="note" style="margin-top:4px">相手（2頭以上・軸馬は除外）</div><div id="v-partners">'+grid('pk')+'</div><div class="note" style="margin-top:4px;color:#8a93a3">※軸を'+(m==='2着流し'?'2':'3')+'着に固定した1頭軸流し。内部はフォーメーションとして投票します。</div>'; }
  else if(m==='2頭軸流し'){ h='<div class="note">軸（2頭を選択）</div>'+uni.map(function(x){return chip(x.uma,'pkax2','checkbox',lbl(x));}).join('')+'<div class="note" style="margin-top:4px">相手（複数・軸馬は除外）</div><div id="v-partners">'+grid('pk')+'</div>'; if(ordered(bt)){ h+='<div class="note" style="margin-top:4px;color:#8a93a3">※着順パターン・マルチは「方式」の下で選択。マルチ=相手ごとの三連単ボックス／着順固定=フォーメーションとして投票します。</div>'; } else { h+='<div class="note" style="margin-top:4px;color:#8a93a3">※軸2頭＋各相手の三連複（1点/相手）。内部は相手ごとの三連複ボックスとして投票します。</div>'; } }
  else if(m==='ボックス'){ h='<div class="note">ボックス対象馬（2頭以上）</div>'+grid('pk'); }
  else { h='<div class="note">1着</div>'+uni.map(function(x){return chip(x.uma,'pf1','checkbox',lbl(x));}).join('')+'<div class="note" style="margin-top:4px">2着</div>'+uni.map(function(x){return chip(x.uma,'pf2','checkbox',lbl(x));}).join('')+(sizeOf(bt)===3?('<div class="note" style="margin-top:4px">3着</div>'+uni.map(function(x){return chip(x.uma,'pf3','checkbox',lbl(x));}).join('')):''); }
  document.getElementById('v-pick').innerHTML=h;
  var ax2row=document.getElementById('v-ax2row');   // 着順パターン(2頭軸流し・三連単の時だけ方式の下に表示)
  if(ax2row){ if(m==='2頭軸流し'&&ordered(bt)){ ax2row.style.display='flex'; setRadios('v-ax2pos','vax2pos',[{v:'1-2',l:'1・2着'},{v:'2-3',l:'2・3着'},{v:'1-3',l:'1・3着'}],(val('v-ax2pos')||'1-2'),'calc()'); } else { ax2row.style.display='none'; var _sp=document.getElementById('v-ax2pos'); if(_sp)_sp.innerHTML=''; } }
  var mrow=document.getElementById('v-multirow');   // マルチ(三連単/馬単の流し・2頭軸流しの時だけ1点欄の上に表示)
  if(mrow){ var showMulti=ordered(bt)&&(m==='流し'||m==='2頭軸流し');
    if(showMulti){ var _mc=document.getElementById('v-multi'),wasCk=_mc?_mc.checked:(sizeOf(bt)===3); var lab=(m==='2頭軸流し')?'マルチ（軸2頭の着順を固定しない＝1・2・3着すべて＝6点/相手。外すと上の着順パターンで2点/相手）':('マルチ（軸の着順を固定しない＝軸が1〜'+sizeOf(bt)+'着のいずれでも。外すと軸1着固定の1着流し）'); mrow.style.display='flex'; mrow.innerHTML='<label class="rb" style="font-size:12px"><input type="checkbox" id="v-multi"'+(wasCk?' checked':'')+' onchange="calc()"> '+lab+'</label>'; }
    else { mrow.style.display='none'; mrow.innerHTML=''; } }
  calc();
}
function calc(){
  var bt=val('v-bt'),m=val('v-method'),st=+val('v-st')||0,sel=getSel(),n=enumCombos(bt,m,sel).length;
  document.getElementById('v-calc').textContent=n>0?(n+'点 × '+st+'円 = '+(n*st).toLocaleString()+'円'):'（馬を選択）';
  return {n:n,sel:sel,bt:bt,m:m,st:st};
}
function addBet(){
  var c=calc(); if(c.n<=0){alert('買い目が0点です。馬を選択してください');return;}
  if(c.st<100){alert('1点金額は100円以上にしてください');return;}
  if(single(c.bt)){ c.sel.singles.forEach(function(u){ CART.push({bettype:c.bt,method:'通常',axis:u,partners:[],box:[],f1:[],f2:[],f3:[],stake:c.st,points:1,label:c.bt+' '+u}); }); }
  else if(c.m==='流し'){ if(!c.sel.axis){alert('軸を選択してください');return;} var mu=ordered(c.bt)?!!c.sel.multi:null; CART.push({bettype:c.bt,method:'流し',axis:c.sel.axis,partners:c.sel.partners,box:[],f1:[],f2:[],f3:[],stake:c.st,points:c.n,multi:mu,label:c.bt+'流し'+(ordered(c.bt)?(mu?'(マルチ)':'(1着流し)'):'')+' 軸'+c.sel.axis+(ordered(c.bt)?'→':'-')+c.sel.partners.join(',')}); }
  else if(c.m==='2着流し'||c.m==='3着流し'){ if(!c.sel.axis){alert('軸を選択してください');return;} if(c.sel.partners.length<2){alert('相手を2頭以上選択してください');return;} var f1,f2,f3; if(c.m==='2着流し'){ f1=c.sel.partners; f2=[c.sel.axis]; f3=c.sel.partners; } else { f1=c.sel.partners; f2=c.sel.partners; f3=[c.sel.axis]; } CART.push({bettype:c.bt,method:'フォーメーション',axis:0,partners:[],box:[],f1:f1,f2:f2,f3:f3,stake:c.st,points:c.n,label:c.bt+c.m+' 軸'+c.sel.axis+'←'+c.sel.partners.join(',')}); }
  else if(c.m==='2頭軸流し'){ if(!c.sel.axis2||c.sel.axis2.length!==2){alert('軸を2頭選択してください');return;} if(c.sel.partners.length<1){alert('相手を1頭以上選択してください');return;} var A2=c.sel.axis2[0],B2=c.sel.axis2[1];
    if(!ordered(c.bt)){ c.sel.partners.forEach(function(pn){ CART.push({bettype:c.bt,method:'ボックス',axis:0,partners:[],box:[A2,B2,pn],f1:[],f2:[],f3:[],stake:c.st,points:1,label:c.bt+'2軸流し '+A2+','+B2+'-'+pn+'(BOX)'}); }); }   // 三連複=相手ごとの三連複ボックス(1点)
    else if(c.sel.multi){ c.sel.partners.forEach(function(pn){ CART.push({bettype:c.bt,method:'ボックス',axis:0,partners:[],box:[A2,B2,pn],f1:[],f2:[],f3:[],stake:c.st,points:6,label:c.bt+'2軸流しマルチ '+A2+','+B2+'-'+pn+'(BOX)'}); }); }   // マルチ=相手ごとの三連単ボックス(6点)
    else { var pos=c.sel.ax2pos||'1-2'; var f1,f2,f3; if(pos==='1-2'){f1=[A2,B2];f2=[A2,B2];f3=c.sel.partners;} else if(pos==='2-3'){f1=c.sel.partners;f2=[A2,B2];f3=[A2,B2];} else {f1=[A2,B2];f2=c.sel.partners;f3=[A2,B2];} CART.push({bettype:c.bt,method:'フォーメーション',axis:0,partners:[],box:[],f1:f1,f2:f2,f3:f3,stake:c.st,points:c.n,label:c.bt+'2軸流し'+pos.replace('-','・')+'着 '+A2+','+B2+'←'+c.sel.partners.join(',')}); } }   // 着順固定=フォーメーション
  else if(c.m==='ボックス'){ CART.push({bettype:c.bt,method:'ボックス',axis:0,partners:[],box:c.sel.box,f1:[],f2:[],f3:[],stake:c.st,points:c.n,label:c.bt+'BOX '+c.sel.box.join(',')}); }
  else { CART.push({bettype:c.bt,method:'フォーメーション',axis:0,partners:[],box:[],f1:c.sel.f1,f2:c.sel.f2,f3:c.sel.f3,stake:c.st,points:c.n,label:c.bt+'F '+c.sel.f1.join(',')+' - '+c.sel.f2.join(',')+(sizeOf(c.bt)===3?(' - '+c.sel.f3.join(',')):'')}); }
  renderCart();
}
function rmBet(i){ CART.splice(i,1); renderCart(); }
function renderCart(){
  var el=document.getElementById('cart');
  if(CART.length===0){ el.innerHTML='<div class="note">買い目リストは空です。上で式別・方式・馬を選び「＋ リストに追加」。</div>'; document.getElementById('cart-sum').textContent=''; return; }
  var tp=0,ty=0;
  var rows=CART.map(function(b,i){ var amt=b.points*b.stake; tp+=b.points; ty+=amt; return '<tr><td>'+(i+1)+'</td><td>'+esc(b.label)+'</td><td class="r">'+b.points+'点</td><td class="r">'+b.stake+'円</td><td class="r">'+amt.toLocaleString()+'円</td><td><a href="#" onclick="rmBet('+i+');return false">削除</a></td></tr>'; }).join('');
  el.innerHTML='<table style="width:auto;min-width:60%"><thead><tr><th>#</th><th>買い目</th><th class="r">点</th><th class="r">1点</th><th class="r">金額</th><th></th></tr></thead><tbody>'+rows+'</tbody></table>';
  document.getElementById('cart-sum').textContent='合計 '+CART.length+'件 / '+tp+'点 / '+ty.toLocaleString()+'円';
}
function fillVote(j){
  var k=(j.meta&&(''+j.meta.kind))||'';
  var bt=k.indexOf('ワイド')>=0?'ワイド':(k.indexOf('三連複')>=0?'三連複':(k.indexOf('馬連')>=0?'馬連':'複勝'));
  setRadio('v-bt',bt); onBt();
  var m=val('v-method'),ax='',pt=[];
  (j.horses||[]).forEach(function(h){ if(h.scratched)return; if(h.mark==='◎')ax=h.uma; else if(h.mark==='○'||h.mark==='▲'||h.mark==='△')pt.push(h.uma); });
  if(single(bt)){ if(ax){var e=document.querySelector('#v-pick .pk[data-uma="'+ax+'"]'); if(e)e.checked=true;} }
  else if(m==='流し'){ if(ax){var ea=document.querySelector('#v-pick .pkax[data-uma="'+ax+'"]'); if(ea)ea.checked=true;} pt.forEach(function(u){var e=document.querySelector('#v-pick .pk[data-uma="'+u+'"]'); if(e)e.checked=true;}); onAx1(); }
  calc();
}
async function doVote(){
  if(CART.length===0){alert('買い目リストが空です。先に「＋ リストに追加」してください');return;}
  var v=qp('venue'),r=qp('race'),md=val('v-mode');
  var adEl=document.getElementById('v-allowdup'); var allowDup=!!(adEl&&adEl.checked);
  var tp=0,ty=0; CART.forEach(function(b){tp+=b.points;ty+=b.points*b.stake;});
  var warn=md==='Auto'?'\n\n★Auto＝無人で実際に投票します（最終確認なし・実金が動きます。※IPAT実DOM較正後に実動）。':(md==='ConfirmStop'?'\n\nConfirmStop＝確認画面まで自動。最後の購入操作はサーバのIPATブラウザで人が押します（※較正後に実動）。':'\n\nDryRun＝投票せず試算のみ。');
  if(allowDup&&md!=='DryRun')warn+='\n\n⚠ 重複でも投票=既に投票済みの同一買目でも上乗せ投票します（二重投票になります）。';
  if(!confirm('投票しますか？\n'+CART.length+'件 / '+tp+'点 / '+ty.toLocaleString()+'円 / '+md+warn))return;
  var btn=document.getElementById('v-go'),res=document.getElementById('v-res');
  btn.disabled=true; res.textContent='送信中...';
  try{
    var resp=await fetch('/api/vote',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({venue:v,race:Number(r),mode:md,allowdup:allowDup,bets:CART})});
    var j=await resp.json();
    if(j.ok===false){ res.textContent='⚠ '+(j.msg||'失敗'); }
    else if(j.mode==='DryRun'){ res.textContent='試算OK（無投票・'+(j.count||CART.length)+'件）:\n'+(j.output||''); }
    else{ var startMsg='送信しました（'+md+'・'+(j.count||CART.length)+'件）'; res.textContent='⏳ '+startMsg+'…投票処理中'; if(j.since){ await pollVoteResult(v,r,j.since,startMsg,md); } else { res.textContent='✅ '+(j.msg||'開始しました'); } }
  }catch(e){ res.textContent='通信エラー: '+e; }
  btn.disabled=false;
}
// 手動投票(ConfirmStop/Auto)の成否を /api/vote-status でポーリング表示。完了/失敗/締切/見送りを判定。
async function pollVoteResult(v,r,since,startMsg,md){
  var res=document.getElementById('v-res'); var t0=Date.now(), maxMs=6*60*1000;
  while(Date.now()-t0 < maxMs){
    await new Promise(function(rs){ setTimeout(rs,4000); });
    var s; try{ s=await (await fetch('/api/vote-status?venue='+encodeURIComponent(v)+'&race='+r+'&since='+encodeURIComponent(since))).json(); }catch(e){ continue; }
    if(!s||s.ok===false){ continue; }
    var sec=Math.round((Date.now()-t0)/1000);
    if(s.total>0 && !s.running){
      if(s.fail>0){ res.textContent='⚠ 投票に失敗があります（投票完了'+s.done+' / 失敗'+s.fail+(s.closed?' / 締切'+s.closed:'')+(s.skip?' / 見送り'+s.skip:'')+'）。/history でご確認ください。'; }
      else if(s.done>0){ res.textContent='✅ 投票完了（'+s.done+'件）'+(s.closed?' ／ 締切'+s.closed:'')+(s.skip?' ／ 見送り'+s.skip:''); }
      else if(s.closed>0||s.skip>0){ res.textContent='ℹ 投票成立せず（締切'+s.closed+' / 見送り'+s.skip+'）'; }
      else { res.textContent='ℹ 記録なし。/history でご確認ください。'; }
      return;
    }
    res.textContent='⏳ '+startMsg+'…投票処理中（'+sec+'秒経過'+(s.total>0?'・記録'+s.total+'件':'')+(md==='ConfirmStop'?'・サーバのIPATで購入操作待ちの場合あり':'')+'）';
  }
  res.textContent='⌛ 投票結果を確認できませんでした（タイムアウト）。/history でご確認ください。';
}
async function setNav(v,r){
  var j; try{ j=await (await fetch('/api/races')).json(); }catch(e){ return; }
  var list=(j.races||[]).slice().sort(function(a,b){ return String(a.post||'').localeCompare(String(b.post||''))||String(a.venue).localeCompare(String(b.venue))||(a.race-b.race); });
  var idx=-1; for(var i=0;i<list.length;i++){ if(list[i].venue===v && (''+list[i].race)===(''+r)){ idx=i; break; } }
  var prev=idx>0?list[idx-1]:null, next=(idx>=0&&idx<list.length-1)?list[idx+1]:null;
  function lnk(x,lbl){ return x?('<a class="back" href="/buyme?venue='+encodeURIComponent(x.venue)+'&race='+x.race+'">'+lbl+' '+esc(x.post)+' '+esc(x.venue)+esc(x.race)+'R</a>'):('<span class="pend">'+lbl+'なし</span>'); }
  document.getElementById('rnav').innerHTML=lnk(prev,'← 前のレース')+'　｜　'+lnk(next,'次のレース →');
}
async function refreshData(){
  var v=qp('venue'),r=qp('race');
  var j; try{ j=await (await fetch('/api/buyme?venue='+encodeURIComponent(v)+'&race='+encodeURIComponent(r)+dq())).json(); }catch(e){ return; }
  if(j.error)return;
  HORSES=j.horses||[]; FRAME={}; HORSES.forEach(function(h){ FRAME[h.uma]=h.frame||0; }); renderHorses(); renderVoted(j);   // 表(オッズ/着/断層/投票済み)のみ更新=投票ビルダー(v-bt/CART/選択)は不変
  var started=j.finished||postPassed(j.post);
  if(started){ ['v-go','v-add'].forEach(function(id){ var b=document.getElementById(id); if(b){b.disabled=true;b.style.opacity='0.5';} }); }
}
async function load(){
  var v=qp('venue'),r=qp('race'),d=qp('date');
  setNav(v,r);
  var sbk=document.getElementById('sbk'); if(sbk){ sbk.href='/shutuba?venue='+encodeURIComponent(v)+'&race='+encodeURIComponent(r)+(d?'&date='+encodeURIComponent(d):''); }
  var rbk=document.getElementById('rbk'); if(rbk){ rbk.href='/reason?venue='+encodeURIComponent(v)+'&race='+encodeURIComponent(r)+(d?'&date='+encodeURIComponent(d):''); }
  var j; try{ j=await (await fetch('/api/buyme?venue='+encodeURIComponent(v)+'&race='+encodeURIComponent(r)+dq())).json(); }catch(e){ document.getElementById('hd').textContent='読込失敗'; return; }
  if(j.error){ document.getElementById('hd').textContent=esc(j.error); return; }
  document.getElementById('hd').textContent=esc(j.post)+' '+esc(j.venue)+' '+esc(j.race)+'R '+(j.dist?esc(j.dist)+'m':'')+(j.raceName?' '+esc(j.raceName):'');
  var m=j.meta||{};
  document.getElementById('meta').innerHTML=(j.finished?'<span class="tag-good">【結果確定】</span> ':'')+'軸確度 <b>'+esc(m.conf)+'</b> / 券種 '+esc(m.kind)+' / 波乱度'+esc(m.seg);
  var hb=(j.horses||[]).filter(function(h){return !h.scratched;}).slice().sort(function(a,b){return a.rk-b.rk;});
  if(hb.length>=2){ var g12=(hb[0].idx||0)-(hb[1].idx||0); var ds=[]; for(var i=0;i<hb.length-1;i++){ var gp=(hb[i].idx||0)-(hb[i+1].idx||0); if(gp>=10){ds.push((i+1)+'位後(差'+gp+')');} } document.getElementById('meta').innerHTML+=' ／ 1-2位差 '+g12+' ／ <b>断層'+(ds.length?('='+ds.join('・')):'なし')+'</b>'; }
  var ax=null; for(var i=0;i<j.horses.length;i++){ if(j.horses[i].mark==='◎'){ax=j.horses[i];break;} }
  FRAME={}; (j.horses||[]).forEach(function(h){ FRAME[h.uma]=h.frame||0; });   // 枠色の囲い馬番用
  document.getElementById('sum').innerHTML='本線：軸◎ '+(ax?wkN('',ax.uma)+' '+esc(ax.name):'(なし)');
  renderVoted(j);   // 🎫 投票済み（IPAT実投票）を本線の下に
  HORSES=j.horses||[];
  renderHorses();
  if(!HORSES.length){ document.getElementById('tb').innerHTML='<tr><td colspan="11" class="pend" style="padding:14px">この日・このレースの買目データがありません（コンピ指数未取得＝非開催日や、まだ出馬表・コンピが取り込まれていないレースの可能性）。</td></tr>'; }
  if(HORSES.some(function(h){return h.qual;})){ document.getElementById('meta').innerHTML+=' ／ 💬=定性あり(クリック/タップで表示)'; }
  else { document.getElementById('meta').innerHTML+=' ／ <span class="pend">定性データ未取得(調教/厩舎)</span>'; }
  var _tou=(j.horses||[]).length;   // 登録頭数(発売判定=枠連は9頭以上)
  var _av=BT_ALL.filter(function(b){return betSold(b,(j.venue||v||''),_tou);}); setRadios('v-bt','vbt',_av,_av[0],'onBt()');
  fillVote(j);
  renderCart();
  var started=j.finished||postPassed(j.post);
  if(started){ ['v-go','v-add'].forEach(function(id){ var b=document.getElementById(id); if(b){b.disabled=true;b.style.opacity='0.5';} }); var vg=document.getElementById('v-go'); vg.textContent=j.finished?'結果確定':'締切'; document.getElementById('v-res').textContent=(j.finished?'結果確定済み':'発走時刻を経過')+'のため投票できません。'; }
  if(j.cancelled){ ['v-go','v-add'].forEach(function(id){ var b=document.getElementById(id); if(b){b.disabled=true;b.style.opacity='0.5';} }); document.getElementById('meta').innerHTML='<span style="color:#ff6b6b;font-weight:700">🚫 このレースは取りやめ(中止)に設定されています。投票できません。</span><br>'+document.getElementById('meta').innerHTML; document.getElementById('v-res').textContent='🚫取りやめのため投票不可。'; }  // A9
  var rfp=new URLSearchParams(location.search).get('refresh'); var _rf=rfp===null?5:+rfp; if(_rf>0)setInterval(refreshData,_rf*1000);  // A5:データのみ自動更新(既定5秒・?refresh=0で無効)
}
// IPAT投票可能額(残高)。初期=直近値(照会せず)、更新ボタン=IpatVote balanceをバックグラウンド照会→状態ポーリング。地方rakuten-balance移植。
async function loadIpatBal(){
  try{ var j=await (await fetch('/api/ipat-balance')).json(); var el=document.getElementById('ipat-bal'); if(!el)return;
    if(j&&j.balance!=null){ el.textContent=Number(j.balance).toLocaleString()+'円'+(j.balT?'（'+j.balT+'）':''); el.style.color='#7ee787'; }
    else { el.textContent='未取得'; el.style.color='#8a93a3'; } }catch(e){}
}
async function refreshIpatBal(){
  var el=document.getElementById('ipat-bal'), btn=document.getElementById('ipat-bal-btn'); if(!el)return;
  el.textContent='照会中…（IPATログイン）'; el.style.color='#e6e9ef'; if(btn)btn.disabled=true;
  try{ await fetch('/api/ipat-balance-refresh',{method:'POST'}); }catch(e){}
  var tries=0; var timer=setInterval(async function(){ tries++;
    try{ var s=await (await fetch('/api/ipat-balance-status')).json();
      if(s&&s.done){ clearInterval(timer); if(btn)btn.disabled=false;
        if(s.balance!=null){ el.textContent=Number(s.balance).toLocaleString()+'円'; el.style.color='#7ee787'; el.title=''; }
        else { el.textContent=(s.message||'未取得'); el.style.color='#ffb454'; el.title=s.message||''; } } }catch(e){}
    if(tries>45){ clearInterval(timer); if(btn)btn.disabled=false; if(('' +el.textContent).indexOf('照会中')>=0){ el.textContent='タイムアウト'; el.style.color='#ff8a8a'; } }
  },2000);
}
load(); loadIpatBal();
</script>
</div></body></html>
""";

// 出馬表(馬柱)ページ。縦=属性・横=各馬・過去走は前走最上段。/api/shutuba(shutuba.ps1)を消費するだけのDB非依存ビュー。
string ShutubaHtml() => """
<!doctype html><html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="icon" href="/favicon.ico"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<title>出馬表（馬柱）JRA</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#0b0e13;color:#e6e9ef;font-family:system-ui,'Segoe UI',sans-serif}
.wrap{max-width:100%;margin:0 auto;padding:10px}
h1{font-size:17px;margin:6px 0}
a.back{color:#7aa2ff;text-decoration:none;font-size:14px}
a.buy{display:inline-block;color:#15130a;background:#ffd479;font-weight:700;text-decoration:none;font-size:14px;padding:6px 12px;border-radius:7px}
.note{color:#8a93a3;font-size:12px;margin:6px 0}
.scroll{overflow-x:auto;border:1px solid #1b222c;border-radius:6px}
table.umc{border-collapse:collapse;font-size:11px;white-space:nowrap}
table.umc td{border:1px solid #222a35;padding:3px 5px;vertical-align:top}
td.lbl{position:sticky;left:0;z-index:2;background:#11161d;color:#8a93a3;font-weight:600;text-align:center;min-width:42px;writing-mode:vertical-rl;text-orientation:upright}
td.hcell{min-width:118px;max-width:140px;white-space:normal}
.fr{text-align:center;font-weight:800;font-size:13px;padding:4px}
.f1{background:#f3f3f3;color:#111}.f2{background:#1a1a1a;color:#fff}.f3{background:#e23b3b;color:#fff}.f4{background:#3b6fe2;color:#fff}
.f5{background:#f3d03a;color:#111}.f6{background:#3aae54;color:#fff}.f7{background:#e8862a;color:#fff}.f8{background:#e86fa0;color:#111}.f0{background:#222a35;color:#fff}
.ch{color:#9aa3b2;font-size:10px}.nm{font-weight:700;font-size:13px;white-space:normal}.sx{color:#9aa3b2;font-size:10px}
.stg{display:inline-block;min-width:16px;padding:0 3px;border-radius:3px;font-size:10px;font-weight:700;text-align:center;margin-left:4px;vertical-align:1px}
.st-nige{background:#5a2222;color:#ff9d9d}.st-senko{background:#54401e;color:#ffce7a}.st-sashi{background:#1e4630;color:#7ee0a5}.st-oikomi{background:#1e3350;color:#8ec2ff}
.mk{color:#ffd479;font-weight:800;font-size:14px}.idx{color:#7aa2ff;font-weight:700}
.sm{color:#9aa3b2;font-size:10px;white-space:normal}
.pc .p-r{font-weight:800;font-size:13px}.pc .p-t{color:#9aa3b2;font-weight:400;font-size:10px}
.pc .p-v{color:#cbd2e0}.pc .p-c{color:#9aa3b2;font-size:10px}.pc .p-cmp{color:#7fc8ff;font-size:10px;font-weight:700}.pc .p-n{color:#8a93a3;font-size:10px;white-space:normal;overflow:hidden;text-overflow:ellipsis;max-width:130px}
.pc .p-tm{color:#e6e9ef}.pc .p-x{color:#9aa3b2;font-size:10px}
.b1{background:#33290a !important}.b2{background:#23282f !important}.b3{background:#2c2113 !important}
.chk1,.chk2,.chk3{font-weight:800;padding:0 6px;border-radius:9px;color:#15130a}
.chk1{background:#f3c63a}.chk2{background:#c7cdd6}.chk3{background:#d29a55}
.empty{color:#444;text-align:center}
.wp{color:#ff8a8a;font-size:10px}.wm{color:#7ad1a0;font-size:10px}
.pc .p-mg{color:#cbd2e0;font-weight:600;font-size:10px}
/* 過去走の脚質バッジ(逃赤/先橙/差青/追緑) */
.kb{display:inline-block;min-width:15px;padding:0 3px;border-radius:3px;font-size:10px;font-weight:800;text-align:center;margin-left:3px;vertical-align:1px;color:#fff}
.k-nige{background:#e23b3b}.k-senko{background:#e8862a}.k-sashi{background:#3b6fe2}.k-oikomi{background:#3aae54}
.ivr td.ivl{writing-mode:horizontal-tb;text-orientation:mixed;font-size:9px;font-weight:600;color:#6b7382;min-width:42px}
.ivc{text-align:center;font-size:11px;color:#9aa3b2;background:#0e1218;padding:2px 4px;white-space:nowrap}
.ivc.rest{color:#ffb454;font-weight:800;background:#2e2310;border-top:2px solid #c8861f;border-bottom:2px solid #c8861f}
.ivc.lng{color:#7db4ff;font-weight:700}
.ivc .iz{color:#ffd089;font-size:9px;font-weight:700}
.umc td.avg{text-align:center;font-weight:700;color:#dfe4ee;background:#141923}
.ctrl{margin:7px 0;font-size:13px}
.ctrl select{background:#1a1f29;color:#e6e6e6;border:1px solid #39404d;border-radius:5px;padding:3px 6px;font-size:13px;margin:0 2px}
.ctrl .nav{color:#7db4ff;text-decoration:none;margin:0 6px;font-weight:600}.ctrl .nav.off{color:#555;margin:0 6px}
</style></head><body><div class="wrap">
<a class="back" href="/">🏠 コントロールに戻る</a>　<a class="back" href="/races">← 今日のレース一覧</a>　<a id="rbk" class="back" href="#">🧠 選定理由 →</a>　<a id="histlink" class="back" href="/history">📋 投票履歴 →</a>
<h1 id="hd">読込中...</h1>
<div id="ctrl" class="ctrl"></div>
<div id="buylink" style="margin:6px 0 8px"></div>
<div class="note">馬柱（各馬を列・過去5走を縦に。<b>前走が最上段</b>）。馬柱の間に前走間隔（🌿=休養明け）。<b>過去走をクリックでその日の馬柱へ</b>。買目は上の🎯リンク。着/頭・着差タイム・前半3F・上り(順位)・通過・馬体重・単勝・コンピ/h2h順位。1-3着は色分け。横スクロール可。</div>
<div class="scroll"><table class="umc" id="umc"></table></div>
<script>
function esc(s){return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function qp(k){return new URLSearchParams(location.search).get(k)||'';}
function fmtTime(t){ var s=Number(t); if(!s||isNaN(s)||s<=0)return ''; var m=Math.floor(s/60); var sec=s-m*60; return m>0?(m+'.'+(sec<10?'0':'')+sec.toFixed(1)):sec.toFixed(1); }
function chBadge(c){ return (c>=1&&c<=3)?('<span class="chk'+c+'">'+c+'</span>'):esc(c); }
// 過去走の脚質バッジ: その走の最終コーナー通過位置÷頭数で 逃/先/差/追 を判定し色分け
function kyakuBadge(p){ if(!p||!p.corner||!p.tousu)return ''; var cs=(''+p.corner).split('-').map(Number).filter(function(x){return x>0;}); if(!cs.length)return ''; var n=+p.tousu; if(!(n>0))return ''; var avg=cs.reduce(function(a,b){return a+b;},0)/cs.length; var r=avg/n,cls,lab; if(avg<=1.5||r<=0.15){cls='k-nige';lab='逃';}else if(r<=0.35){cls='k-senko';lab='先';}else if(r<=0.65){cls='k-sashi';lab='差';}else{cls='k-oikomi';lab='追';} return '<span class="kb '+cls+'" title="脚質(平均通過'+avg.toFixed(1)+'番手/'+n+'頭)">'+lab+'</span>'; }
function pcell(p){
  if(!p) return '<td class="hcell empty">—</td>';
  var b=(p.chaku>=1&&p.chaku<=3)?(' b'+p.chaku):'';
  var ag=p.agari?('上'+esc(p.agari)+(p.agariRk?'<span class="p-t">('+esc(p.agariRk)+'位)</span>':'')):'';
  var zen=p.zen3f?('前'+esc(p.zen3f)+'　'):'';
  var nav=(p.fd&&p.ven)?(' onclick="location.href=\'/shutuba?venue='+encodeURIComponent(p.ven)+'&race='+p.race+'&date='+p.fd+'\'" style="cursor:pointer" title="この日の馬柱へ"'):'';
  return '<td class="hcell pc'+b+'"'+nav+'>'
    +'<div class="p-r">'+chBadge(p.chaku)+(p.tousu?'<span class="p-t">/'+esc(p.tousu)+'頭</span>':'')+kyakuBadge(p)+((p.margin!==''&&p.margin!=null)?' <span class="p-mg">'+esc(p.margin)+'秒</span>':'')+'</div>'
    +'<div class="p-v">'+esc(p.ven)+' '+esc(p.d)+'</div>'
    +'<div class="p-c">'+esc(p.cond)+' '+esc(p.kind)+esc(p.dist)+(p.corner?'　通過'+esc(p.corner):'')+'</div>'
    +((p.cRk>0||p.cIdx>0)?'<div class="p-cmp">コンピ'+(p.cRk>0?esc(p.cRk)+'位':'-')+(p.cIdx>0?'　指'+esc(p.cIdx):'')+'</div>':'')
    +'<div class="p-n">'+esc(p.name)+'</div>'
    +'<div class="p-tm">'+esc(fmtTime(p.time))+'　'+zen+ag+'</div>'
    +'<div class="p-x">'+(p.wt?'体'+esc(p.wt)+'　':'')+esc(p.jk)+(p.kin?' '+esc(Number(p.kin)):'')+'</div>'
    +'</td>';
}
function jitStr(h){ return (h.jitokei||[]).map(function(x){return esc(x.dist)+' '+esc(fmtTime(x.t));}).join('<br>'); }
function render(j){
  var hs=j.horses||[];
  function row(lbl,cellFn,cls){ var tds=hs.map(cellFn).join(''); return '<tr><td class="lbl">'+lbl+'</td>'+tds+'</tr>'; }
  var html='';
  html+=row('枠 馬',function(h){ return '<td class="hcell fr f'+(h.frame||0)+'">'+(h.frame||'')+'枠<br>'+esc(h.uma)+'</td>'; });
  html+=row('馬名',function(h){ var stMap={'逃げ':['逃','st-nige'],'先行':['先','st-senko'],'差し':['差','st-sashi'],'追込':['追','st-oikomi']}; var stTag=(h.style&&stMap[h.style])?('<span class="stg '+stMap[h.style][1]+'" title="予測脚質(直近5走の平均通過): '+esc(h.style)+'">'+stMap[h.style][0]+'</span>'):''; return '<td class="hcell">'
    +'<div class="ch">'+esc(h.chichi)+'</div>'
    +'<div class="nm">'+esc(h.name)+stTag+'</div>'
    +'<div class="sx">'+esc(h.sex)+(h.age?esc(h.age):'')+'</div>'
    +((h.haha||h.bofu)?'<div class="sx">'+esc(h.haha)+(h.bofu?'（'+esc(h.bofu)+'）':'')+'</div>':'')
    +'</td>'; });
  html+=row('印 指数',function(h){ return '<td class="hcell">'+(h.mark?'<span class="mk">'+esc(h.mark)+'</span> ':'')+'<span class="idx">指'+esc(h.idx)+'</span>'+'<div class="sm">コンピ'+esc(h.rk)+'位 / h2h'+(h.h2hRk?esc(h.h2hRk)+'位':'-')+'</div></td>'; });
  html+=row('単勝',function(h){ return '<td class="hcell">'+(h.tan>0?'<b style="color:#ffd479">'+esc(Number(h.tan).toFixed(1))+'</b>倍':'<span class="sm">-</span>')+'</td>'; });
  html+=row('騎手',function(h){ return '<td class="hcell">'+esc(h.jk)+(h.kin?' '+esc(Number(h.kin)):'')+'</td>'; });
  html+=row('馬体重',function(h){ var wd=(h.wd!==''&&h.wd!=null)?('<span class="'+(Number(h.wd)>0?'wp':(Number(h.wd)<0?'wm':''))+'">('+(Number(h.wd)>0?'+':'')+esc(h.wd)+')</span>'):''; return '<td class="hcell">'+(h.wt>0?'<b>'+esc(h.wt)+'</b>'+wd:'<span class="sm">-</span>')+'</td>'; });
  html+=row('厩舎',function(h){ return '<td class="hcell sm">'+esc(h.trainer)+(h.owner?'<br>'+esc(h.owner):'')+(h.bokujo?'<br>'+esc(h.bokujo):'')+'</td>'; });
  html+=row('持時計',function(h){ return '<td class="hcell sm">'+jitStr(h)+'</td>'; });
  if(j.finished){ html+=row('今走',function(h){ return '<td class="hcell">'+((h.chaku>=1&&h.chaku<=3)?'<span class="chk'+h.chaku+'">'+h.chaku+'着</span>':(h.chaku>0?esc(h.chaku)+'着':'—'))+'</td>'; }); }
  function dayGap(a,b){ if(!a||!b) return null; var g=Math.round((new Date(a)-new Date(b))/86400000); return (g>=0)?g:null; }
  function gapDisp(g){ return (g>=21)?(Math.round(g/7)+'週'):(g+'日'); }
  function avgGap(h){ var p=h.past||[]; var gs=[]; for(var i=0;i<p.length-1;i++){ var g=dayGap(p[i].fd,p[i+1].fd); if(g!==null) gs.push(g); } if(!gs.length) return null; return Math.round(gs.reduce(function(a,b){return a+b;},0)/gs.length); }
  html+=row('平均間隔',function(h){ var a=avgGap(h); return '<td class="hcell avg">'+(a===null?'<span class="sm">—</span>':'中'+gapDisp(a))+'</td>'; });
  function ivCell(h,idx){
    var newer=(idx===0)?j.date:((h.past&&h.past[idx-1])?h.past[idx-1].fd:null);
    var older=(h.past&&h.past[idx])?h.past[idx].fd:null;
    var g=dayGap(newer,older);
    if(g===null) return '<td class="ivc"></td>';
    var rest=(g>=42); var a=avgGap(h);
    var lng=(a!==null&&g>=a+14&&g>=a*1.5&&!rest);
    return '<td class="ivc'+(rest?' rest':(lng?' lng':''))+'">'+(rest?'🌿':'')+'中'+gapDisp(g)+(rest?'<div class="iz">休養明け</div>':'')+'</td>';
  }
  function ivRow(idx){ return '<tr class="ivr"><td class="lbl ivl">'+(idx===0?'今走<br>間隔':'間隔')+'</td>'+hs.map(function(h){return ivCell(h,idx);}).join('')+'</tr>'; }
  var maxp=0; hs.forEach(function(h){ if(h.past&&h.past.length>maxp)maxp=h.past.length; }); if(maxp>5)maxp=5;
  for(var i=0;i<maxp;i++){ (function(idx){
    html+=ivRow(idx);
    var lbl=(idx===0)?'前走':((idx+1)+'走前');
    html+=row(lbl,function(h){ return pcell((h.past&&h.past[idx])?h.past[idx]:null); });
  })(i); }
  document.getElementById('umc').innerHTML=html;
}
function buildCtrl(j){
  var v=j.venue,r=j.race,d=j.date;
  function opts(arr,sel,suf){ return (arr||[]).map(function(x){ return '<option value="'+esc(x)+'"'+((''+x)===(''+sel)?' selected':'')+'>'+esc(x)+(suf||'')+'</option>'; }).join(''); }
  var h='開催日 <select id="s-date">'+opts(j.dates,d)+'</select>'
    +'　場 <select id="s-ven">'+opts(j.venues,v)+'</select>'
    +'　<select id="s-race">'+opts(j.races,r,'R')+'</select>'
    +'　'+(j.prevRace?'<a class="nav" href="/shutuba?venue='+encodeURIComponent(v)+'&race='+j.prevRace+'&date='+encodeURIComponent(d)+'">← 前のレース</a>':'<span class="nav off">← 前のレース</span>')
    +(j.nextRace?'<a class="nav" href="/shutuba?venue='+encodeURIComponent(v)+'&race='+j.nextRace+'&date='+encodeURIComponent(d)+'">次のレース →</a>':'<span class="nav off">次のレース →</span>');
  document.getElementById('ctrl').innerHTML=h;
  document.getElementById('s-date').onchange=function(){ location.href='/shutuba?date='+encodeURIComponent(this.value)+'&venue='+encodeURIComponent(v); };
  document.getElementById('s-ven').onchange=function(){ location.href='/shutuba?date='+encodeURIComponent(d)+'&venue='+encodeURIComponent(this.value); };
  document.getElementById('s-race').onchange=function(){ location.href='/shutuba?date='+encodeURIComponent(d)+'&venue='+encodeURIComponent(v)+'&race='+encodeURIComponent(this.value); };
}
async function load(){
  var v=qp('venue'),r=qp('race'),d=qp('date'); var dq=d?'&date='+encodeURIComponent(d):'';
  var um=qp('umas'); var uq=um?'&umas='+encodeURIComponent(um):'';   // 選択馬絞り込み(umas)をAPIへ転送
  var j; try{ j=await (await fetch('/api/shutuba?venue='+encodeURIComponent(v)+'&race='+encodeURIComponent(r)+dq+uq)).json(); }catch(e){ document.getElementById('hd').textContent='読込失敗'; return; }
  if(j.error){ document.getElementById('hd').textContent=esc(j.error); return; }
  document.getElementById('hd').textContent=esc(j.post)+' '+esc(j.venue)+' '+esc(j.race)+'R '+(j.kind?esc(j.kind):'')+(j.dist?esc(j.dist)+'m':'')+(j.raceName?' '+esc(j.raceName):'')+(j.finished?'（確定）':'');
  var qd=j.date?'&date='+encodeURIComponent(j.date):'';
  document.getElementById('buylink').innerHTML='<a class="buy" href="/buyme?venue='+encodeURIComponent(j.venue)+'&race='+encodeURIComponent(j.race)+qd+'">🎯 このレースの買目を見る →</a>';
  document.getElementById('histlink').href='/history?venue='+encodeURIComponent(j.venue)+(j.date?'&date='+encodeURIComponent(j.date):'');
  var rbk=document.getElementById('rbk'); if(rbk){ var rv=qp('venue'),rr=qp('race'),rd=qp('date'); rbk.href='/reason?venue='+encodeURIComponent(rv)+'&race='+encodeURIComponent(rr)+(rd?'&date='+encodeURIComponent(rd):''); }
  buildCtrl(j);
  render(j);
}
load();
</script>
</div></body></html>
""";
