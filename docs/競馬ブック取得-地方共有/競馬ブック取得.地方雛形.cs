// ============================================================================
// 競馬ブック取得(地方競馬 雛形) — JRA版 月別開催日程/Services/競馬ブック取得.cs から移植
// ----------------------------------------------------------------------------
// ★これは「取得インフラ」の雛形です。地方リポジトリ(namespace 地方競馬.Services)へ
//   月別開催日程/Services/競馬ブック取得.cs として置き、地方ページ用の解析(ParseXxx)と
//   保存(Save)を実装してください。
//
// ★前提(重要): 競馬ブックの「厩舎の話(danwa)」「調教(cyokyo)」は中央競馬(/cyuou/)専用で、
//   地方競馬(/chihou/)には存在しません。地方の競馬ブックは
//     /chihou/nittei(日程) /chihou/syutuba(出馬表) /chihou/cyokuzen(直前)
//     /chihou/nouken(能力検査) /chihou/seiseki(成績) /chihou/sokuhou(速報)
//   等です。取りたいページを決めて、その解析を実装してください。
//
// ★そのまま流用できる土台(JRAで実証済み):
//   - curl.exe 経由の GetHtml … .NET HttpClient だと競馬ブックにbot判定されログインページが返るため、
//     Windows標準 curl.exe を呼ぶ(UTF-8静的HTML)。
//   - EnsureLogin … secrets.local.json の KeibabookUser/KeibabookPass で /login/login へフォームログイン
//     (Laravel CSRF _token + Cookieジャー)。★競馬ブックのアカウントは中央・地方共通。
//   - DiscoverRaceIds … /chihou/nittei/{yyyyMMdd} から /chihou/syutuba/{race_id} を列挙(地方race_id=16桁)。
//   - 範囲一括(raceid単位スキップ=再開可) と raw テーブルへスナップショット保存のパターン。
//
// ★地方race_id: 16桁。先頭8桁=YYYYMMDD(開催日)。場コード/R等の並びは要検証
//   → 確実なのは「対象ページの内容/タイトルから 開催日・場・R を取得」する方式。
//
// セットアップは同フォルダ README.md を参照(Secretsキー追加/csproj/テーブルDDL/ConsoleApp配線)。
// ============================================================================
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using 地方競馬.共通.Libraly;   // Logger / Secrets

namespace 地方競馬.Services
{
    /// <summary>競馬ブック(地方/chihou)の取得・保存処理(HTTP・curl.exe・会員ログイン)の雛形。</summary>
    public class 競馬ブック取得
    {
        private const string Base = "https://p.keibabook.co.jp/chihou";   // ★中央は /cyuou
        private static readonly string CurlExe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "curl.exe");
        private const string UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36";
        private const int 既定待機ミリ秒 = 500;

        // 会員ログイン用Cookieジャー。ログイン時のみ全頭/全データが取れる。
        private static readonly string CookieJar = Path.Combine(Path.GetTempPath(), "keibabook_cookies.txt");
        private static bool _loginAttempted = false;
        private static bool _loggedIn = false;
        private static bool _skipLogin = false;

        // ============================ エントリーポイント ============================

        /// <summary>
        /// 単日取得の雛形。--date yyyy-MM-dd の各レースを取得・保存。
        /// ★ParseXxx / Save を地方の対象ページに合わせて実装してください。
        /// </summary>
        public static void 取得(string[] args)
        {
            Logger.Log("競馬ブック取得(地方) IN");
            try
            {
                string connStr = GetConnStr();
                if (string.IsNullOrWhiteSpace(connStr)) { Logger.Log("接続文字列が取得できません。"); return; }
                _skipLogin = HasFlag(args, "--no-login");
                DateOnly 対象日 = DateOnly.TryParse(GetOpt(args, "--date"), out var d) ? d : DateOnly.FromDateTime(DateTime.Today);

                var raceIds = DiscoverRaceIds(対象日);
                Logger.Log($"対象 {対象日:yyyy-MM-dd}: {raceIds.Count}レース");
                if (raceIds.Count == 0) { Logger.Log("対象レースが見つかりません。"); return; }

                int saved = 0;
                foreach (var raceId in raceIds)
                {
                    // TODO: 取りたいページのURLに変更(例 出馬表 $"{Base}/syutuba/{raceId}", 成績 $"{Base}/seiseki/{raceId}" 等)
                    var html = GetHtml($"{Base}/syutuba/{raceId}");
                    if (string.IsNullOrEmpty(html)) { Thread.Sleep(既定待機ミリ秒); continue; }

                    // TODO: 開催日/場/Rを html の <title> または内容から取得(地方race_id先頭8桁=YYYYMMDDも利用可)
                    // TODO: var recs = ParseXxx(html, ...);  → 行データへ
                    // TODO: saved += Save(connStr, ..., recs);

                    Logger.Log($"  取得: race_id={raceId}(解析未実装の雛形)");
                    Thread.Sleep(既定待機ミリ秒);
                }
                Logger.Log($"競馬ブック取得(地方) 完了: 保存 {saved}");
            }
            catch (Exception ex) { Logger.LogError("競馬ブック取得(地方)でエラー", ex); }
            finally { Logger.Log("競馬ブック取得(地方) OUT"); }
        }

        /// <summary>範囲一括の雛形。raceid単位でスキップ=再開可。--from/--to/--sleep/--no-login。</summary>
        public static void 取得範囲(string[] args)
        {
            Logger.Log("競馬ブック取得(地方) 範囲 IN");
            try
            {
                string connStr = GetConnStr();
                if (string.IsNullOrWhiteSpace(connStr)) { Logger.Log("接続文字列が取得できません。"); return; }
                DateOnly from = DateOnly.TryParse(GetOpt(args, "--from"), out var f) ? f : new DateOnly(2022, 1, 1);
                DateOnly to = DateOnly.TryParse(GetOpt(args, "--to"), out var t) ? t : DateOnly.FromDateTime(DateTime.Today);
                int sleepMs = int.TryParse(GetOpt(args, "--sleep"), out var sm) ? sm : 既定待機ミリ秒;
                _skipLogin = HasFlag(args, "--no-login");
                if (from > to) { Logger.Log("from>to"); return; }

                // TODO: 保存先テーブル名に変更(LoadExistingRaceIdsの第2引数)。
                var existing = LoadExistingRaceIds(connStr, "ここに地方の保存テーブル名");
                Logger.Log($"範囲取得(地方): {from:yyyy-MM-dd}〜{to:yyyy-MM-dd}  既存raceid={existing.Count:N0}");
                int saved = 0, skipped = 0;
                for (var date = from; date <= to; date = date.AddDays(1))
                {
                    var raceIds = DiscoverRaceIds(date);   // 初回でEnsureLogin
                    foreach (var rid in raceIds)
                    {
                        if (existing.Contains(rid)) { skipped++; continue; }
                        var html = GetHtml($"{Base}/syutuba/{rid}");   // TODO: 対象ページURL
                        // TODO: 解析→保存。saved += Save(...);
                        existing.Add(rid);
                        Thread.Sleep(sleepMs);
                    }
                }
                Logger.Log($"範囲取得(地方)完了: 保存 {saved} / スキップ {skipped}");
            }
            catch (Exception ex) { Logger.LogError("競馬ブック取得(地方) 範囲でエラー", ex); }
            finally { Logger.Log("競馬ブック取得(地方) 範囲 OUT"); }
        }

        // ============================ 発見(/chihou/nittei) ============================

        /// <summary>指定日の nittei ページから当日の race_id(16桁)を列挙します。</summary>
        private static List<string> DiscoverRaceIds(DateOnly date)
        {
            var html = GetHtml($"{Base}/nittei/{date:yyyyMMdd}");
            var seen = new HashSet<string>(); var list = new List<string>();
            // 地方race_idは16桁。中央(12桁)と異なるので \d{16} で抽出。
            foreach (Match m in Regex.Matches(html, @"/chihou/syutuba/(?<id>\d{16})"))
                if (seen.Add(m.Groups["id"].Value)) list.Add(m.Groups["id"].Value);
            list.Sort();
            return list;
        }

        // ============================ HTTP(curl.exe) ============================

        /// <summary>curl.exe を Cookieジャー付きで実行し標準出力をUTF-8で返す(低レベル)。</summary>
        private static string RunCurl(params string[] args)
        {
            try
            {
                var psi = new System.Diagnostics.ProcessStartInfo
                {
                    FileName = File.Exists(CurlExe) ? CurlExe : "curl",
                    RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true,
                };
                psi.ArgumentList.Add("-s");
                psi.ArgumentList.Add("-A"); psi.ArgumentList.Add(UserAgent);
                psi.ArgumentList.Add("--max-time"); psi.ArgumentList.Add("60");
                psi.ArgumentList.Add("-b"); psi.ArgumentList.Add(CookieJar);
                psi.ArgumentList.Add("-c"); psi.ArgumentList.Add(CookieJar);
                foreach (var a in args) psi.ArgumentList.Add(a);
                using var p = System.Diagnostics.Process.Start(psi)!;
                using var ms = new MemoryStream();
                p.StandardOutput.BaseStream.CopyTo(ms);
                p.WaitForExit();
                return System.Text.Encoding.UTF8.GetString(ms.ToArray());
            }
            catch (Exception ex) { Logger.LogError("curl実行に失敗", ex); return string.Empty; }
        }

        /// <summary>ページ取得(必要なら先に会員ログイン)。</summary>
        private static string GetHtml(string url) { EnsureLogin(); return RunCurl(url); }

        /// <summary>
        /// secrets.local.json(KeibabookUser/KeibabookPass)があれば競馬ブックweb会員ログインを1回だけ実行。
        /// ★競馬ブックのアカウントは中央・地方共通。無い/失敗時は非ログイン(一部のみ)で継続。
        /// </summary>
        private static void EnsureLogin()
        {
            if (_loginAttempted) return;
            _loginAttempted = true;
            if (_skipLogin) { Logger.Log("--no-login: 非ログインで取得します。"); return; }
            var user = Secrets.KeibabookUser; var pass = Secrets.KeibabookPass;
            if (string.IsNullOrWhiteSpace(user) || string.IsNullOrWhiteSpace(pass))
            { Logger.Log("競馬ブックの資格情報(secrets.local.json: KeibabookUser/KeibabookPass)が無いため非ログインで取得します。"); return; }

            try { if (File.Exists(CookieJar)) File.Delete(CookieJar); } catch { }
            var loginUrl = "https://p.keibabook.co.jp/login/login";
            var page = RunCurl(loginUrl);   // ① GET で _token と Cookie
            var token = Regex.Match(page, @"name=""_token""[^>]*value=""(?<v>[^""]+)""");
            if (!token.Success) { Logger.Log("ログインページの_token(CSRF)を取得できませんでした。非ログインで継続。"); return; }
            var resp = RunCurl("-L",   // ② 資格情報POST(リダイレクト追従)
                "--data-urlencode", $"_token={token.Groups["v"].Value}",
                "--data-urlencode", $"login_id={user}",
                "--data-urlencode", $"pswd={pass}",
                "--data-urlencode", "service=keibabook",
                "--data-urlencode", "referer=",
                "--data-urlencode", "autologin=1",
                "--data-urlencode", "submitbutton=ログインする",
                loginUrl);
            _loggedIn = !Regex.IsMatch(resp, @"name=""pswd""");   // 成功すると遷移先にログインフォーム(pswd)が無い
            Logger.Log(_loggedIn ? "競馬ブックにログインしました。" : "競馬ブックのログインに失敗(KeibabookUser/Pass確認)。非ログインで継続。");
        }

        // ============================ 保存(雛形) ============================

        /// <summary>指定テーブルに保存済みの raceid 集合(範囲取得のスキップ用)。</summary>
        private static HashSet<string> LoadExistingRaceIds(string connStr, string table)
        {
            var set = new HashSet<string>();
            try
            {
                using var conn = new SqlConnection(connStr); conn.Open();
                using var cmd = conn.CreateCommand(); cmd.CommandText = $"SELECT DISTINCT raceid FROM [{table}]"; cmd.CommandTimeout = 120;
                using var rd = cmd.ExecuteReader();
                while (rd.Read()) { var v = rd[0]?.ToString(); if (!string.IsNullOrEmpty(v)) set.Add(v); }
            }
            catch (Exception ex) { Logger.LogError("既存raceid読込に失敗(全件取得扱いで継続)", ex); }
            return set;
        }

        // TODO: 地方の対象ページ用に Parse / Save を実装。
        //   JRA版の ParseDanwa / Save / Save調教(Microsoft.Data.SqlClient の raw INSERT、取得日時スナップショット)が雛形になります。
        //   テーブルDDLは JRA tools/keibabook-danwa-schema.sql / keibabook-cyokyo-schema.sql を参照。

        // ============================ 補助 ============================

        private static string StripTags(string html)
        {
            var text = Regex.Replace(html, @"<[^>]+>", " ");
            text = WebUtility.HtmlDecode(text);
            return Regex.Replace(text, @"\s+", " ").Trim();
        }
        private static string GetConnStr()
        {
            var cfg = new ConfigurationBuilder().SetBasePath(AppContext.BaseDirectory).AddJsonFile("appsettings.json", optional: false).AddEnvironmentVariables().Build();
            return cfg.GetConnectionString("DefaultConnection") ?? string.Empty;
        }
        private static string? GetOpt(string[] args, string name) { int i = Array.IndexOf(args, name); return (i >= 0 && i + 1 < args.Length) ? args[i + 1] : null; }
        private static bool HasFlag(string[] args, string name) => Array.IndexOf(args, name) >= 0;
    }
}
