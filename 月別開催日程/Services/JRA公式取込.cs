// 役割: JRA公式サイト(www.jra.go.jp / /JRADB POST=cname駆動・Shift_JIS)から競走結果・払戻金を取得して保存します。
// netkeiba(db.netkeiba)が当日結果を翌日まで反映しないラグを解消するため、当日/直近の即時取得に使う追加経路です。
// 過去数年の一括backfillは引き続き netkeiba(JRA取込.FetchRange)を使用(公式は約2ヶ月のみ保持)。
// 経路(全てHTTP POST=Selenium不要): GET /keiba/(成績一覧cname取得) → POST 成績一覧(開催srl列挙)
//   → POST 開催srl(その開催の全レース結果ページcname=ses取得) → POST ses(1ページに全12R結果+全8券種払戻)。
// 保存・着差計算・場コードは JRA取込(同一partialクラス)の既存実装を再利用します。
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using 中央競馬.共通.Libraly;
using 中央競馬.共通.Models;

namespace 中央競馬.Services
{
    public static partial class JRA取込
    {
        private const string 公式Keiba = "https://www.jra.go.jp/keiba/";
        private const string 公式AccessS = "https://www.jra.go.jp/JRADB/accessS.html";
        // 公式の馬券表記(dt)。netkeibaは「三連複/三連単」、公式は「3連複/3連単」なので保存時に正規化する。
        private static readonly string[] 公式馬券 = { "単勝", "複勝", "枠連", "馬連", "ワイド", "馬単", "3連複", "3連単" };

        private static Encoding 公式エンコーディング()
        {
            Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
            return Encoding.GetEncoding("shift_jis");
        }

        /// <summary>
        /// JRA公式から指定日付範囲の競走結果・払戻金を取得・保存します。各開催は1ページ(全レース+払戻)で完結。
        /// </summary>
        public static void FetchOfficialRange(DateOnly from, DateOnly to, int delayMs = 1500)
        {
            if (from > to) { Logger.Log($"fetch-jra-officialの引数が不正です(開始>終了): {from:yyyy-MM-dd} > {to:yyyy-MM-dd}"); return; }
            Logger.Log($"fetch-jra-official開始: {from:yyyy-MM-dd} ～ {to:yyyy-MM-dd}");
            var enc = 公式エンコーディング();

            // 1) 成績一覧の起点cname(トークン付)を GET /keiba/ から取得(トークンは随時変わるため動的取得)。
            var keiba = 公式GET(公式Keiba, enc);
            var listMatch = Regex.Match(keiba ?? string.Empty, @"doAction\('/JRADB/accessS\.html',\s*'(pw01sli00/[0-9A-Za-z]+)'\)");
            var listCname = listMatch.Success ? listMatch.Groups[1].Value : "pw01sli00";

            // 2) 成績一覧 → 開催srl cname列挙(cnameに 場コード/開催初日/開催日 を内包)。
            var listHtml = 公式POST(listCname, enc);
            if (string.IsNullOrEmpty(listHtml)) { Logger.Log("JRA公式の成績一覧を取得できません。"); return; }
            var srl = Regex.Matches(listHtml, @"doAction\('/JRADB/accessS\.html',\s*'(pw01srl\d{2}(\d{2})\d{8}(\d{8})/[0-9A-Za-z]+)'\)");

            // (場コード,開催日)でユニーク化。
            var 開催一覧 = new Dictionary<(string 場c, DateOnly d), string>();
            foreach (Match m in srl)
            {
                var cname = m.Groups[1].Value; var 場c = m.Groups[2].Value;
                if (!DateOnly.TryParseExact(m.Groups[3].Value, "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d)) continue;
                if (d < from || d > to) continue;
                開催一覧[(場c, d)] = cname;
            }
            if (開催一覧.Count == 0)
            {
                Logger.Log($"対象範囲にJRA公式の開催が見つかりません({from:yyyy-MM-dd}〜{to:yyyy-MM-dd})。公式は約2ヶ月のみ保持のため、古い日付は fetch-jra-range(netkeiba)を使用してください。");
                return;
            }

            var 取得開催 = 0;
            foreach (var kv in 開催一覧.OrderBy(k => k.Key.d).ThenBy(k => k.Key.場c))
            {
                var (場c, d) = kv.Key;
                if (!場コード.TryGetValue(場c, out var 場名)) continue;
                try
                {
                    // 3) 開催srl → その開催の全レース結果ページ cname(ses, 場+開催日が一致するもの)。
                    var srlHtml = 公式POST(kv.Value, enc);
                    var sesPattern = $@"doAction\('/JRADB/accessS\.html',\s*'(pw01ses\d{{2}}{場c}\d{{8}}{d:yyyyMMdd}/[0-9A-Za-z]+)'\)";
                    var ses = Regex.Match(srlHtml ?? string.Empty, sesPattern);
                    if (!ses.Success) { Logger.Log($"{d:yyyy-MM-dd} {場名}: 結果ページcname(ses)が見つかりません。"); continue; }

                    // 4) 結果ページ(1ページに全レース+払戻) → 解析 → 保存。
                    var resHtml = 公式POST(ses.Groups[1].Value, enc);
                    if (string.IsNullOrEmpty(resHtml)) { Logger.Log($"{d:yyyy-MM-dd} {場名}: 結果ページを取得できません。"); continue; }

                    var 解析 = 公式結果解析(resHtml, d, 場名);
                    if (解析.競走結果.Count == 0) { Logger.Log($"{d:yyyy-MM-dd} {場名}: 結果を解析できません(未確定/未掲載の可能性)。"); continue; }

                    Store(解析);
                    取得開催++;
                    Logger.Log($"保存完了(公式): {d:yyyy-MM-dd} {場名} {解析.競走結果.Select(r => r.レース番号).Distinct().Count()}R (出走{解析.競走結果.Count}・払戻{解析.払戻金.Count})");
                }
                catch (Exception ex) { Logger.LogError($"fetch-jra-officialエラー: {d:yyyy-MM-dd} {場名}", ex); }
                Thread.Sleep(delayMs);
            }
            Logger.Log($"fetch-jra-official終了: 取得 {取得開催}開催");
        }

        // ---- HTTP(Shift_JIS) ----

        private static string? 公式GET(string url, Encoding enc)
        {
            try { using var c = CreateHttpClient(); return enc.GetString(c.GetByteArrayAsync(url).GetAwaiter().GetResult()); }
            catch (Exception ex) { Logger.LogError($"公式GET失敗: {url}", ex); return null; }
        }

        // accessS への cname POST。空応答(ブロック)時は JRA取込のバックオフ表で待ち越す。
        private static string? 公式POST(string cname, Encoding enc)
        {
            for (var attempt = 0; attempt < BackoffSeconds.Length; attempt++)
            {
                try
                {
                    using var c = CreateHttpClient();
                    // cnameはASCII。"/"を保持するため自前エンコードせず生body送信(curl --data と同等)。
                    using var content = new StringContent("cname=" + cname, Encoding.ASCII, "application/x-www-form-urlencoded");
                    var resp = c.PostAsync(公式AccessS, content).GetAwaiter().GetResult();
                    var bytes = resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();
                    if (bytes.Length >= MinValidBytes) return enc.GetString(bytes);
                    Logger.Log($"JRA公式 空応答({bytes.Length}B)。{BackoffSeconds[attempt]}秒待機 {attempt + 1}/{BackoffSeconds.Length} (cname={cname})");
                }
                catch (Exception ex) { Logger.Log($"JRA公式 POST失敗。{BackoffSeconds[attempt]}秒待機 {attempt + 1}/{BackoffSeconds.Length}: {ex.Message}"); }
                Thread.Sleep(BackoffSeconds[attempt] * 1000);
            }
            return null;
        }

        // ---- 解析(Shift_JIS結果ページ。1ページに全レース) ----

        private static 解析結果 公式結果解析(string html, DateOnly date, string 場名)
        {
            var 解析 = new 解析結果();
            // 各レースは <div class="race_result_unit" id="race_result_{N}R"> 〜 次のunit/末尾。
            var units = Regex.Matches(html, @"(?s)<div class=""race_result_unit""\s+id=""race_result_(\d+)R"">(.*?)(?=<div class=""race_result_unit""\s+id=""race_result_\d+R""|\z)");
            foreach (Match u in units)
            {
                if (!int.TryParse(u.Groups[1].Value, out var R)) continue;
                var block = u.Groups[2].Value;
                var rows = 公式結果行(block, date, 場名, R);
                if (rows.Count == 0) continue;
                CalculateGapTimes(rows);
                解析.競走結果.AddRange(rows);
                解析.払戻金.AddRange(公式払戻(block, date, 場名, R));
            }
            return 解析;
        }

        private static List<競走結果モデル> 公式結果行(string block, DateOnly date, string 場名, int R)
        {
            var list = new List<競走結果モデル>();
            var tbl = Regex.Match(block, @"(?s)<table class=""basic[^""]*"">(.*?)</table>");
            if (!tbl.Success) return list;

            foreach (Match tr in Regex.Matches(tbl.Groups[1].Value, @"(?s)<tr[^>]*>(.*?)</tr>"))
            {
                var row = tr.Groups[1].Value;
                if (!Regex.IsMatch(row, @"<td class=""place""")) continue; // ヘッダ(th)行を除外

                string Cell(string cls)
                {
                    var m = Regex.Match(row, $@"(?s)<td class=""{cls}[^""]*"">(.*?)</td>");
                    return m.Success ? 公式タグ除去(m.Groups[1].Value) : string.Empty;
                }

                var 馬番 = int.TryParse(Regex.Match(Cell("num"), @"\d+").Value, out var bn) ? bn : 0;
                if (馬番 == 0) continue;
                var 着順 = int.TryParse(Regex.Match(Cell("place"), @"\d+").Value, out var p) ? p : 0; // 取消/中止/除外は0
                var wakuM = Regex.Match(row, @"waku/(\d+)\.png");
                if (!wakuM.Success) wakuM = Regex.Match(row, @"枠(\d+)");
                var 枠番 = wakuM.Success ? int.Parse(wakuM.Groups[1].Value) : 0;

                var r = new 競走結果モデル
                {
                    開催場所 = 場名,
                    開催日 = date,
                    レース番号 = R,
                    着順 = 着順,
                    枠番 = 枠番,
                    馬番 = 馬番,
                    馬名 = Cell("horse").Trim(),
                    走破時計 = 公式タイム秒(Cell("time")),
                    着差 = 公式全角数字を半角(Cell("margin")).Trim(),
                    上り3F = decimal.TryParse(Cell("f_time"), NumberStyles.Any, CultureInfo.InvariantCulture, out var f) ? f : 0m,
                };

                // コーナー通過順位(<li title="3コーナー通過順位">2</li> 等)。無ければcorner cell内の数字。
                var corners = Regex.Matches(row, @"(?s)<li title=""\dコーナー通過順位"">\s*(\d+)\s*</li>")
                    .Select(m => int.Parse(m.Groups[1].Value)).ToList();
                if (corners.Count == 0)
                    corners = Regex.Matches(Cell("corner"), @"\d+").Select(m => int.Parse(m.Value)).ToList();
                公式コーナー割当(r, corners);

                list.Add(r);
            }
            return list;
        }

        // コーナー通過順は末尾から 四→三→二→一 に割り当てる(最終コーナー=四コーナー)。
        private static void 公式コーナー割当(競走結果モデル r, List<int> corners)
        {
            var n = corners.Count;
            if (n >= 1) r.四コーナー = corners[n - 1];
            if (n >= 2) r.三コーナー = corners[n - 2];
            if (n >= 3) r.二コーナー = corners[n - 3];
            if (n >= 4) r.一コーナー = corners[n - 4];
        }

        private static List<払戻金モデル> 公式払戻(string block, DateOnly date, string 場名, int R)
        {
            var list = new List<払戻金モデル>();
            // <dt>馬券</dt> ... </dl> の中に <div class="num">組番</div> ... <div class="yen">金額</div> の組(複勝/ワイドは複数)。
            foreach (Match dl in Regex.Matches(block, @"(?s)<dt>([^<]+)</dt>(.*?)</dl>"))
            {
                var bet = dl.Groups[1].Value.Trim();
                if (Array.IndexOf(公式馬券, bet) < 0) continue; // 払戻dt以外(ナビ等)を除外
                var 馬券 = bet switch { "3連複" => "三連複", "3連単" => "三連単", _ => bet };
                foreach (Match line in Regex.Matches(dl.Groups[2].Value, @"(?s)<div class=""num"">(.*?)</div>\s*<div class=""yen"">([\d,]+)"))
                {
                    var 組番生 = 公式タグ除去(line.Groups[1].Value).Trim();
                    if (組番生.Length == 0) continue;
                    if (!decimal.TryParse(line.Groups[2].Value.Replace(",", ""), out var 金額) || 金額 <= 0) continue;
                    // 馬単/三連単は順序あり=netkeiba表記に合わせ "a-b" → "a→b"。他(馬連/ワイド/枠連/三連複)はダッシュ保持。
                    var 組番 = (bet == "馬単" || bet == "3連単") ? 組番生.Replace("-", "→") : 組番生;
                    list.Add(new 払戻金モデル { 開催場所 = 場名, 開催日 = date, レース番号 = R, 馬券 = 馬券, 組番 = 組番, 金額 = 金額 });
                }
            }
            return list;
        }

        // ---- 小物 ----

        private static string 公式タグ除去(string html)
        {
            var t = Regex.Replace(html ?? string.Empty, @"(?s)<[^>]+>", " ").Replace("&nbsp;", " ");
            return Regex.Replace(t, @"\s+", " ").Trim();
        }

        private static decimal 公式タイム秒(string text)
        {
            var m = Regex.Match(text ?? string.Empty, @"(\d+):(\d{1,2})\.(\d)");
            if (!m.Success) return 0m;
            return int.Parse(m.Groups[1].Value) * 60
                 + int.Parse(m.Groups[2].Value)
                 + decimal.Parse("0." + m.Groups[3].Value, CultureInfo.InvariantCulture);
        }

        private static string 公式全角数字を半角(string s)
        {
            if (string.IsNullOrEmpty(s)) return s ?? string.Empty;
            var sb = new StringBuilder(s.Length);
            foreach (var ch in s) sb.Append(ch >= '０' && ch <= '９' ? (char)(ch - '０' + '0') : ch);
            return sb.ToString();
        }
    }
}
