// 役割: 日刊スポーツ「極ウマ」中央競馬(JRA)コンピから、コンピ指数を取得しDBの コンピ指数 へ保存します。
// 構成: chuo/compi_archive.php?year=YYYY(過去の年インデックス) / chuo/compi.php(当週) → 各開催の
//   chuo/compi_detail.php?kaicode=… (.newspaper レイアウト) を解析。
//   kaicode = "1"+西暦4桁+場コード2桁+MMDD+"000" (14桁。例 12026050614000 = 2026/06/14 場コード05=東京)。
//   ※地方競馬は "2"始まり、中央競馬は "1"始まり。場コードは JRA 01札幌〜10小倉。
// ★中央のアーカイブ/詳細はログイン不要・静的HTML・UTF-8。地方(要ログイン+Selenium)と異なり HttpClient+正規表現で取得します。
// 保存: 取得日時付きスナップショット(再取得は別行=指数・順位の変遷を残す)。
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using 中央競馬.共通.Libraly;

namespace 中央競馬.Services
{
    /// <summary>極ウマ 中央競馬(JRA)コンピ指数の取得・保存処理(HTTP・ログイン不要)。</summary>
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

        private const string ArchiveUrl = "https://goku-uma.nikkansports.com/chuo/compi_archive.php";
        private const string CurrentUrl = "https://goku-uma.nikkansports.com/chuo/compi.php";
        private const string DetailUrlBase = "https://goku-uma.nikkansports.com/chuo/compi_detail.php";

        // 極ウマのdetail/archiveは .NET HttpClient(TLSフィンガープリント)だとbot判定でログインページが返るため、
        // 確実に通る Windows標準 curl.exe を呼び出して取得する(curlは同条件でデータを返す)。
        private static readonly string CurlExe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "curl.exe");
        private const string UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36";

        // kaicodeの場コード(2桁)→JRA場名。netkeiba取込と同じ並び。
        private static readonly Dictionary<string, string> 場コード = new()
        {
            ["01"] = "札幌", ["02"] = "函館", ["03"] = "福島", ["04"] = "新潟", ["05"] = "東京",
            ["06"] = "中山", ["07"] = "中京", ["08"] = "京都", ["09"] = "阪神", ["10"] = "小倉",
        };

        /// <summary>大量取得時のdetailページ間の既定待機(ミリ秒)。</summary>
        private const int 既定待機ミリ秒 = 600;

        /// <summary>
        /// fetch-compi エントリーポイント。対象日(既定=今日)の全開催のコンピ指数を取得して保存します。
        /// </summary>
        /// <param name="args">[1..]に任意で --date yyyy-MM-dd / --venue &lt;場名&gt; / --kaicode &lt;code&gt; / --no-dump。</param>
        public static void 取得(string[] args)
        {
            Logger.Log("コンピ指数取得 IN");
            try
            {
                string connStr = GetConnStr();
                if (string.IsNullOrWhiteSpace(connStr)) { Logger.Log("接続文字列が取得できません。"); return; }

                string? dateOpt = GetOpt(args, "--date");
                string? venueOpt = GetOpt(args, "--venue");
                string? kaicodeOpt = GetOpt(args, "--kaicode");
                DateOnly 対象日 = DateOnly.TryParse(dateOpt, out var d) ? d : DateOnly.FromDateTime(DateTime.Today);

                List<string> kaicodes;
                if (!string.IsNullOrWhiteSpace(kaicodeOpt))
                {
                    kaicodes = new List<string> { kaicodeOpt!.Trim() };
                }
                else
                {
                    // 当週(compi.php)と当年アーカイブ(compi_archive.php?year=)の両方から集めて対象日で絞る。
                    var all = new HashSet<string>();
                    foreach (var kc in CollectKaicodes(GetHtml(CurrentUrl))) all.Add(kc);
                    foreach (var kc in CollectKaicodes(GetHtml($"{ArchiveUrl}?year={対象日.Year}"))) all.Add(kc);
                    kaicodes = all
                        .Where(kc => ParseKaicode(kc) is { } m && m.開催日 == 対象日
                                     && (string.IsNullOrWhiteSpace(venueOpt) || m.場名.Contains(venueOpt!)))
                        .ToList();
                    Logger.Log($"対象 {対象日:yyyy-MM-dd}: {kaicodes.Count}開催 [{string.Join(",", kaicodes.Select(k => ParseKaicode(k)?.場名 ?? k))}]");
                }
                if (kaicodes.Count == 0) { Logger.Log("対象の開催(kaicode)が見つかりません。--date/--venue を確認、または当週未掲載の可能性。"); return; }

                int totalSaved = 0, totalRace = 0;
                foreach (var kc in kaicodes)
                {
                    var meta = ParseKaicode(kc);
                    if (meta == null) { Logger.Log($"kaicode解析不可: {kc}"); continue; }
                    var (開催日, 場名) = meta.Value;

                    var recs = ParseDetailHtml(GetHtml($"{DetailUrlBase}?kaicode={kc}"));
                    if (recs.Count == 0) { Logger.Log($"  指数行を抽出できません: {場名} {開催日:yyyy-MM-dd}(未掲載/構造差?)"); continue; }

                    int saved = Save(connStr, 開催日, 場名, recs);
                    totalSaved += saved; totalRace += recs.Select(r => r.レース番号).Distinct().Count();
                    Logger.Log($"  保存 {saved}行 / {recs.Select(r => r.レース番号).Distinct().Count()}R ({場名} {開催日:yyyy-MM-dd})");
                    Thread.Sleep(既定待機ミリ秒);
                }
                Logger.Log($"コンピ指数取得 完了: 合計 {totalSaved}行 / {totalRace}R / {kaicodes.Count}開催");
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
        /// 範囲一括取得(バックフィル)。compi_archive.php?year=YYYY の年インデックスから全開催を辿り、未取得分を保存します。
        /// </summary>
        /// <param name="args">[1..]に任意で --from yyyy-MM-dd / --to yyyy-MM-dd / --venue &lt;場名&gt; / --force / --sleep &lt;ms&gt;。</param>
        public static void 取得範囲(string[] args)
        {
            DateOnly from = DateOnly.TryParse(GetOpt(args, "--from"), out var f) ? f : new DateOnly(2022, 1, 1);
            DateOnly to = DateOnly.TryParse(GetOpt(args, "--to"), out var t) ? t : DateOnly.FromDateTime(DateTime.Today);
            取得範囲(from, to, GetOpt(args, "--venue"), HasFlag(args, "--force"),
                     int.TryParse(GetOpt(args, "--sleep"), out var sm) ? sm : 既定待機ミリ秒);
        }

        /// <summary>
        /// 範囲一括取得(バックフィル)。年インデックス(compi_archive.php?year=)を辿り、未取得(開催日×場)分のみ保存します。
        /// </summary>
        /// <param name="from">取得開始日(含む)。</param>
        /// <param name="to">取得終了日(含む)。</param>
        /// <param name="venueOpt">場名フィルタ(省略可)。</param>
        /// <param name="force">取得済み(開催日×場)でも再取得(別スナップショット)するか。</param>
        /// <param name="sleepMs">detailページ間の待機ミリ秒。</param>
        public static void 取得範囲(DateOnly from, DateOnly to, string? venueOpt = null, bool force = false, int sleepMs = 既定待機ミリ秒)
        {
            Logger.Log("コンピ指数 範囲取得 IN");
            try
            {
                string connStr = GetConnStr();
                if (string.IsNullOrWhiteSpace(connStr)) { Logger.Log("接続文字列が取得できません。"); return; }
                if (from > to) { Logger.Log("from が to より後です。"); return; }

                var existing = LoadExistingKeys(connStr);
                Logger.Log($"範囲取得: {from:yyyy-MM-dd}〜{to:yyyy-MM-dd}{(venueOpt != null ? " 場=" + venueOpt : "")}  既存(開催×場)={existing.Count:N0}件");

                // 年ごとにアーカイブインデックスを開き、全 kaicode を収集 → 範囲・場でフィルタ。
                var targets = new List<string>();
                var seen = new HashSet<string>();
                for (int year = from.Year; year <= to.Year; year++)
                {
                    var html = GetHtml($"{ArchiveUrl}?year={year}");
                    foreach (var kc in CollectKaicodes(html))
                    {
                        var meta = ParseKaicode(kc);
                        if (meta == null) continue;
                        if (meta.Value.開催日 < from || meta.Value.開催日 > to) continue;
                        if (!string.IsNullOrWhiteSpace(venueOpt) && !meta.Value.場名.Contains(venueOpt!)) continue;
                        if (seen.Add(kc)) targets.Add(kc);
                    }
                    Logger.Log($"  {year}年インデックス: 累計対象 {targets.Count}件");
                    Thread.Sleep(sleepMs);
                }

                targets = targets.OrderBy(kc => ParseKaicode(kc)?.開催日 ?? DateOnly.MinValue).ThenBy(kc => kc).ToList();
                Logger.Log($"取得対象: {targets.Count:N0}開催(場×日)。未取得分のみ保存します。");

                int totalSaved = 0, doneDetail = 0, skipped = 0;
                foreach (var kc in targets)
                {
                    var meta = ParseKaicode(kc)!.Value;
                    string key = $"{meta.開催日:yyyyMMdd}|{meta.場名}";
                    if (!force && existing.Contains(key)) { skipped++; continue; }

                    var recs = ParseDetailHtml(GetHtml($"{DetailUrlBase}?kaicode={kc}"));
                    Thread.Sleep(sleepMs);
                    if (recs.Count == 0) { Logger.Log($"  指数行なし: {meta.場名} {meta.開催日:yyyy-MM-dd}(休催/未掲載/構造差?)"); existing.Add(key); doneDetail++; continue; }

                    int saved = Save(connStr, meta.開催日, meta.場名, recs);
                    existing.Add(key);
                    totalSaved += saved; doneDetail++;

                    if (doneDetail % 25 == 0)
                        Logger.Log($"  進捗: {doneDetail}/{targets.Count - skipped} 取得(直近 {meta.開催日:yyyy-MM-dd} {meta.場名})  累計保存 {totalSaved:N0}行  スキップ {skipped}");
                }

                Logger.Log($"範囲取得 完了: 取得 {doneDetail}開催 / 保存 {totalSaved:N0}行 / スキップ(取得済) {skipped}");
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

        // ===================== HTTP =====================

        /// <summary>指定URLを curl.exe で取得しUTF-8デコードして返す。失敗時は空文字列。</summary>
        private static string GetHtml(string url)
        {
            try
            {
                var psi = new System.Diagnostics.ProcessStartInfo
                {
                    FileName = File.Exists(CurlExe) ? CurlExe : "curl",
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                };
                psi.ArgumentList.Add("-s");
                psi.ArgumentList.Add("-A");
                psi.ArgumentList.Add(UserAgent);
                psi.ArgumentList.Add("--max-time");
                psi.ArgumentList.Add("60");
                psi.ArgumentList.Add(url);

                using var p = System.Diagnostics.Process.Start(psi)!;
                using var ms = new MemoryStream();
                p.StandardOutput.BaseStream.CopyTo(ms);
                p.WaitForExit();
                return System.Text.Encoding.UTF8.GetString(ms.ToArray());
            }
            catch (Exception ex)
            {
                Logger.LogError($"curl取得に失敗しました: {url}", ex);
                return string.Empty;
            }
        }

        /// <summary>インデックスHTMLから compi_detail の kaicode を重複排除して集めます。</summary>
        private static List<string> CollectKaicodes(string html)
        {
            var list = new List<string>();
            var seen = new HashSet<string>();
            foreach (Match m in Regex.Matches(html ?? string.Empty, @"compi_detail\.php\?kaicode=(?<k>\d{10,})"))
            {
                if (seen.Add(m.Groups["k"].Value)) list.Add(m.Groups["k"].Value);
            }
            return list;
        }

        /// <summary>kaicode("1"+YYYY+場コード2桁+MMDD+"000") を 開催日・場名 に分解。JRA(prefix 1)以外はnull。</summary>
        public static (DateOnly 開催日, string 場名)? ParseKaicode(string kaicode)
        {
            if (string.IsNullOrWhiteSpace(kaicode) || kaicode.Length != 14 || kaicode[0] != '1') return null;
            try
            {
                int year = int.Parse(kaicode.Substring(1, 4), CultureInfo.InvariantCulture);
                string cc = kaicode.Substring(5, 2);
                int month = int.Parse(kaicode.Substring(7, 2), CultureInfo.InvariantCulture);
                int day = int.Parse(kaicode.Substring(9, 2), CultureInfo.InvariantCulture);
                if (!場コード.TryGetValue(cc, out var 場名)) return null;
                return (new DateOnly(year, month, day), 場名);
            }
            catch { return null; }
        }

        // ===================== 詳細(compi_detail.php)の解析 =====================
        // .newspaper[data-racenum=N] が1レース。各 .line_frame=1頭(先頭はヘッダ行=馬番が数値でないので除外)。
        //   馬番=span.horseNum / 馬名=p.horseName(aタグ内) / 指数=class に row-s_compi を含むdivの data-sort。

        /// <summary>compi_detail.php のHTMLから各レースの 馬番/馬名/指数/指数順位 を抽出します。</summary>
        public static List<Rec> ParseDetailHtml(string html)
        {
            var result = new List<Rec>();
            if (string.IsNullOrEmpty(html)) return result;

            var blockStarts = Regex.Matches(html, @"<div class=""newspaper[^""]*"" data-racenum=""(?<r>\d+)""");
            for (int b = 0; b < blockStarts.Count; b++)
            {
                if (!int.TryParse(blockStarts[b].Groups["r"].Value, out var R) || R <= 0) continue;
                int start = blockStarts[b].Index;
                int end = b + 1 < blockStarts.Count ? blockStarts[b + 1].Index : html.Length;
                var block = html.Substring(start, end - start);

                var recs = new List<Rec>();
                var lfStarts = Regex.Matches(block, @"<div class=""line_frame[^""]*"">");
                for (int i = 0; i < lfStarts.Count; i++)
                {
                    int s = lfStarts[i].Index;
                    int e = i + 1 < lfStarts.Count ? lfStarts[i + 1].Index : block.Length;
                    var lf = block.Substring(s, e - s);

                    // 馬番(ヘッダ行は「馬番」の文字で数値化できず除外)。
                    var numM = Regex.Match(lf, @"class=""horseNum""[^>]*>\s*(\d+)");
                    if (!numM.Success || !int.TryParse(numM.Groups[1].Value, out var 馬番) || 馬番 <= 0) continue;

                    // 指数: class に row-s_compi を含むdivの data-sort(無い行=取消等は除外)。
                    var compiM = Regex.Match(lf, @"class=""[^""]*row-s_compi[^""]*""[^>]*data-sort=""(\d+)""");
                    if (!compiM.Success || !int.TryParse(compiM.Groups[1].Value, out var 指数) || 指数 <= 0) continue;

                    var nameM = Regex.Match(lf, @"class=""horseName""[^>]*>(?<v>.*?)</p>", RegexOptions.Singleline);
                    string? 馬名 = nameM.Success ? StripTags(nameM.Groups["v"].Value) : null;
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

        private static string StripTags(string html)
        {
            var text = Regex.Replace(html, @"<[^>]+>", " ");
            text = WebUtility.HtmlDecode(text);
            return Regex.Replace(text, @"\s+", " ").Trim();
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

        // ===================== 補助 =====================

        private static string GetConnStr()
        {
            var cfg = new ConfigurationBuilder()
                .SetBasePath(AppContext.BaseDirectory)
                .AddJsonFile("appsettings.json", optional: false)
                .AddEnvironmentVariables()
                .Build();
            return cfg.GetConnectionString("DefaultConnection") ?? string.Empty;
        }

        private static string? GetOpt(string[] args, string name)
        {
            int i = Array.IndexOf(args, name);
            return (i >= 0 && i + 1 < args.Length) ? args[i + 1] : null;
        }

        private static bool HasFlag(string[] args, string name) => args.Contains(name);
    }
}
