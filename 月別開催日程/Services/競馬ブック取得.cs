// 役割: 競馬ブック(p.keibabook.co.jp)の「厩舎の話」(/cyuou/danwa/0/{race_id})を取得し DBの 厩舎の話 へ保存します。
// 発見: /cyuou/nittei/{yyyyMMdd} から当日の全レースの race_id(/cyuou/syutuba/{race_id})を列挙。
//   race_id = 年4+回2+場2+日2+R2(例 202603040401 = 2026年・3回・場04(東京)・4日目・1R)。開催日/場名/R は danwa ページの<title>から取得。
// ★非ログインでは各レース一部の頭数のみ。会員ログイン実装後に全頭取得へ拡張可。静的HTML・UTF-8・curl.exeで取得(.NET HttpClientのbot判定回避)。
// 保存: 取得日時付きスナップショット(再取得は別行)。着順は 競走結果 と (開催場所,開催日,レース番号,馬番) で結合。
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.EntityFrameworkCore;
using 中央競馬.共通.Libraly;
using 中央競馬.共通.Data;
using 中央競馬.共通.Models;

namespace 中央競馬.Services
{
    /// <summary>競馬ブック「厩舎の話」の取得・保存処理(HTTP・curl.exe)。</summary>
    public class 競馬ブック取得
    {
        private const string Base = "https://p.keibabook.co.jp";
        private static readonly string CurlExe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "curl.exe");
        private const string UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36";
        private const int 既定待機ミリ秒 = 500;

        // ログイン用Cookieジャー(curlで保持)。会員ログイン時のみ全頭の厩舎の話/調教が取得できる。
        private static readonly string CookieJar = Path.Combine(Path.GetTempPath(), "keibabook_cookies.txt");
        private static bool _loginAttempted = false;
        private static bool _loggedIn = false;
        private static bool _skipLogin = false;

        /// <summary>厩舎の話 1頭分。</summary>
        private sealed class Danwa
        {
            public int 馬番;
            public int 枠番;
            public string? 馬名;
            public string? umacd;
            public string? 性齢;
            public string? 騎手;
            public string? 印;
            public string? 調教師;
            public string? コメント;
            public string? 原文;
        }

        /// <summary>
        /// fetch-danwa エントリーポイント。対象日(既定=今日)の全レースの厩舎の話を取得して保存します。
        /// </summary>
        /// <param name="args">[1..]に任意で --date yyyy-MM-dd / --raceid &lt;race_id&gt; / --sleep &lt;ms&gt;。</param>
        public static void 取得(string[] args)
        {
            Logger.Log("競馬ブック厩舎の話取得 IN");
            try
            {
                string connStr = GetConnStr();
                if (string.IsNullOrWhiteSpace(connStr)) { Logger.Log("接続文字列が取得できません。"); return; }

                string? raceidOpt = GetOpt(args, "--raceid");
                int sleepMs = int.TryParse(GetOpt(args, "--sleep"), out var sm) ? sm : 既定待機ミリ秒;
                DateOnly 対象日 = DateOnly.TryParse(GetOpt(args, "--date"), out var d) ? d : DateOnly.FromDateTime(DateTime.Today);
                _skipLogin = HasFlag(args, "--no-login");

                List<string> raceIds;
                if (!string.IsNullOrWhiteSpace(raceidOpt))
                {
                    raceIds = new List<string> { raceidOpt!.Trim() };
                }
                else
                {
                    raceIds = DiscoverRaceIds(対象日);
                    Logger.Log($"対象 {対象日:yyyy-MM-dd}: {raceIds.Count}レース");
                }
                if (raceIds.Count == 0) { Logger.Log("対象レースが見つかりません(未開催/未掲載の可能性)。"); return; }

                int totalSaved = 0, races = 0;
                foreach (var raceId in raceIds)
                {
                    var html = GetHtml($"{Base}/cyuou/danwa/0/{raceId}");
                    if (!TryParseHeader(html, out var 開催日, out var 場名, out var レース番号))
                    {
                        Logger.Log($"  ヘッダ解析不可: race_id={raceId}");
                        Thread.Sleep(sleepMs);
                        continue;
                    }
                    var recs = ParseDanwa(html);
                    if (recs.Count > 0)
                    {
                        int saved = Save(connStr, 開催日, 場名, レース番号, raceId, recs);
                        totalSaved += saved; races++;
                        Logger.Log($"  保存 {saved}頭 ({場名} {開催日:yyyy-MM-dd} {レース番号}R)");
                    }
                    else
                    {
                        Logger.Log($"  厩舎の話なし: {場名} {開催日:yyyy-MM-dd} {レース番号}R(未掲載/非ログインで非公開)");
                    }
                    Thread.Sleep(sleepMs);
                }
                Logger.Log($"競馬ブック厩舎の話取得 完了: 合計 {totalSaved}頭 / {races}レース / {raceIds.Count}対象");
            }
            catch (Exception ex)
            {
                Logger.LogError("競馬ブック厩舎の話取得でエラー", ex);
            }
            finally
            {
                Logger.Log("競馬ブック厩舎の話取得 OUT");
            }
        }

        /// <summary>
        /// fetch-danwa-range。指定期間の各開催日の厩舎の話を未取得(raceid単位)だけ取得して保存します(再開可)。
        /// </summary>
        /// <param name="args">[1..]に任意で --from yyyy-MM-dd / --to yyyy-MM-dd / --sleep ms / --no-login。</param>
        public static void 取得範囲(string[] args)
        {
            Logger.Log("競馬ブック厩舎の話 範囲取得 IN");
            try
            {
                string connStr = GetConnStr();
                if (string.IsNullOrWhiteSpace(connStr)) { Logger.Log("接続文字列が取得できません。"); return; }
                DateOnly from = DateOnly.TryParse(GetOpt(args, "--from"), out var f) ? f : new DateOnly(2022, 1, 1);
                DateOnly to = DateOnly.TryParse(GetOpt(args, "--to"), out var t) ? t : DateOnly.FromDateTime(DateTime.Today);
                int sleepMs = int.TryParse(GetOpt(args, "--sleep"), out var sm) ? sm : 既定待機ミリ秒;
                _skipLogin = HasFlag(args, "--no-login");
                if (from > to) { Logger.Log("from が to より後です。"); return; }

                var existing = LoadExistingRaceIds(connStr, "厩舎の話");
                Logger.Log($"範囲取得(厩舎の話): {from:yyyy-MM-dd}〜{to:yyyy-MM-dd}  既存raceid={existing.Count:N0}");
                int totalSaved = 0, races = 0, skipped = 0;
                for (var date = from; date <= to; date = date.AddDays(1))
                {
                    var raceIds = DiscoverRaceIds(date); // 初回呼び出しでEnsureLogin
                    if (raceIds.Count == 0) continue;
                    int dayRaces = 0;
                    foreach (var rid in raceIds)
                    {
                        if (existing.Contains(rid)) { skipped++; continue; }
                        var html = GetHtml($"{Base}/cyuou/danwa/0/{rid}");
                        if (TryParseHeader(html, out var 開催日, out var 場名, out var レース番号))
                        {
                            var recs = ParseDanwa(html);
                            if (recs.Count > 0) { totalSaved += Save(connStr, 開催日, 場名, レース番号, rid, recs); races++; dayRaces++; }
                        }
                        existing.Add(rid);
                        Thread.Sleep(sleepMs);
                    }
                    if (dayRaces > 0) Logger.Log($"  {date:yyyy-MM-dd}: {dayRaces}レース取得(累計 {races}R/{totalSaved}頭, スキップ{skipped})");
                }
                Logger.Log($"範囲取得(厩舎の話)完了: {races}レース/{totalSaved}頭 / スキップ(取得済){skipped}");
            }
            catch (Exception ex) { Logger.LogError("厩舎の話 範囲取得でエラー", ex); }
            finally { Logger.Log("競馬ブック厩舎の話 範囲取得 OUT"); }
        }

        /// <summary>
        /// fetch-cyokyo-range。指定期間の各開催日の調教を未取得(raceid単位)だけ取得して保存します(再開可)。
        /// </summary>
        /// <param name="args">[1..]に任意で --from yyyy-MM-dd / --to yyyy-MM-dd / --sleep ms / --no-login。</param>
        public static void 調教取得範囲(string[] args)
        {
            Logger.Log("競馬ブック調教 範囲取得 IN");
            try
            {
                string connStr = GetConnStr();
                if (string.IsNullOrWhiteSpace(connStr)) { Logger.Log("接続文字列が取得できません。"); return; }
                DateOnly from = DateOnly.TryParse(GetOpt(args, "--from"), out var f) ? f : new DateOnly(2022, 1, 1);
                DateOnly to = DateOnly.TryParse(GetOpt(args, "--to"), out var t) ? t : DateOnly.FromDateTime(DateTime.Today);
                int sleepMs = int.TryParse(GetOpt(args, "--sleep"), out var sm) ? sm : 既定待機ミリ秒;
                _skipLogin = HasFlag(args, "--no-login");
                bool force = HasFlag(args, "--force"); // 既存raceidも再取得(非ログイン時の部分取得スタブを全頭で上書き=最新スナップショット採用)
                if (from > to) { Logger.Log("from が to より後です。"); return; }

                var existing = LoadExistingRaceIds(connStr, "調教");
                Logger.Log($"範囲取得(調教): {from:yyyy-MM-dd}〜{to:yyyy-MM-dd}  既存raceid={existing.Count:N0}{(force ? "  [--force=既存も再取得]" : "")}");
                int totalUma = 0, totalLine = 0, races = 0, skipped = 0;
                for (var date = from; date <= to; date = date.AddDays(1))
                {
                    var raceIds = DiscoverRaceIds(date);
                    if (raceIds.Count == 0) continue;
                    int dayRaces = 0;
                    foreach (var rid in raceIds)
                    {
                        if (!force && existing.Contains(rid)) { skipped++; continue; }
                        var html = GetHtml($"{Base}/cyuou/cyokyo/0/0/{rid}");
                        if (TryParseHeader(html, out var 開催日, out var 場名, out var レース番号))
                        {
                            var umas = Parse調教(html);
                            if (umas.Count > 0) { var (u, l) = Save調教(connStr, 開催日, 場名, レース番号, rid, umas); totalUma += u; totalLine += l; races++; dayRaces++; }
                        }
                        existing.Add(rid);
                        Thread.Sleep(sleepMs);
                    }
                    if (dayRaces > 0) Logger.Log($"  {date:yyyy-MM-dd}: {dayRaces}レース取得(累計 {races}R/{totalUma}頭/{totalLine}本, スキップ{skipped})");
                }
                Logger.Log($"範囲取得(調教)完了: {races}レース/{totalUma}頭/{totalLine}本 / スキップ(取得済){skipped}");
            }
            catch (Exception ex) { Logger.LogError("調教 範囲取得でエラー", ex); }
            finally { Logger.Log("競馬ブック調教 範囲取得 OUT"); }
        }

        /// <summary>指定テーブルに保存済みの raceid 集合を返す(範囲取得のスキップ用)。</summary>
        private static HashSet<string> LoadExistingRaceIds(string connStr, string table)
        {
            var set = new HashSet<string>();
            try
            {
                using var conn = new SqlConnection(connStr);
                conn.Open();
                using var cmd = conn.CreateCommand();
                cmd.CommandText = $"SELECT DISTINCT raceid FROM [{table}]";
                cmd.CommandTimeout = 120;
                using var rd = cmd.ExecuteReader();
                while (rd.Read()) { var v = rd[0]?.ToString(); if (!string.IsNullOrEmpty(v)) set.Add(v); }
            }
            catch (Exception ex) { Logger.LogError("既存raceid読込に失敗(全件取得扱いで継続)", ex); }
            return set;
        }

        /// <summary>調教1頭分のサマリ。</summary>
        private sealed class CyokyoUma
        {
            public int 馬番;
            public int 枠番;
            public string? 馬名;
            public string? umacd;
            public string? 追い切り短評;
            public string? 矢印;
            public List<CyokyoLine> 明細 = new();
        }

        /// <summary>調教1本(ライン)分。</summary>
        private sealed class CyokyoLine
        {
            public int 行番号;
            public string? 種別;
            public string? mark;
            public string? 騎乗者;
            public string? 日付;
            public string? コース;
            public string? 馬場;
            public string[] タイム = new string[7]; // 1哩,7F,6F,5F,半哩,3F,1F
            public string? 回り位置;
            public string? 脚色;
            public string? 短評;
            public string? 原文;
        }

        /// <summary>
        /// fetch-cyokyo エントリーポイント。対象日(既定=今日)の全レースの調教(サマリ+明細)を取得して保存します。
        /// </summary>
        /// <param name="args">[1..]に任意で --date yyyy-MM-dd / --raceid &lt;race_id&gt; / --sleep &lt;ms&gt;。</param>
        public static void 調教取得(string[] args)
        {
            Logger.Log("競馬ブック調教取得 IN");
            try
            {
                string connStr = GetConnStr();
                if (string.IsNullOrWhiteSpace(connStr)) { Logger.Log("接続文字列が取得できません。"); return; }

                string? raceidOpt = GetOpt(args, "--raceid");
                int sleepMs = int.TryParse(GetOpt(args, "--sleep"), out var sm) ? sm : 既定待機ミリ秒;
                DateOnly 対象日 = DateOnly.TryParse(GetOpt(args, "--date"), out var d) ? d : DateOnly.FromDateTime(DateTime.Today);
                _skipLogin = HasFlag(args, "--no-login");

                List<string> raceIds = !string.IsNullOrWhiteSpace(raceidOpt)
                    ? new List<string> { raceidOpt!.Trim() }
                    : DiscoverRaceIds(対象日);
                if (string.IsNullOrWhiteSpace(raceidOpt)) Logger.Log($"対象 {対象日:yyyy-MM-dd}: {raceIds.Count}レース");
                if (raceIds.Count == 0) { Logger.Log("対象レースが見つかりません(未開催/未掲載の可能性)。"); return; }

                int totalUma = 0, totalLine = 0, races = 0;
                foreach (var raceId in raceIds)
                {
                    var html = GetHtml($"{Base}/cyuou/cyokyo/0/0/{raceId}");
                    if (!TryParseHeader(html, out var 開催日, out var 場名, out var レース番号))
                    {
                        Logger.Log($"  ヘッダ解析不可: race_id={raceId}");
                        Thread.Sleep(sleepMs);
                        continue;
                    }
                    var umas = Parse調教(html);
                    if (umas.Count > 0)
                    {
                        var (u, l) = Save調教(connStr, 開催日, 場名, レース番号, raceId, umas);
                        totalUma += u; totalLine += l; races++;
                        Logger.Log($"  保存 {u}頭/{l}本 ({場名} {開催日:yyyy-MM-dd} {レース番号}R)");
                    }
                    else
                    {
                        Logger.Log($"  調教なし: {場名} {開催日:yyyy-MM-dd} {レース番号}R(未掲載/非ログインで非公開)");
                    }
                    Thread.Sleep(sleepMs);
                }
                Logger.Log($"競馬ブック調教取得 完了: 合計 {totalUma}頭 / {totalLine}本 / {races}レース / {raceIds.Count}対象");
            }
            catch (Exception ex)
            {
                Logger.LogError("競馬ブック調教取得でエラー", ex);
            }
            finally
            {
                Logger.Log("競馬ブック調教取得 OUT");
            }
        }

        /// <summary>調教ページから各馬の 追い切り短評/矢印 と 調教明細(各ライン)を抽出します。</summary>
        private static List<CyokyoUma> Parse調教(string html)
        {
            var result = new List<CyokyoUma>();
            // 馬ごとに <table class="default cyokyo" id="cyokyo{umacd}"> ... (内側に cyokyodata テーブルが入れ子)。
            var starts = Regex.Matches(html, @"<table class=""default cyokyo"" id=""cyokyo(?<cd>\d+)"">");
            for (int i = 0; i < starts.Count; i++)
            {
                int s = starts[i].Index;
                int e = i + 1 < starts.Count ? starts[i + 1].Index : html.Length;
                var block = html.Substring(s, e - s);
                var uma = new CyokyoUma { umacd = starts[i].Groups["cd"].Value };

                // サマリ部 = 内側 cyokyodata テーブルより前の領域。
                int dataIdx = block.IndexOf("<table class=\"cyokyodata\"", StringComparison.Ordinal);
                var head = dataIdx > 0 ? block.Substring(0, dataIdx) : block;

                var 馬番M = Regex.Match(head, @"class=""umaban"">\s*(\d+)");
                if (!馬番M.Success || !int.TryParse(馬番M.Groups[1].Value, out var 馬番) || 馬番 <= 0) continue;
                uma.馬番 = 馬番;
                var 枠M = Regex.Match(head, @"class=""waku\d*""[^>]*>\s*(?:<p[^>]*>)?\s*(\d+)");
                uma.枠番 = 枠M.Success ? int.Parse(枠M.Groups[1].Value) : 0;
                var 馬M = Regex.Match(head, @"/db/uma/\d+""[^>]*>(?<nm>[^<]+)</a>");
                uma.馬名 = 馬M.Success ? WebUtility.HtmlDecode(馬M.Groups["nm"].Value).Trim() : null;
                var tanpyoM = Regex.Match(head, @"<td class=""tanpyo"">(?<v>.*?)</td>", RegexOptions.Singleline);
                uma.追い切り短評 = tanpyoM.Success ? StripTags(tanpyoM.Groups["v"].Value) : null;
                var yaM = Regex.Match(head, @"<td class=""yajirusi"">(?<v>.*?)</td>", RegexOptions.Singleline);
                uma.矢印 = yaM.Success ? StripTags(yaM.Groups["v"].Value) : null;

                // 明細 = 内側 cyokyodata の tbody 行(tr.time / tr.oikiri)。
                var dataTable = Regex.Match(block, @"<table class=""cyokyodata"">.*?</table>", RegexOptions.Singleline);
                if (dataTable.Success)
                {
                    int lineNo = 0;
                    foreach (Match row in Regex.Matches(dataTable.Value, @"<tr class=""(?<cls>time|oikiri)"">(?<r>.*?)</tr>", RegexOptions.Singleline))
                    {
                        var tds = Regex.Matches(row.Groups["r"].Value, @"<td[^>]*>(?<v>.*?)</td>", RegexOptions.Singleline)
                            .Select(m => StripTags(m.Groups["v"].Value)).ToList();
                        if (tds.Count < 15) continue; // 想定16列(動画含む)
                        var line = new CyokyoLine
                        {
                            行番号 = lineNo++,
                            種別 = row.Groups["cls"].Value == "oikiri" ? "追切" : "時計",
                            mark = NullIfEmpty(tds[0]),
                            騎乗者 = NullIfEmpty(tds[1]),
                            日付 = NullIfEmpty(tds[2]),
                            コース = NullIfEmpty(tds[3]),
                            馬場 = NullIfEmpty(tds[4]),
                            回り位置 = NullIfEmpty(tds[12]),
                            脚色 = NullIfEmpty(tds[13]),
                            短評 = NullIfEmpty(tds[14]),
                            原文 = StripTags(row.Groups["r"].Value),
                        };
                        for (int c = 0; c < 7; c++) line.タイム[c] = tds[5 + c];
                        uma.明細.Add(line);
                    }
                }
                result.Add(uma);
            }
            return result;
        }

        private static (int 頭, int 本) Save調教(string connStr, DateOnly 開催日, string 場名, int レース番号, string raceId, List<CyokyoUma> umas)
        {
            int 頭 = 0, 本 = 0;
            using var conn = new SqlConnection(connStr);
            conn.Open();
            DateTime 取得日時 = DateTime.Now;
            foreach (var u in umas)
            {
                if (u.馬番 <= 0) continue;
                using (var cmd = conn.CreateCommand())
                {
                    cmd.CommandText = @"
INSERT INTO 調教(開催日,開催場所,レース番号,raceid,馬番,枠番,馬名,umacd,追い切り短評,矢印,取得日時,取得元)
VALUES(@日,@場,@R,@rid,@番,@枠,@名,@uc,@tp,@ya,@時,N'keibabook')";
                    AddP(cmd, "@日", 開催日.ToDateTime(TimeOnly.MinValue)); AddP(cmd, "@場", 場名); AddP(cmd, "@R", レース番号);
                    AddP(cmd, "@rid", raceId); AddP(cmd, "@番", u.馬番); AddP(cmd, "@枠", u.枠番);
                    AddP(cmd, "@名", (object?)u.馬名 ?? DBNull.Value); AddP(cmd, "@uc", (object?)u.umacd ?? DBNull.Value);
                    AddP(cmd, "@tp", (object?)u.追い切り短評 ?? DBNull.Value); AddP(cmd, "@ya", (object?)u.矢印 ?? DBNull.Value);
                    AddP(cmd, "@時", 取得日時);
                    try { 頭 += cmd.ExecuteNonQuery(); } catch (SqlException ex) when (ex.Number == 2601 || ex.Number == 2627) { }
                }
                foreach (var l in u.明細)
                {
                    using var cmd = conn.CreateCommand();
                    cmd.CommandText = @"
INSERT INTO 調教明細(開催日,開催場所,レース番号,raceid,馬番,umacd,行番号,種別,mark,騎乗者,日付,コース,馬場,
  タイム1哩,タイム7F,タイム6F,タイム5F,タイム半哩,タイム3F,タイム1F,回り位置,脚色,短評,原文,取得日時,取得元)
VALUES(@日,@場,@R,@rid,@番,@uc,@ln,@sb,@mk,@nr,@hd,@cs,@bb,@t0,@t1,@t2,@t3,@t4,@t5,@t6,@mw,@as,@tp,@raw,@時,N'keibabook')";
                    AddP(cmd, "@日", 開催日.ToDateTime(TimeOnly.MinValue)); AddP(cmd, "@場", 場名); AddP(cmd, "@R", レース番号);
                    AddP(cmd, "@rid", raceId); AddP(cmd, "@番", u.馬番); AddP(cmd, "@uc", (object?)u.umacd ?? DBNull.Value);
                    AddP(cmd, "@ln", l.行番号); AddP(cmd, "@sb", (object?)l.種別 ?? DBNull.Value); AddP(cmd, "@mk", (object?)l.mark ?? DBNull.Value);
                    AddP(cmd, "@nr", (object?)l.騎乗者 ?? DBNull.Value); AddP(cmd, "@hd", (object?)l.日付 ?? DBNull.Value);
                    AddP(cmd, "@cs", (object?)l.コース ?? DBNull.Value); AddP(cmd, "@bb", (object?)l.馬場 ?? DBNull.Value);
                    AddP(cmd, "@t0", (object?)NullIfEmpty(l.タイム[0]) ?? DBNull.Value); AddP(cmd, "@t1", (object?)NullIfEmpty(l.タイム[1]) ?? DBNull.Value);
                    AddP(cmd, "@t2", (object?)NullIfEmpty(l.タイム[2]) ?? DBNull.Value); AddP(cmd, "@t3", (object?)NullIfEmpty(l.タイム[3]) ?? DBNull.Value);
                    AddP(cmd, "@t4", (object?)NullIfEmpty(l.タイム[4]) ?? DBNull.Value); AddP(cmd, "@t5", (object?)NullIfEmpty(l.タイム[5]) ?? DBNull.Value);
                    AddP(cmd, "@t6", (object?)NullIfEmpty(l.タイム[6]) ?? DBNull.Value);
                    AddP(cmd, "@mw", (object?)l.回り位置 ?? DBNull.Value); AddP(cmd, "@as", (object?)l.脚色 ?? DBNull.Value);
                    AddP(cmd, "@tp", (object?)l.短評 ?? DBNull.Value); AddP(cmd, "@raw", (object?)Trunc(l.原文, 400) ?? DBNull.Value);
                    AddP(cmd, "@時", 取得日時);
                    try { 本 += cmd.ExecuteNonQuery(); } catch (SqlException ex) when (ex.Number == 2601 || ex.Number == 2627) { }
                }
            }
            return (頭, 本);
        }

        private static void AddP(SqlCommand cmd, string n, object v) => cmd.Parameters.AddWithValue(n, v);
        private static string? NullIfEmpty(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
        private static string? Trunc(string? s, int max) => s == null ? null : (s.Length <= max ? s : s.Substring(0, max));

        /// <summary>指定日の nittei ページから当日の全レースの race_id を列挙します。</summary>
        private static List<string> DiscoverRaceIds(DateOnly date)
        {
            var html = GetHtml($"{Base}/cyuou/nittei/{date:yyyyMMdd}");
            var seen = new HashSet<string>();
            var list = new List<string>();
            foreach (Match m in Regex.Matches(html, @"/cyuou/syutuba/(?<id>\d{12})"))
            {
                if (seen.Add(m.Groups["id"].Value)) list.Add(m.Groups["id"].Value);
            }
            list.Sort();
            return list;
        }

        /// <summary>danwa ページの &lt;title&gt;(例「厩舎の話 | 2026年6月14日東京1R | 競馬ブック」)から開催日・場名・R を取得。</summary>
        private static bool TryParseHeader(string html, out DateOnly 開催日, out string 場名, out int レース番号)
        {
            開催日 = default; 場名 = string.Empty; レース番号 = 0;
            var title = Regex.Match(html, @"<title>(?<v>.*?)</title>", RegexOptions.Singleline);
            if (!title.Success) return false;
            var m = Regex.Match(title.Groups["v"].Value, @"(?<y>\d{4})年(?<mo>\d{1,2})月(?<d>\d{1,2})日(?<ba>.+?)(?<r>\d{1,2})R");
            if (!m.Success) return false;
            try
            {
                開催日 = new DateOnly(int.Parse(m.Groups["y"].Value), int.Parse(m.Groups["mo"].Value), int.Parse(m.Groups["d"].Value));
                場名 = m.Groups["ba"].Value.Trim();
                レース番号 = int.Parse(m.Groups["r"].Value);
                return レース番号 > 0 && !string.IsNullOrEmpty(場名);
            }
            catch { return false; }
        }

        /// <summary>table.danwa の各行から 厩舎の話 を抽出します。</summary>
        private static List<Danwa> ParseDanwa(string html)
        {
            var result = new List<Danwa>();
            var table = Regex.Match(html, @"<table class=""default danwa""[^>]*>.*?</table>", RegexOptions.Singleline);
            if (!table.Success) return result;

            foreach (Match row in Regex.Matches(table.Value, @"<tr>(?<r>.*?)</tr>", RegexOptions.Singleline))
            {
                var tr = row.Groups["r"].Value;
                var danwaCell = Regex.Match(tr, @"<td class=""danwa"">(?<v>.*?)</td>", RegexOptions.Singleline);
                if (!danwaCell.Success) continue; // ヘッダ行(th)はスキップ

                var 馬番M = Regex.Match(tr, @"class=""umaban"">\s*(\d+)");
                if (!馬番M.Success || !int.TryParse(馬番M.Groups[1].Value, out var 馬番) || 馬番 <= 0) continue;

                var 枠M = Regex.Match(tr, @"class=""waku\d*""[^>]*>\s*(?:<p[^>]*>)?\s*(\d+)");
                var 馬M = Regex.Match(tr, @"/db/uma/(?<cd>\d+)""[^>]*>(?<nm>[^<]+)</a>");
                var 騎手M = Regex.Match(tr, @"/db/kisyu/[^""]*""[^>]*>(?<nm>[^<]+)</a>");
                var 性齢M = Regex.Match(tr, @"(?<v>[牡牝セ騙騸セン]+\s*\d+)");

                var 原文 = StripTags(danwaCell.Groups["v"].Value);
                var (印, 調教師, 本文) = ParseComment(原文);

                result.Add(new Danwa
                {
                    馬番 = 馬番,
                    枠番 = 枠M.Success ? int.Parse(枠M.Groups[1].Value) : 0,
                    馬名 = 馬M.Success ? WebUtility.HtmlDecode(馬M.Groups["nm"].Value).Trim() : null,
                    umacd = 馬M.Success ? 馬M.Groups["cd"].Value : null,
                    性齢 = 性齢M.Success ? Regex.Replace(性齢M.Groups["v"].Value, @"\s", "") : null,
                    騎手 = 騎手M.Success ? WebUtility.HtmlDecode(騎手M.Groups["nm"].Value).Trim() : null,
                    印 = 印,
                    調教師 = 調教師,
                    コメント = 本文,
                    原文 = 原文,
                });
            }
            return result;
        }

        /// <summary>「○スウェーバック【天間師】本文」を 印・調教師・本文 に分解。</summary>
        private static (string? 印, string? 調教師, string? 本文) ParseComment(string raw)
        {
            if (string.IsNullOrWhiteSpace(raw)) return (null, null, null);
            string? 印 = null;
            var mark = Regex.Match(raw, @"^(?<m>[◎○●▲△☆★◇◆注消？])");
            if (mark.Success) 印 = mark.Groups["m"].Value;

            string? 調教師 = null, 本文 = raw;
            var br = Regex.Match(raw, @"【(?<t>[^】]+)】(?<body>.*)$", RegexOptions.Singleline);
            if (br.Success)
            {
                調教師 = Regex.Replace(br.Groups["t"].Value.Trim(), @"師$", "");
                本文 = br.Groups["body"].Value.Trim();
            }
            return (印, 調教師, 本文);
        }

        // ===================== 保存 =====================

        private static int Save(string connStr, DateOnly 開催日, string 場名, int レース番号, string raceId, List<Danwa> recs)
        {
            int n = 0;
            using var conn = new SqlConnection(connStr);
            conn.Open();
            DateTime 取得日時 = DateTime.Now;
            foreach (var r in recs)
            {
                if (r.馬番 <= 0) continue;
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
INSERT INTO 厩舎の話(開催日,開催場所,レース番号,raceid,馬番,枠番,馬名,umacd,性齢,騎手,印,調教師,コメント,コメント原文,取得日時,取得元)
VALUES(@日,@場,@R,@rid,@番,@枠,@名,@uc,@性,@騎,@印,@師,@com,@raw,@時,N'keibabook')";
                cmd.Parameters.AddWithValue("@日", 開催日.ToDateTime(TimeOnly.MinValue));
                cmd.Parameters.AddWithValue("@場", 場名);
                cmd.Parameters.AddWithValue("@R", レース番号);
                cmd.Parameters.AddWithValue("@rid", raceId);
                cmd.Parameters.AddWithValue("@番", r.馬番);
                cmd.Parameters.AddWithValue("@枠", r.枠番);
                cmd.Parameters.AddWithValue("@名", (object?)r.馬名 ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@uc", (object?)r.umacd ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@性", (object?)r.性齢 ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@騎", (object?)r.騎手 ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@印", (object?)r.印 ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@師", (object?)r.調教師 ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@com", (object?)r.コメント ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@raw", (object?)r.原文 ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@時", 取得日時);
                try { n += cmd.ExecuteNonQuery(); }
                catch (SqlException ex) when (ex.Number == 2601 || ex.Number == 2627) { /* 同一スナップショット重複は無視 */ }
            }
            return n;
        }

        // ===================== HTTP / 補助 =====================

        /// <summary>curl.exe を Cookieジャー付きで実行し、標準出力をUTF-8で返す(低レベル・ログイン誘発なし)。</summary>
        private static string RunCurl(params string[] args)
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
                psi.ArgumentList.Add("-b"); psi.ArgumentList.Add(CookieJar); // Cookie送信
                psi.ArgumentList.Add("-c"); psi.ArgumentList.Add(CookieJar); // Cookie保存
                foreach (var a in args) psi.ArgumentList.Add(a);
                using var p = System.Diagnostics.Process.Start(psi)!;
                using var ms = new MemoryStream();
                p.StandardOutput.BaseStream.CopyTo(ms);
                p.WaitForExit();
                return System.Text.Encoding.UTF8.GetString(ms.ToArray());
            }
            catch (Exception ex)
            {
                Logger.LogError("curl実行に失敗しました", ex);
                return string.Empty;
            }
        }

        /// <summary>ページ取得(必要なら先に会員ログイン)。失敗時は空文字列。</summary>
        private static string GetHtml(string url)
        {
            EnsureLogin();
            return RunCurl(url);
        }

        /// <summary>
        /// secrets.local.json(KeibabookUser/KeibabookPass)があれば競馬ブックweb会員ログインを1回だけ実行します。
        /// ログインすると各レース全頭の厩舎の話/調教が取得できます。資格情報が無い/失敗した場合は非ログイン(一部頭数)で継続。
        /// </summary>
        private static void EnsureLogin()
        {
            if (_loginAttempted) return;
            _loginAttempted = true;
            if (_skipLogin) { Logger.Log("--no-login 指定: 非ログイン(各レース一部のみ)で取得します。"); return; }

            var user = Secrets.KeibabookUser;
            var pass = Secrets.KeibabookPass;
            if (string.IsNullOrWhiteSpace(user) || string.IsNullOrWhiteSpace(pass))
            {
                Logger.Log("競馬ブックの資格情報(secrets.local.json: KeibabookUser/KeibabookPass)が無いため、非ログイン(各レース一部のみ)で取得します。");
                return;
            }

            try { if (File.Exists(CookieJar)) File.Delete(CookieJar); } catch { }

            var loginUrl = $"{Base}/login/login";
            // ① ログインページGET → _token(CSRF)とセッションCookieを取得。
            var page = RunCurl(loginUrl);
            var token = Regex.Match(page, @"name=""_token""[^>]*value=""(?<v>[^""]+)""");
            if (!token.Success)
            {
                Logger.Log("ログインページの_token(CSRF)を取得できませんでした。非ログインで継続します。");
                return;
            }
            // ② 資格情報をPOST(リダイレクト追従)。
            var resp = RunCurl(
                "-L",
                "--data-urlencode", $"_token={token.Groups["v"].Value}",
                "--data-urlencode", $"login_id={user}",
                "--data-urlencode", $"pswd={pass}",
                "--data-urlencode", "service=keibabook",
                "--data-urlencode", "referer=",
                "--data-urlencode", "autologin=1",
                "--data-urlencode", "submitbutton=ログインする",
                loginUrl);

            // ③ 成否判定: 成功すると遷移先ページにはログインフォーム(pswd欄)が無い。失敗時はログイン画面が再表示される。
            _loggedIn = !Regex.IsMatch(resp, @"name=""pswd""");
            Logger.Log(_loggedIn
                ? "競馬ブックにログインしました(全頭取得)。"
                : "競馬ブックのログインに失敗しました(KeibabookUser/Passを確認)。非ログイン(各レース一部のみ)で継続します。");
        }

        private static string StripTags(string html)
        {
            var text = Regex.Replace(html, @"<[^>]+>", " ");
            text = WebUtility.HtmlDecode(text);
            return Regex.Replace(text, @"\s+", " ").Trim();
        }

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

        private static bool HasFlag(string[] args, string name) => Array.IndexOf(args, name) >= 0;

        // ============================ 完全データ(出走履歴) /db/uma/{umacd}/kanzen ============================
        // 地方競馬(20260607)のfetch-umaをJRA(中央)へ移植。ページ構造は中央/地方共通。SetRegionは中央固定のため不要。
        /// <summary>完全データ1走分。</summary>
        private sealed class Seiseki
        {
            public DateOnly 開催日; public string? 競走key; public string? 中央地方;
            public string 場名 = ""; public int レース番号; public string? レース名;
            public string? コース種別; public string? 回り; public int? 距離; public string? 馬場; public string? 天候;
            public int? 頭数; public int? ゲート番; public int? 馬体重; public string? 本紙印;
            public decimal? 単勝オッズ; public int? 人気; public decimal? 前半3F; public decimal? 後半3F; public bool 後半3F最速;
            public string? ペース; public decimal? レース上り4F; public decimal? レース上り3F;
            public int? 通過1角; public int? 通過2角; public int? 通過3角; public int? 通過4角; public bool 不利; public string? 四角内外;
            public int? 着順; public string? 走破タイム; public string? 着差; public string? 寸評; public string? 追切; public string? ラップタイム;
            public string? 騎手; public decimal? 負担重量;
        }

        /// <summary>fetch-uma: 馬の完全データ(出走履歴)を取得。--umacd 単体 / --date その日の中央出走馬全頭 / --sleep / --no-login。</summary>
        public static void 完全データ取得(string[] args)
        {
            Logger.Log("競馬ブック完全データ取得 IN");
            try
            {
                string connStr = GetConnStr();
                if (string.IsNullOrWhiteSpace(connStr)) { Logger.Log("接続文字列が取得できません。"); return; }
                _skipLogin = HasFlag(args, "--no-login");
                int sleepMs = int.TryParse(GetOpt(args, "--sleep"), out var sm) ? sm : 既定待機ミリ秒;

                var umacds = new List<string>();
                var nameByCd = new Dictionary<string, string>();
                var single = GetOpt(args, "--umacd");
                if (!string.IsNullOrWhiteSpace(single)) { umacds.Add(single!.Trim()); }
                else
                {
                    DateOnly 対象日 = DateOnly.TryParse(GetOpt(args, "--date"), out var d) ? d : DateOnly.FromDateTime(DateTime.Today);
                    LoadRunnerUmacds(connStr, 対象日, umacds, nameByCd); // 既取得の厩舎の話/調教/能力指数から
                    if (umacds.Count == 0) DiscoverUmacdsFromSyutuba(対象日, umacds, nameByCd); // 無ければ出馬表から
                    Logger.Log($"対象 {対象日:yyyy-MM-dd}: 出走馬 {umacds.Distinct().Count()}頭");
                }
                if (umacds.Count == 0) { Logger.Log("対象馬が見つかりません。"); return; }

                int totalRaces = 0, horses = 0;
                foreach (var cd in umacds.Distinct())
                {
                    var html = GetHtml($"{Base}/db/uma/{cd}/kanzen"); // 302先に直接アクセス
                    // ★同ページの馬プロフィール表から血統(父/母/母父/生産牧場等)を解析し馬情報へupsert(馬柱の父母表示用・追加HTTPなし)。
                    SaveUmaInfo(cd, nameByCd.TryGetValue(cd, out var nmHint) ? nmHint : null, html);
                    var recs = ParseKanzen(html);
                    if (recs.Count > 0)
                    {
                        var nm = nameByCd.TryGetValue(cd, out var n) ? n : ParseUmaName(html);
                        totalRaces += SaveSeiseki(connStr, cd, nm, recs); horses++;
                        Logger.Log($"  保存 {recs.Count}走 (umacd={cd} {nm})");
                    }
                    else Logger.Log($"  履歴なし: umacd={cd}");
                    Thread.Sleep(sleepMs);
                }
                Logger.Log($"競馬ブック完全データ取得 完了: {horses}頭 / {totalRaces}走 / {umacds.Distinct().Count()}対象");
            }
            catch (Exception ex) { Logger.LogError("完全データ取得でエラー", ex); }
            finally { Logger.Log("競馬ブック完全データ取得 OUT"); }
        }

        /// <summary>既取得の厩舎の話/調教/能力指数から対象日の出走馬umacd(+馬名)を読む。</summary>
        private static void LoadRunnerUmacds(string connStr, DateOnly date, List<string> cds, Dictionary<string, string> names)
        {
            try
            {
                using var conn = new SqlConnection(connStr); conn.Open();
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"SELECT umacd, MAX(馬名) nm FROM (
                    SELECT umacd,馬名 FROM 厩舎の話 WHERE 開催日=@d AND umacd IS NOT NULL
                    UNION ALL SELECT umacd,馬名 FROM 調教 WHERE 開催日=@d AND umacd IS NOT NULL
                    UNION ALL SELECT umacd,馬名 FROM 競馬ブック能力指数 WHERE 開催日=@d AND umacd IS NOT NULL) z GROUP BY umacd";
                cmd.Parameters.AddWithValue("@d", date.ToDateTime(TimeOnly.MinValue));
                using var rd = cmd.ExecuteReader();
                while (rd.Read()) { var cd = rd[0]?.ToString(); if (!string.IsNullOrEmpty(cd)) { cds.Add(cd!); var nm = rd[1]?.ToString(); if (!string.IsNullOrEmpty(nm)) names[cd!] = nm!; } }
            }
            catch (Exception ex) { Logger.LogError("出走馬umacd読込(DB)に失敗", ex); }
        }

        /// <summary>対象日の中央出馬表(syutuba)から出走馬umacd(+馬名)を抽出。</summary>
        private static void DiscoverUmacdsFromSyutuba(DateOnly date, List<string> cds, Dictionary<string, string> names)
        {
            var seen = new HashSet<string>();
            foreach (var rid in DiscoverRaceIds(date))
            {
                var html = GetHtml($"{Base}/cyuou/syutuba/{rid}");
                foreach (Match m in Regex.Matches(html, @"/db/uma/(?<cd>\d+)""[^>]*>(?<nm>[^<]+)</a>"))
                {
                    var cd = m.Groups["cd"].Value;
                    if (seen.Add(cd)) { cds.Add(cd); names[cd] = WebUtility.HtmlDecode(m.Groups["nm"].Value).Trim(); }
                }
                Thread.Sleep(既定待機ミリ秒);
            }
        }

        /// <summary>kanzenページの各レースブロック(tr.oikiri)を解析。</summary>
        private static List<Seiseki> ParseKanzen(string html)
        {
            var list = new List<Seiseki>();
            // 1レース=oikiri行から次のoikiri(またはtbody/table終端)まで(racemeiがrowspanで複数<tr>に跨るため範囲で捕捉)。
            foreach (Match blk in Regex.Matches(html, @"<tr class=""oikiri"">(?<blk>.*?)(?=<tr class=""oikiri""|</tbody>|</table>)", RegexOptions.Singleline))
            {
                try
                {
                    var body = blk.Groups["blk"].Value; var oik = body;
                    var rm = Regex.Match(body, @"<td[^>]*class=""racemei[^""]*""[^>]*>(?<v>.*?)</td>", RegexOptions.Singleline);
                    if (!rm.Success) continue;
                    var rmHtml = rm.Groups["v"].Value; var rmText = StripTags(rmHtml);
                    var r = new Seiseki();
                    var link = Regex.Match(rmHtml, @"/(?<rt>chihou|cyuou)/seiseki/(?<rid>\d+)");
                    if (link.Success) { r.競走key = link.Groups["rid"].Value; r.中央地方 = link.Groups["rt"].Value == "chihou" ? "地方" : "中央"; }
                    var dt = Regex.Match(rmText, @"(?<y>\d{4})年(?<mo>\d{1,2})月(?<d>\d{1,2})日");
                    if (!dt.Success) continue;
                    r.開催日 = new DateOnly(int.Parse(dt.Groups["y"].Value), int.Parse(dt.Groups["mo"].Value), int.Parse(dt.Groups["d"].Value));
                    var wb = Regex.Match(rmText, @"日[(（](?<w>[^・)）]+)[・·](?<b>[^)）]+)[)）]");
                    if (wb.Success) { r.天候 = wb.Groups["w"].Value.Trim(); r.馬場 = wb.Groups["b"].Value.Trim(); }
                    // JRA(中央)形式: "3回中山2日目4R(芝Ａ・右内 1800m)"。場=回〜日目間、コース直後にトラック記号(Ａ等)+回り(右内/左外等)。
                    var cond = Regex.Match(rmText, @"\d+回(?<ba>[^\d回]+?)\d+日目(?<r>\d{1,2})R[(（](?<kind>ダート|ダ|芝|障[^・)）]*)[^0-9]*?(?<dist>\d{3,4})m");
                    if (cond.Success)
                    {
                        r.場名 = cond.Groups["ba"].Value.Trim(); r.レース番号 = int.Parse(cond.Groups["r"].Value);
                        r.コース種別 = cond.Groups["kind"].Value.Trim();
                        r.距離 = int.Parse(cond.Groups["dist"].Value);
                        var tn = Regex.Match(rmText, @"[(（](?:ダート|ダ|芝|障[^・)）]*)[^・)）]*[・·](?<turn>右内|左内|右外|左外|右|左|直)");
                        if (tn.Success) r.回り = tn.Groups["turn"].Value;
                    }
                    else
                    {
                        // 地方(NAR)など旧形式フォールバック: "船橋11R(ダ・右 1600m)"。
                        var c2 = Regex.Match(rmText, @"(?<ba>[^\d\s（(]+?)(?<r>\d{1,2})R[(（](?<kind>ダート|ダ|芝|障[^・)）]*)[・·]?(?<turn>[左右直内外]+)?\s*(?<dist>\d{3,4})m");
                        if (c2.Success)
                        {
                            r.場名 = c2.Groups["ba"].Value.Trim(); r.レース番号 = int.Parse(c2.Groups["r"].Value);
                            r.コース種別 = c2.Groups["kind"].Value.Trim(); if (c2.Groups["turn"].Success) r.回り = c2.Groups["turn"].Value;
                            r.距離 = int.Parse(c2.Groups["dist"].Value);
                        }
                    }
                    var nameM = Regex.Match(rmHtml, @"k_dataracename.*?>\s*(?:<a[^>]*>)?\s*(?<nm>[^<]+?)\s*(?:</a>)?\s*<", RegexOptions.Singleline);
                    if (nameM.Success) r.レース名 = WebUtility.HtmlDecode(nameM.Groups["nm"].Value).Trim();
                    var ac = Regex.Match(body, @"<td[^>]*class=""active""[^>]*>(?<v>.*?)</td>", RegexOptions.Singleline);
                    if (ac.Success) { var at = StripTags(ac.Groups["v"].Value); var am = Regex.Match(at, @"(?<t>[\d.:]+)\s*(?:[(（](?<m>[^)）]+)[)）])?"); if (am.Success) { r.走破タイム = am.Groups["t"].Value; if (am.Groups["m"].Success) r.着差 = am.Groups["m"].Value; } }
                    var dc = Regex.Match(body, @"<td[^>]*class=""detail""[^>]*>(?<v>.*?)</td>", RegexOptions.Singleline);
                    if (dc.Success) ParseDetail(StripTags(dc.Groups["v"].Value), r);
                    var sun = Regex.Match(oik, @"<td[^>]*class=""sunpyo""[^>]*>(?<v>.*?)</td>", RegexOptions.Singleline);
                    if (sun.Success) { var st = StripTags(Regex.Match(sun.Groups["v"].Value, @"<dt>(?<x>.*?)</dt>", RegexOptions.Singleline) is var d2 && d2.Success ? d2.Groups["x"].Value : sun.Groups["v"].Value); r.寸評 = Trunc(NullIfEmpty(st), 80); }
                    var oikp = Regex.Match(oik, @"kanzendata_click[^>]*>\s*<p>(?<v>.*?)</p>", RegexOptions.Singleline);
                    if (oikp.Success) r.追切 = Trunc(NullIfEmpty(StripTags(oikp.Groups["v"].Value)), 120);
                    var lap = Regex.Match(body, @"<td[^>]*class=""laptime""[^>]*>(?<v>.*?)</td>", RegexOptions.Singleline);
                    if (lap.Success) r.ラップタイム = Trunc(NullIfEmpty(StripTags(lap.Groups["v"].Value)), 120); // 全ハロンのラップ "12.9-11.6-..."
                    list.Add(r);
                }
                catch { }
            }
            return list;
        }

        /// <summary>detailセル(頭数/ゲート/体重/印/オッズ/前後半3F/ペース/上り/通過/着順)を解析。</summary>
        private static void ParseDetail(string s, Seiseki r)
        {
            var m = Regex.Match(s, @"(\d+)頭"); if (m.Success) r.頭数 = int.Parse(m.Groups[1].Value);
            m = Regex.Match(s, @"頭\s*(\d+)\s*ｹﾞｰﾄ"); if (m.Success) r.ゲート番 = int.Parse(m.Groups[1].Value);
            m = Regex.Match(s, @"(\d{3,4})K"); if (m.Success) r.馬体重 = int.Parse(m.Groups[1].Value);
            m = Regex.Match(s, @"K\s*(?<p>[◎○▲△注☆◇×消])"); if (m.Success) r.本紙印 = m.Groups["p"].Value;
            m = Regex.Match(s, @"([\d.]+)\s*[(（](\d+)人気[)）]"); if (m.Success) { if (decimal.TryParse(m.Groups[1].Value, out var od)) r.単勝オッズ = od; r.人気 = int.Parse(m.Groups[2].Value); }
            m = Regex.Match(s, @"前\s*([\d.]+)\s*-\s*後\s*([\d.]+)"); if (m.Success) { if (decimal.TryParse(m.Groups[1].Value, out var f)) r.前半3F = f; if (decimal.TryParse(m.Groups[2].Value, out var b)) r.後半3F = b; }
            m = Regex.Match(s, @"([HMS])ペース"); if (m.Success) r.ペース = m.Groups[1].Value;
            m = Regex.Match(s, @"上り\s*([\d.]+)\s*-\s*([\d.]+)"); if (m.Success) { if (decimal.TryParse(m.Groups[1].Value, out var u4)) r.レース上り4F = u4; if (decimal.TryParse(m.Groups[2].Value, out var u3)) r.レース上り3F = u3; }
            m = Regex.Match(s, @"(\d+)着"); if (m.Success) r.着順 = int.Parse(m.Groups[1].Value);
            // 通過順位 + 4角内外: 「上りX-Y」の後〜「N着」の前
            var seg = Regex.Match(s, @"上り\s*[\d.]+\s*-\s*[\d.]+\s*(?<rest>.*?)\s*\d+着");
            if (seg.Success)
            {
                var rest = seg.Groups["rest"].Value;
                var io = Regex.Match(rest, @"(内|外|中)"); if (io.Success) r.四角内外 = io.Groups[1].Value;
                var posPart = Regex.Replace(rest, @"(内|外|中).*$", "");
                var nums = new List<int>();
                foreach (Match t in Regex.Matches(posPart, @"[①-⑳]|\d+")) { var (n, unf) = CircledToInt(t.Value); if (n > 0) { nums.Add(n); if (unf) r.不利 = true; } }
                int c = nums.Count;
                if (c >= 1) r.通過4角 = nums[c - 1];
                if (c >= 2) r.通過3角 = nums[c - 2];
                if (c >= 3) r.通過2角 = nums[c - 3];
                if (c >= 4) r.通過1角 = nums[c - 4];
            }
        }

        /// <summary>丸数字(①〜⑳)→(数値,不利true)、半角数字→(数値,false)。</summary>
        private static (int, bool) CircledToInt(string tok)
        {
            if (string.IsNullOrEmpty(tok)) return (0, false);
            char ch = tok[0];
            if (ch >= '①' && ch <= '⑳') return (ch - '①' + 1, true);
            return int.TryParse(tok, out var n) ? (n, false) : (0, false);
        }

        /// <summary>kanzenページから馬名を抽出(取得できなければnull)。</summary>
        private static string? ParseUmaName(string html)
        {
            // <title>馬名(生年) - 英名 | 完全データ | 競馬ブック</title>
            var m = Regex.Match(html, @"<title>\s*(?<n>[^(（|<]+)");
            if (m.Success) { var nm = WebUtility.HtmlDecode(m.Groups["n"].Value).Trim(); if (!string.IsNullOrEmpty(nm)) return nm; }
            return null;
        }

        /// <summary>
        /// kanzenページの馬プロフィール表(&lt;table class="default uma"&gt;)から血統等を解析し、馬情報へupsertします。
        /// 馬柱の「父 / 母(母父) / 生産牧場」表示用。JRAには馬情報を埋める取込が無かったため(旧馬情報.csは地方keiba.go.jp向け)、
        /// 既にfetch-umaで取得済のkanzen HTMLを再利用して追加HTTPなしで補完します。血統が取れない場合はスキップ。
        /// 既存判定・重複回避は馬情報.csと同じ(馬名+調教師)。生年は&lt;title&gt;の(YYYY)からYYYY-01-01とする(ユニーク制約 馬名×生年月日×父 のため)。
        /// </summary>
        private static void SaveUmaInfo(string umacd, string? nameHint, string html)
        {
            try
            {
                if (string.IsNullOrEmpty(html)) return;
                // 血統を含むプロフィール表(母父かつ生産牧場を含む<table>)を特定。
                string body = html;
                foreach (Match tm in Regex.Matches(html, @"<table[^>]*>(?<b>.*?)</table>", RegexOptions.Singleline))
                {
                    var b = tm.Groups["b"].Value;
                    if (b.Contains("母父") && b.Contains("生産牧場")) { body = b; break; }
                }
                // <th>ラベル</th><td>値</td> の最初のtd。値は最初の<a>テキスト優先、無ければタグ除去。
                string Cell(string label)
                {
                    var m = Regex.Match(body, @"<th[^>]*>\s*" + Regex.Escape(label) + @"\s*</th>\s*<td[^>]*>(?<v>.*?)</td>", RegexOptions.Singleline);
                    if (!m.Success) return string.Empty;
                    var v = m.Groups["v"].Value;
                    var a = Regex.Match(v, @"<a[^>]*>(?<t>.*?)</a>", RegexOptions.Singleline);
                    return StripTags(a.Success ? a.Groups["t"].Value : v);
                }
                string 父 = Cell("父"), 母 = Cell("母"), 母父 = Cell("母父");
                string 生産牧場 = Cell("生産牧場"), 厩舎 = Cell("厩舎"), 馬主 = Cell("馬主");
                if (父.Length == 0 && 母.Length == 0 && 生産牧場.Length == 0) return; // 血統が取れない=スキップ
                // 産地(生産牧場tdの(地名))・所属(厩舎tdの(美浦/栗東))
                string 産地 = "", 所属 = "";
                var seisanM = Regex.Match(body, @"<th[^>]*>\s*生産牧場\s*</th>\s*<td[^>]*>(?<v>.*?)</td>", RegexOptions.Singleline);
                if (seisanM.Success) { var pm = Regex.Match(StripTags(seisanM.Groups["v"].Value), @"[（(]\s*(?<c>[^)）]+?)\s*[)）]"); if (pm.Success) 産地 = pm.Groups["c"].Value; }
                var kyusyaM = Regex.Match(body, @"<th[^>]*>\s*厩舎\s*</th>\s*<td[^>]*>(?<v>.*?)</td>", RegexOptions.Singleline);
                if (kyusyaM.Success) { var am = Regex.Match(StripTags(kyusyaM.Groups["v"].Value), @"[（(]\s*(?<c>[^)）]+?)\s*[)）]"); if (am.Success) 所属 = am.Groups["c"].Value; }
                // 生年: <title>馬名(YYYY) - ... の(YYYY)。
                int 生年 = 0;
                var tM = Regex.Match(html, @"<title>(?<t>.*?)</title>", RegexOptions.Singleline);
                if (tM.Success) { var ym = Regex.Match(tM.Groups["t"].Value, @"[（(](?<y>\d{4})[)）]"); if (ym.Success) int.TryParse(ym.Groups["y"].Value, out 生年); }
                // 馬名: 出走馬テーブル由来(コンピ/レース情報と一致)を優先、無ければページから。
                string 馬名 = (nameHint ?? "").Trim();
                if (馬名.Length == 0) 馬名 = ParseUmaName(html) ?? "";
                if (馬名.Length == 0) return;

                var model = new 馬情報モデル
                {
                    馬名 = Trunc(馬名, 9)!,
                    生年月日 = 生年 > 1900 ? new DateOnly(生年, 1, 1) : new DateOnly(1900, 1, 1),
                    調教師 = Trunc(厩舎, 10) ?? string.Empty,
                    所属 = Trunc(所属, 6) ?? string.Empty,
                    馬主 = Trunc(馬主, 32) ?? string.Empty,
                    生産牧場 = Trunc(生産牧場, 32) ?? string.Empty,
                    産地 = Trunc(産地, 16) ?? string.Empty,
                    父 = Trunc(父, 18) ?? string.Empty,
                    母 = Trunc(母, 18) ?? string.Empty,
                    母父 = Trunc(母父, 18) ?? string.Empty,
                    更新日 = DateOnly.FromDateTime(DateTime.Today),
                };
                using var ctx = new DBContext();
                var existing = ctx.馬情報.FirstOrDefault(h => h.馬名 == model.馬名 && h.調教師 == model.調教師);
                if (existing != null)
                {
                    model.Id = existing.Id;
                    ctx.Entry(existing).CurrentValues.SetValues(model);
                    if (ctx.ChangeTracker.HasChanges()) ctx.SaveChanges();
                }
                else
                {
                    ctx.馬情報.Add(model);
                    ctx.SaveChanges();
                }
            }
            catch (Exception ex) { Logger.LogError($"馬情報upsert失敗 umacd={umacd}", ex); }
        }

        private static int SaveSeiseki(string connStr, string umacd, string? 馬名, List<Seiseki> recs)
        {
            int n = 0; using var conn = new SqlConnection(connStr); conn.Open(); DateTime 取得日時 = DateTime.Now;
            foreach (var r in recs)
            {
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
INSERT INTO 競走成績(umacd,馬名,開催日,競走key,中央地方,場名,レース番号,レース名,コース種別,回り,距離,馬場,天候,頭数,ゲート番,馬体重,本紙印,単勝オッズ,人気,前半3F,後半3F,後半3F最速,ペース,レース上り4F,レース上り3F,通過1角,通過2角,通過3角,通過4角,不利,四角内外,着順,走破タイム,着差,寸評,追切,ラップタイム,前半100m時計,取得日時,取得元)
VALUES(@uc,@nm,@日,@key,@cl,@場,@R,@rn,@kind,@turn,@dist,@baba,@ten,@tou,@gate,@bw,@mark,@odds,@nin,@f3,@b3,@fast,@pace,@u4,@u3,@c1,@c2,@c3,@c4,@huri,@io,@cyaku,@time,@sa,@sun,@oi,@lap,@f100,@時,N'keibabook')";
                void P(string k, object? v) => cmd.Parameters.AddWithValue(k, v ?? DBNull.Value);
                P("@uc", umacd); P("@nm", 馬名); P("@日", r.開催日.ToDateTime(TimeOnly.MinValue)); P("@key", r.競走key); P("@cl", r.中央地方);
                P("@場", string.IsNullOrEmpty(r.場名) ? "?" : r.場名); P("@R", r.レース番号); P("@rn", r.レース名); P("@kind", r.コース種別); P("@turn", r.回り); P("@dist", r.距離);
                P("@baba", r.馬場); P("@ten", r.天候); P("@tou", r.頭数); P("@gate", r.ゲート番); P("@bw", r.馬体重); P("@mark", r.本紙印);
                P("@odds", r.単勝オッズ); P("@nin", r.人気); P("@f3", r.前半3F); P("@b3", r.後半3F); P("@fast", r.後半3F最速 ? 1 : 0);
                P("@pace", r.ペース); P("@u4", r.レース上り4F); P("@u3", r.レース上り3F);
                P("@c1", r.通過1角); P("@c2", r.通過2角); P("@c3", r.通過3角); P("@c4", r.通過4角); P("@huri", r.不利 ? 1 : 0); P("@io", r.四角内外);
                P("@cyaku", r.着順); P("@time", r.走破タイム); P("@sa", r.着差); P("@sun", r.寸評); P("@oi", r.追切); P("@lap", r.ラップタイム);
                P("@f100", Calc前半100m(r.距離, r.前半3F, r.後半3F, r.走破タイム)); P("@時", 取得日時);
                try { n += cmd.ExecuteNonQuery(); } catch (SqlException ex) when (ex.Number == 2601 || ex.Number == 2627) { }
            }
            return n;
        }

        private static decimal? TimeToSec(string? t)
        {
            if (string.IsNullOrWhiteSpace(t)) return null;
            var parts = t.Trim().Split('.');
            try
            {
                var ci = System.Globalization.CultureInfo.InvariantCulture;
                if (parts.Length == 3) return int.Parse(parts[0]) * 60 + int.Parse(parts[1]) + decimal.Parse("0." + parts[2], ci);
                if (parts.Length == 2) return int.Parse(parts[0]) + decimal.Parse("0." + parts[1], ci);
            }
            catch { }
            return null;
        }

        /// <summary>前半3Fが無いレース用の代替ペース: 前半100mあたり秒 = (走破秒 - 後半3F) / (距離-600) * 100。</summary>
        private static decimal? Calc前半100m(int? 距離, decimal? 前半3F, decimal? 後半3F, string? 走破タイム)
        {
            if (前半3F != null) return null;
            if (後半3F == null || 距離 == null || 距離 <= 600) return null;
            var sec = TimeToSec(走破タイム); if (sec == null) return null;
            var front = sec.Value - 後半3F.Value; var dist = 距離.Value - 600;
            if (front <= 0) return null;
            return Math.Round(front / dist * 100m, 2);
        }
    }
}
