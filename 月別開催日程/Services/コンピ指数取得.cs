// 役割: 日刊スポーツ「極ウマ」地方全場コンピから、コンピ指数(馬番コンピ)を取得しDBの コンピ指数 へ保存します。
// 構成: compi.php(日付→開催場のインデックス) → 各場の compi_detail.php?kaicode=… (馬番コンピ表) を解析。
//   kaicode = "2"+西暦4桁+場コード2桁+MMDD+"000" (例 22026360618000 = 2026/06/18 場コード36=門別)。
//   馬番コンピ表 table.umaban: 行=1レース、列=指数順位(1..16降順)、セル「馬番<改行>指数」。馬名は無し(馬番のみ)。
// ログイン: PIANO ID(クロスドメインiframe)のため、永続Chromeプロファイルで「初回だけ手動ログイン→以降Cookie維持」。
// 保存: 取得日時付きスナップショット(再取得は別行=指数・順位の変遷を残す)。場名は場コード→場名マスタ(高知/園田/門別…)へ正規化。
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using OpenQA.Selenium;
using 中央競馬.共通.Libraly;
using 中央競馬.共通.Models;

namespace 中央競馬.Services
{
    /// <summary>極ウマ 地方全場コンピ指数の取得・保存処理。</summary>
    public class コンピ指数取得
    {
        /// <summary>1レース1頭分のコンピ指数レコード。</summary>
        public sealed class Rec
        {
            public int レース番号;
            public int 馬番;
            public string? 馬名;
            public int 指数;
            public int 指数順位;
            public int 頭数;
        }

        private const string DetailUrlBase = "https://goku-uma.nikkansports.com/chiho_c/compi_detail.php";

        /// <summary>
        /// fetch-compi エントリーポイント。
        /// </summary>
        /// <param name="args">[1..]に任意で --date yyyy-MM-dd / --venue &lt;場名&gt; / --kaicode &lt;code&gt; / --headless / --no-dump。</param>
        public static void 取得(string[] args)
        {
            Logger.Log("コンピ指数取得 IN");
            try
            {
                var cfg = LoadConfig();
                var g = cfg.GetSection("GokuUma");
                string connStr = cfg.GetConnectionString("DefaultConnection") ?? string.Empty;
                if (string.IsNullOrWhiteSpace(connStr)) { Logger.Log("接続文字列が取得できません。"); return; }

                string profileDir = Val(g, "ProfileDir", Path.Combine(Path.GetTempPath(), "gokuuma-profile"));
                string chihoCUrl = Val(g, "ChihoCUrl", "https://goku-uma.nikkansports.com/chiho_c/");
                string compiUrl = Val(g, "CompiUrl", "https://goku-uma.nikkansports.com/chiho_c/compi.php");
                string loginUrl = Val(g, "LoginUrl", "https://goku-uma.nikkansports.com/membership/login/");
                string dumpDir = Val(g, "DumpDir", Path.Combine(Path.GetTempPath(), "compi-dump"));
                int assistSec = int.TryParse(g["ManualLoginAssistSeconds"], out var a) ? a : 120;
                bool headlessCfg = bool.TryParse(g["Headless"], out var h) && h;

                string? dateOpt = GetOpt(args, "--date");
                string? venueOpt = GetOpt(args, "--venue");
                string? kaicodeOpt = GetOpt(args, "--kaicode");
                bool headless = headlessCfg || HasFlag(args, "--headless");
                bool doDump = !HasFlag(args, "--no-dump");
                DateOnly 対象日 = DateOnly.TryParse(dateOpt, out var d) ? d : DateOnly.FromDateTime(DateTime.Today);

                var driver = WebDriverHelper.InitializeDriverWithProfile(chihoCUrl, profileDir, headless);
                if (driver == null) { Logger.Log("WebDriver初期化に失敗。"); return; }

                try
                {
                    if (!EnsureLoggedIn(driver, chihoCUrl, loginUrl, assistSec))
                    {
                        Logger.Log("極ウマのログイン状態を確認できませんでした(初回は画面で手動ログインしてください)。");
                        return;
                    }

                    // 取得対象の kaicode 一覧を決める
                    List<string> kaicodes;
                    if (!string.IsNullOrWhiteSpace(kaicodeOpt))
                    {
                        kaicodes = new List<string> { kaicodeOpt!.Trim() };
                    }
                    else
                    {
                        kaicodes = CollectKaicodes(driver, compiUrl, 対象日, venueOpt);
                        Logger.Log($"compi.php インデックス: {対象日:yyyy-MM-dd} の対象 {kaicodes.Count}場 [{string.Join(",", kaicodes.Select(k => ParseKaicode(k)?.場名 ?? k))}]");
                    }
                    if (kaicodes.Count == 0) { Logger.Log("対象の開催(kaicode)が見つかりません。--date/--venue を確認、または当日未掲載の可能性。"); return; }

                    if (doDump) Directory.CreateDirectory(dumpDir);

                    int totalSaved = 0, totalRace = 0;
                    foreach (var kc in kaicodes)
                    {
                        var meta = ParseKaicode(kc);
                        if (meta == null) { Logger.Log($"kaicode解析不可: {kc}"); continue; }
                        var (開催日, 場名) = meta.Value;

                        string url = $"{DetailUrlBase}?kaicode={kc}";
                        Logger.Log($"detail取得: {開催日:yyyy-MM-dd} {場名} ({url})");
                        driver.Navigate().GoToUrl(url);
                        System.Threading.Thread.Sleep(800);

                        if (doDump)
                        {
                            string dumpPath = Path.Combine(dumpDir, $"compi_{kc}.html");
                            try { File.WriteAllText(dumpPath, driver.PageSource ?? string.Empty, System.Text.Encoding.UTF8); } catch { }
                        }

                        var recs = ParseDetail(driver);
                        if (recs.Count == 0) { Logger.Log($"  指数行を抽出できません: {場名} {開催日:yyyy-MM-dd}(table.umaban未検出?)。ダンプ確認。"); continue; }

                        int saved = Save(connStr, 開催日, 場名, recs);
                        int races = recs.Select(r => r.レース番号).Distinct().Count();
                        totalSaved += saved; totalRace += races;
                        Logger.Log($"  保存 {saved}行 / {races}R ({場名} {開催日:yyyy-MM-dd})");
                    }
                    Logger.Log($"コンピ指数取得 完了: 合計 {totalSaved}行 / {totalRace}R / {kaicodes.Count}場");
                }
                finally
                {
                    try { driver.Quit(); } catch { }
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("コンピ指数取得でエラー", ex);
            }
            finally
            {
                Logger.Log("コンピ指数取得 OUT");
            }
        }

        /// <summary>
        /// 範囲一括取得(バックフィル)。compi.php?year=YYYY の年インデックスから全開催を辿り、未取得分を保存します。
        /// </summary>
        /// <param name="args">[1..]に任意で --from yyyy-MM-dd / --to yyyy-MM-dd / --venue &lt;場名&gt; / --headless / --no-dump / --force / --sleep &lt;ms&gt;。</param>
        public static void 取得範囲(string[] args)
        {
            DateOnly from = DateOnly.TryParse(GetOpt(args, "--from"), out var f) ? f : new DateOnly(2022, 1, 1);
            DateOnly to = DateOnly.TryParse(GetOpt(args, "--to"), out var t) ? t : DateOnly.FromDateTime(DateTime.Today);
            取得範囲(from, to, GetOpt(args, "--venue"), HasFlag(args, "--headless"), HasFlag(args, "--dump"), HasFlag(args, "--force"),
                     int.TryParse(GetOpt(args, "--sleep"), out var sm) ? sm : 600);
        }

        /// <summary>
        /// 範囲一括取得(バックフィル/補完)。compi.php?year=YYYY の年インデックスから全開催を辿り、未取得分を保存します。
        /// 既存の補完処理(fetch-range 等)からも呼べるよう、型付き引数の入口を用意しています。
        /// </summary>
        /// <param name="from">取得開始日(含む)。</param>
        /// <param name="to">取得終了日(含む)。</param>
        /// <param name="venueOpt">場名フィルタ(省略可)。</param>
        /// <param name="headless">ヘッドレス起動(プロファイルにログイン済みであること)。</param>
        /// <param name="doDump">取得HTMLをDumpDirへ保存するか。</param>
        /// <param name="force">取得済み(開催日×場)でも再取得(別スナップショット)するか。</param>
        /// <param name="sleepMs">detailページ間の待機ミリ秒。</param>
        public static void 取得範囲(DateOnly from, DateOnly to, string? venueOpt = null, bool headless = false, bool doDump = false, bool force = false, int sleepMs = 600)
        {
            Logger.Log("コンピ指数 範囲取得 IN");
            try
            {
                var cfg = LoadConfig();
                var g = cfg.GetSection("GokuUma");
                string connStr = cfg.GetConnectionString("DefaultConnection") ?? string.Empty;
                if (string.IsNullOrWhiteSpace(connStr)) { Logger.Log("接続文字列が取得できません。"); return; }

                string profileDir = Val(g, "ProfileDir", Path.Combine(Path.GetTempPath(), "gokuuma-profile"));
                string chihoCUrl = Val(g, "ChihoCUrl", "https://goku-uma.nikkansports.com/chiho_c/");
                string compiUrl = Val(g, "CompiUrl", "https://goku-uma.nikkansports.com/chiho_c/compi.php");
                string loginUrl = Val(g, "LoginUrl", "https://goku-uma.nikkansports.com/membership/login/");
                string dumpDir = Val(g, "DumpDir", Path.Combine(Path.GetTempPath(), "compi-dump"));
                int assistSec = int.TryParse(g["ManualLoginAssistSeconds"], out var a) ? a : 180;
                bool headlessCfg = bool.TryParse(g["Headless"], out var hc) && hc;
                headless = headless || headlessCfg;
                if (from > to) { Logger.Log("from が to より後です。"); return; }

                // 取得済み(開催日×場)を読み込み、スキップ判定に使う(再開可能)。
                var existing = LoadExistingKeys(connStr);
                Logger.Log($"範囲取得: {from:yyyy-MM-dd}〜{to:yyyy-MM-dd}{(venueOpt != null ? " 場=" + venueOpt : "")}  既存(開催×場)={existing.Count:N0}件");

                var driver = WebDriverHelper.InitializeDriverWithProfile(chihoCUrl, profileDir, headless);
                if (driver == null) { Logger.Log("WebDriver初期化に失敗。"); return; }
                if (doDump) Directory.CreateDirectory(dumpDir);

                int totalSaved = 0, doneDetail = 0, skipped = 0, processed = 0;
                try
                {
                    if (!EnsureLoggedIn(driver, chihoCUrl, loginUrl, assistSec))
                    { Logger.Log("ログイン状態を確認できませんでした(初回は画面で手動ログイン)。"); return; }

                    // 年ごとにインデックスを開き、全 kaicode を収集 → 範囲・場でフィルタ。
                    var targets = new List<string>();
                    var seen = new HashSet<string>();
                    for (int year = from.Year; year <= to.Year; year++)
                    {
                        var kcs = CollectKaicodesForYear(driver, compiUrl, year);
                        foreach (var kc in kcs)
                        {
                            var meta = ParseKaicode(kc);
                            if (meta == null) continue;
                            if (meta.Value.開催日 < from || meta.Value.開催日 > to) continue;
                            if (!string.IsNullOrWhiteSpace(venueOpt) && !meta.Value.場名.Contains(venueOpt)) continue;
                            if (seen.Add(kc)) targets.Add(kc);
                        }
                        Logger.Log($"  {year}年インデックス: 累計対象 {targets.Count}件");
                    }

                    // 古い順に処理(中断時に古い方から埋まる)。
                    targets = targets.OrderBy(kc => ParseKaicode(kc)?.開催日 ?? DateOnly.MinValue)
                                     .ThenBy(kc => kc).ToList();
                    Logger.Log($"取得対象: {targets.Count:N0}開催(場×日)。未取得分のみ保存します。");

                    foreach (var kc in targets)
                    {
                        var meta = ParseKaicode(kc)!.Value;
                        string key = $"{meta.開催日:yyyyMMdd}|{meta.場名}";
                        if (!force && existing.Contains(key)) { skipped++; continue; }

                        // メモリ肥大対策: 一定件数ごとにChromeを再起動(プロファイルで自動ログイン維持)。
                        if (processed > 0 && processed % DriverRestartEvery == 0)
                        {
                            try { driver.Quit(); } catch { }
                            driver = WebDriverHelper.InitializeDriverWithProfile(chihoCUrl, profileDir, headless);
                            if (driver == null) { Logger.Log("Chrome再初期化に失敗。中断します。"); break; }
                            EnsureLoggedIn(driver, chihoCUrl, loginUrl, assistSec);
                        }
                        processed++;

                        string url = $"{DetailUrlBase}?kaicode={kc}";
                        try { driver.Navigate().GoToUrl(url); } catch { }
                        System.Threading.Thread.Sleep(sleepMs);

                        if (doDump)
                        {
                            try { File.WriteAllText(Path.Combine(dumpDir, $"compi_{kc}.html"), driver.PageSource ?? string.Empty, System.Text.Encoding.UTF8); } catch { }
                        }

                        var recs = ParseDetail(driver);
                        if (recs.Count == 0) { Logger.Log($"  指数行なし: {meta.場名} {meta.開催日:yyyy-MM-dd}(休催/未掲載/構造差?)"); existing.Add(key); doneDetail++; continue; }

                        int saved = Save(connStr, meta.開催日, meta.場名, recs);
                        existing.Add(key);
                        totalSaved += saved; doneDetail++;

                        if (doneDetail % 25 == 0)
                            Logger.Log($"  進捗: {doneDetail}/{targets.Count - skipped} 取得(直近 {meta.開催日:yyyy-MM-dd} {meta.場名})  累計保存 {totalSaved:N0}行  スキップ {skipped}");
                    }

                    Logger.Log($"範囲取得 完了: 取得 {doneDetail}開催 / 保存 {totalSaved:N0}行 / スキップ(取得済) {skipped}");
                }
                finally
                {
                    try { driver?.Quit(); } catch { }
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("コンピ指数 範囲取得でエラー", ex);
            }
            finally
            {
                Logger.Log("コンピ指数 範囲取得 OUT");
            }
        }

        /// <summary>大量取得時にChromeを再起動する間隔(detail件数)。</summary>
        private const int DriverRestartEvery = 300;

        /// <summary>compi.php?year=YYYY の年インデックスから全 compi_detail の kaicode を集めます(日付フィルタなし)。</summary>
        private static List<string> CollectKaicodesForYear(IWebDriver driver, string compiUrl, int year)
        {
            var sep = compiUrl.Contains('?') ? "&" : "?";
            try { driver.Navigate().GoToUrl($"{compiUrl}{sep}year={year}"); System.Threading.Thread.Sleep(1200); } catch { }
            var list = new List<string>();
            var seen = new HashSet<string>();
            foreach (var aLink in driver.FindElements(By.CssSelector("a[href*='compi_detail.php']")))
            {
                var m = Regex.Match(aLink.GetAttribute("href") ?? string.Empty, @"kaicode=(\d{10,})");
                if (m.Success && seen.Add(m.Groups[1].Value)) list.Add(m.Groups[1].Value);
            }
            return list;
        }

        /// <summary>コンピ指数に既に保存済みの (開催日|場名) キー集合を返す(再開スキップ用)。</summary>
        private static HashSet<string> LoadExistingKeys(string connStr)
        {
            var set = new HashSet<string>();
            try
            {
                using var conn = new SqlConnection(connStr);
                conn.Open();
                using var cmd = conn.CreateCommand();
                cmd.CommandText = "SELECT DISTINCT 開催日, 開催場所 FROM コンピ指数";
                cmd.CommandTimeout = 120;
                using var rd = cmd.ExecuteReader();
                while (rd.Read())
                {
                    var dt = Convert.ToDateTime(rd[0]);
                    set.Add($"{dt:yyyyMMdd}|{rd[1]}");
                }
            }
            catch (Exception ex) { Logger.LogError("既存キー読込に失敗(全件取得扱いで継続)", ex); }
            return set;
        }

        // ===================== ログイン =====================

        /// <summary>body[data-login-status] を見てログイン状態を確認。未ログインなら手動ログインを待つ。</summary>
        private static bool EnsureLoggedIn(IWebDriver driver, string chihoCUrl, string loginUrl, int assistSec)
        {
            if (IsLogin(driver)) return true;
            Logger.Log($"未ログイン。ログイン画面を開き、最大{assistSec}秒 手動ログイン(PIANO ID)を待ちます。");
            try { driver.Navigate().GoToUrl(loginUrl); } catch { }
            var end = DateTime.UtcNow.AddSeconds(Math.Max(10, assistSec));
            while (DateTime.UtcNow < end)
            {
                System.Threading.Thread.Sleep(2000);
                if (IsLogin(driver)) { Logger.Log("ログインを確認しました。"); return true; }
            }
            try { driver.Navigate().GoToUrl(chihoCUrl); System.Threading.Thread.Sleep(1500); } catch { }
            return IsLogin(driver);
        }

        /// <summary>body の data-login-status 属性が "login" かどうか。</summary>
        private static bool IsLogin(IWebDriver driver)
        {
            try
            {
                var v = ((IJavaScriptExecutor)driver)
                    .ExecuteScript("return document.body && document.body.getAttribute('data-login-status');") as string;
                return string.Equals(v, "login", StringComparison.OrdinalIgnoreCase);
            }
            catch { return false; }
        }

        // ===================== インデックス(compi.php)から kaicode 収集 =====================

        /// <summary>compi.php(?year=)から、対象日(+任意で場名)に一致する compi_detail の kaicode を集めます。</summary>
        private static List<string> CollectKaicodes(IWebDriver driver, string compiUrl, DateOnly 対象日, string? venueFilter)
        {
            var sep = compiUrl.Contains('?') ? "&" : "?";
            try { driver.Navigate().GoToUrl($"{compiUrl}{sep}year={対象日.Year}"); System.Threading.Thread.Sleep(1000); } catch { }

            var found = new List<string>();
            var seen = new HashSet<string>();
            var links = driver.FindElements(By.CssSelector("a[href*='compi_detail.php']"));
            foreach (var a in links)
            {
                string href = a.GetAttribute("href") ?? string.Empty;
                var m = Regex.Match(href, @"kaicode=(\d{10,})");
                if (!m.Success) continue;
                string kc = m.Groups[1].Value;
                var meta = ParseKaicode(kc);
                if (meta == null) continue;
                if (meta.Value.開催日 != 対象日) continue;
                if (!string.IsNullOrWhiteSpace(venueFilter))
                {
                    string link = (a.Text ?? string.Empty).Trim();
                    if (!meta.Value.場名.Contains(venueFilter) && !link.Contains(venueFilter)) continue;
                }
                if (seen.Add(kc)) found.Add(kc);
            }
            return found;
        }

        /// <summary>kaicode("2"+YYYY+場コード2桁+MMDD+"000") を 開催日・場名 に分解。失敗時null。</summary>
        public static (DateOnly 開催日, string 場名)? ParseKaicode(string kaicode)
        {
            if (string.IsNullOrWhiteSpace(kaicode) || kaicode.Length < 13 || kaicode[0] != '2') return null;
            try
            {
                int year = int.Parse(kaicode.Substring(1, 4), CultureInfo.InvariantCulture);
                string 場コード = kaicode.Substring(5, 2).TrimStart('0');
                int month = int.Parse(kaicode.Substring(7, 2), CultureInfo.InvariantCulture);
                int day = int.Parse(kaicode.Substring(9, 2), CultureInfo.InvariantCulture);
                string 場名 = 場名マスタ.GetByCode(場コード);
                return (new DateOnly(year, month, day), 場名);
            }
            catch { return null; }
        }

        // ===================== 詳細(compi_detail.php)の馬番コンピを解析 =====================
        // ライブの compi_detail は .newspaper[data-racenum=N] divレイアウト(印刷用の table.umaban とは別)。
        //   1ブロック=1レース。各 .line_frame=1頭。馬番=.row_horseNum .horseNum / 馬名=.row_horseName .horseName /
        //   指数=.row-s_compi の data-sort(推奨は bg-r クラス)。指数順位は指数降順で採番。

        /// <summary>compi_detail.php(.newspaper レイアウト)から各レースの 馬番/馬名/指数/指数順位 を抽出します。</summary>
        public static List<Rec> ParseDetail(IWebDriver driver)
        {
            var result = new List<Rec>();
            var blocks = driver.FindElements(By.CssSelector("div.newspaper[data-racenum]"));
            foreach (var block in blocks)
            {
                if (!int.TryParse(block.GetAttribute("data-racenum"), out var R) || R <= 0) continue;

                var recs = new List<Rec>();
                foreach (var row in block.FindElements(By.CssSelector("div.line_frame")))
                {
                    var numEl = row.FindElements(By.CssSelector(".row_horseNum .horseNum")).FirstOrDefault();
                    if (numEl == null) continue;
                    if (!int.TryParse(Regex.Replace(numEl.Text ?? string.Empty, @"[^\d]", ""), out var 馬番) || 馬番 <= 0) continue;

                    // 指数: .row-s_compi の data-sort(無ければ内側テキスト)。コンピ指数が無い行(取消等)は除外。
                    var compiEl = row.FindElements(By.CssSelector(".row-s_compi")).FirstOrDefault();
                    if (compiEl == null) continue;
                    int 指数;
                    var ds = compiEl.GetAttribute("data-sort");
                    if (!int.TryParse(ds, out 指数))
                    {
                        if (!int.TryParse(Regex.Replace(compiEl.Text ?? string.Empty, @"[^\d]", ""), out 指数)) continue;
                    }
                    if (指数 <= 0) continue;

                    string? 馬名 = row.FindElements(By.CssSelector(".row_horseName .horseName")).FirstOrDefault()?.Text?.Trim();
                    if (string.IsNullOrWhiteSpace(馬名)) 馬名 = null;

                    recs.Add(new Rec { レース番号 = R, 馬番 = 馬番, 馬名 = 馬名, 指数 = 指数 });
                }
                if (recs.Count == 0) continue;

                // 指数順位 = 指数降順で採番(同値は同順位)。
                int rank = 0, prev = int.MinValue, seen = 0;
                foreach (var r in recs.OrderByDescending(r => r.指数))
                {
                    seen++;
                    if (r.指数 != prev) { rank = seen; prev = r.指数; }
                    r.指数順位 = rank;
                }
                int 頭数 = recs.Count;
                foreach (var r in recs) r.頭数 = 頭数;
                result.AddRange(recs);
            }
            return result;
        }

        // ===================== 保存 =====================

        /// <summary>スナップショットとして コンピ指数 へ追加挿入。同一(レース×馬×取得時刻)はキー衝突で無視。</summary>
        private static int Save(string connStr, DateOnly 開催日, string 場名, List<Rec> recs)
        {
            int n = 0;
            using var conn = new SqlConnection(connStr);
            conn.Open();
            DateTime 取得日時 = DateTime.Now;
            foreach (var r in recs)
            {
                if (string.IsNullOrEmpty(場名) || r.レース番号 <= 0 || r.馬番 <= 0) continue;
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
INSERT INTO コンピ指数(開催日,開催場所,レース番号,馬番,馬名,指数,指数順位,頭数,取得日時,取得元)
VALUES(@日,@場,@R,@番,@名,@指,@順,@頭,@時,N'goku-uma')";
                cmd.Parameters.AddWithValue("@日", 開催日.ToDateTime(TimeOnly.MinValue));
                cmd.Parameters.AddWithValue("@場", 場名);
                cmd.Parameters.AddWithValue("@R", r.レース番号);
                cmd.Parameters.AddWithValue("@番", r.馬番);
                cmd.Parameters.AddWithValue("@名", (object?)r.馬名 ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@指", r.指数);
                cmd.Parameters.AddWithValue("@順", r.指数順位);
                cmd.Parameters.AddWithValue("@頭", r.頭数);
                cmd.Parameters.AddWithValue("@時", 取得日時);
                try { n += cmd.ExecuteNonQuery(); }
                catch (SqlException ex) when (ex.Number == 2601 || ex.Number == 2627) { /* 同一スナップショット重複は無視 */ }
            }
            return n;
        }

        // ===================== 補助 =====================

        private static IConfigurationRoot LoadConfig()
            => new ConfigurationBuilder()
                .SetBasePath(AppContext.BaseDirectory)
                .AddJsonFile("appsettings.json", optional: false)
                .AddEnvironmentVariables()
                .Build();

        private static string Val(IConfigurationSection s, string key, string fallback)
        {
            var v = s[key];
            return string.IsNullOrWhiteSpace(v) ? fallback : v!;
        }

        private static string? GetOpt(string[] args, string name)
        {
            int i = Array.IndexOf(args, name);
            return (i >= 0 && i + 1 < args.Length) ? args[i + 1] : null;
        }

        private static bool HasFlag(string[] args, string name) => args.Contains(name);
    }
}
