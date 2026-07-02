// 役割: netkeiba(db.netkeiba.com)からJRA(中央競馬)の競走結果・レース情報・払戻金・確定オッズを取得して保存します。
// 1レースページ(/race/{race_id}/)に結果・通過順・上がり・確定オッズ・払戻が集約されているため、
// 地方競馬のkeiba.go.jp向けスクレイパ(開催情報→当日メニュー→出馬表/結果/払戻を辿る)とは構造が異なる新規実装です。
// データ源は netkeiba(無料・EUC-JP)。手法核(四角通過順・上がり3F・持ち時計・確定オッズ)を確実に取得します。
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.EntityFrameworkCore;
using 中央競馬.共通.Data;
using 中央競馬.共通.Libraly;
using 中央競馬.共通.Models;

namespace 中央競馬.Services
{
    /// <summary>
    /// netkeibaからJRAの1レース分(結果・レース情報・払戻・確定オッズ)を取得・保存するクラス。
    /// </summary>
    public static partial class JRA取込
    {
        // netkeibaのページはEUC-JP。.NET CoreはEUC-JPを既定で持たないためCodePagesプロバイダを登録してから取得する。
        // ※静的フィールド初期化子は静的コンストラクタ本体より先に走るため、登録もこのメソッド内で行う(初期化順の罠回避)。
        private static readonly Encoding EucJp = CreateEucJp();

        private static Encoding CreateEucJp()
        {
            Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
            return Encoding.GetEncoding("euc-jp");
        }
        private static readonly HttpClient http = CreateHttpClient();

        // race_idの5-6桁目=JRA場コード→場名。地方競馬の場名マスタとは別系統(JRA10場のみ)。
        private static readonly Dictionary<string, string> 場コード = new()
        {
            ["01"] = "札幌", ["02"] = "函館", ["03"] = "福島", ["04"] = "新潟", ["05"] = "東京",
            ["06"] = "中山", ["07"] = "中京", ["08"] = "京都", ["09"] = "阪神", ["10"] = "小倉",
        };

        // 大量取得時にnetkeiba側へ負荷をかけない/レート制限を避けるためのレース間待機(ミリ秒)。
        private const int 既定待機ミリ秒 = 800;
        private const string ListUrlFormat = "https://db.netkeiba.com/race/list/{0}/";
        private const string RaceUrlFormat = "https://db.netkeiba.com/race/{0}/";

        /// <summary>
        /// 指定日付範囲の各開催日について、netkeibaのレース一覧からJRAのrace_idを列挙し、
        /// 未取得のレースだけ結果・レース情報・払戻・確定オッズを取得して保存します。
        /// 取得済みレース(競走結果に走破時計入りの行がある)はスキップするため、中断後に同じ引数で続きから再実行できます。
        /// </summary>
        /// <param name="from">取得開始日(この日を含む)。</param>
        /// <param name="to">取得終了日(この日を含む)。</param>
        /// <param name="delayMs">レース間の待機ミリ秒。</param>
        public static void FetchRange(DateOnly from, DateOnly to, int delayMs = 既定待機ミリ秒, bool force = false)
        {
            if (from > to)
            {
                Logger.Log($"fetch-jra-rangeの引数が不正です(開始>終了): {from:yyyy-MM-dd} > {to:yyyy-MM-dd}");
                return;
            }

            Logger.Log($"fetch-jra-range開始: {from:yyyy-MM-dd} ～ {to:yyyy-MM-dd}");
            var 取得件数 = 0;
            for (var date = from; date <= to; date = date.AddDays(1))
            {
                var races = FetchJraRaceIds(date);
                if (races.Count == 0)
                {
                    Logger.Log($"{date:yyyy-MM-dd}: JRA開催なし(または一覧取得不可)。");
                    continue;
                }

                // force時は既取得でも再取得し、レース情報(枠番/性別/馬齢/調教師/馬主など)を最新のnetkeibaで上書きする。
                var 取得済 = force ? new HashSet<(string, int)>() : GetStoredRaceKeys(date);
                foreach (var race in races)
                {
                    if (取得済.Contains((race.場名, race.レース番号)))
                    {
                        continue;
                    }

                    if (FetchAndStoreRace(race.raceId, date))
                    {
                        取得件数++;
                    }
                    Thread.Sleep(delayMs);
                }

                Logger.Log($"fetch-jra-range進捗: {date:yyyy-MM-dd} まで処理済み(累計取得 {取得件数}レース)");
            }
            Logger.Log($"fetch-jra-range終了: 取得 {取得件数}レース");
        }

        /// <summary>
        /// 1つのrace_idについて、netkeibaのレースページを取得・解析し、4テーブルへupsertします。
        /// </summary>
        /// <param name="raceId">netkeibaのrace_id(12桁: 年4+場2+回2+日2+R2)。</param>
        /// <param name="raceDate">開催日。race_idには暦日が含まれないため呼び出し側(一覧の対象日)から渡します。</param>
        /// <returns>結果行を保存できた場合はtrue。ページ未掲載や解析失敗の場合はfalse。</returns>
        public static bool FetchAndStoreRace(string raceId, DateOnly raceDate)
        {
            try
            {
                if (!TryParseRaceId(raceId, out var 場名, out var レース番号))
                {
                    Logger.Log($"race_idがJRA形式でないためスキップします: {raceId}");
                    return false;
                }

                var url = string.Format(RaceUrlFormat, raceId);
                var html = GetHtml(url);
                if (string.IsNullOrEmpty(html))
                {
                    Logger.Log($"レースページを取得できません: {url}");
                    return false;
                }

                var 解析 = Parse(html, raceDate, 場名, レース番号);
                if (解析 == null || 解析.競走結果.Count == 0)
                {
                    Logger.Log($"競走結果を解析できません(未確定/未掲載の可能性): {url}");
                    return false;
                }

                CalculateGapTimes(解析.競走結果);
                Store(解析);
                Logger.Log($"保存完了: {raceDate:yyyy-MM-dd} {場名} {レース番号}R (出走{解析.競走結果.Count}・払戻{解析.払戻金.Count})");
                return true;
            }
            catch (Exception ex)
            {
                Logger.LogError($"FetchAndStoreRaceエラー: race_id={raceId}", ex);
                return false;
            }
        }

        // ---- HTTP ----

        private static HttpClient CreateHttpClient()
        {
            var client = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
            // ボット的UAだと拒否/遅延されるため通常ブラウザのUAを名乗る。
            client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36");
            return client;
        }

        // netkeibaは長時間連続アクセスでIPブロック/レート制限し、空応答(~1バイト)を返す。
        // 短期(5〜120秒)+持続ブロック待ち(5分×複数, 最大~1時間)のバックオフで待ち越す。
        // ブロックは通常一時的なので、最初の空応答で待っている間に解除され、以降は通常速度で進む。
        private static readonly int[] BackoffSeconds = { 5, 15, 30, 60, 120, 300, 300, 300, 300, 300, 300, 300, 300, 300 };
        private const int MinValidBytes = 800; // 正常ページは数KB以上。ブロック時は~1バイト。

        /// <summary>
        /// 指定URLをEUC-JPでデコードして返します。空応答(ブロック)や失敗時は段階的に待機して再試行します。
        /// 一覧/レースページが極端に小さい(MinValidBytes未満)場合はブロックとみなしバックオフします。
        /// 開催の無い日の一覧は通常の大きさで返るため、正常な「開催なし」は誤バックオフしません。
        /// </summary>
        private static string GetHtml(string url)
        {
            for (int attempt = 0; ; attempt++)
            {
                int waitSec;
                try
                {
                    var bytes = http.GetByteArrayAsync(url).GetAwaiter().GetResult();
                    if (bytes.Length >= MinValidBytes)
                    {
                        return EucJp.GetString(bytes);
                    }
                    if (attempt >= BackoffSeconds.Length)
                    {
                        Logger.Log($"netkeiba空応答が継続(ブロック?)。スキップ: {url}");
                        return string.Empty;
                    }
                    waitSec = BackoffSeconds[attempt];
                    Logger.Log($"netkeiba空応答({bytes.Length}B)。{waitSec}秒待機して再試行 {attempt + 1}/{BackoffSeconds.Length}");
                }
                catch (Exception ex)
                {
                    if (attempt >= BackoffSeconds.Length)
                    {
                        Logger.LogError($"HTTP取得に失敗しました(最終): {url}", ex);
                        return string.Empty;
                    }
                    waitSec = BackoffSeconds[attempt];
                    Logger.Log($"netkeiba取得失敗。{waitSec}秒待機して再試行 {attempt + 1}/{BackoffSeconds.Length}: {ex.Message}");
                }
                Thread.Sleep(waitSec * 1000);
            }
        }

        /// <summary>
        /// netkeibaのレース一覧ページから、その開催日のJRA(場コード01-10)のrace_idを列挙します。
        /// 地方競馬(NAR)のrace_idは場コードが10より大きいため自動的に除外されます。
        /// </summary>
        private static List<(string raceId, string 場名, int レース番号)> FetchJraRaceIds(DateOnly date)
        {
            var url = string.Format(ListUrlFormat, date.ToString("yyyyMMdd"));
            var html = GetHtml(url);
            var result = new List<(string, string, int)>();
            if (string.IsNullOrEmpty(html))
            {
                return result;
            }

            var seen = new HashSet<string>();
            foreach (Match m in Regex.Matches(html, @"/race/(?<id>20\d{10})/"))
            {
                var id = m.Groups["id"].Value;
                if (!seen.Add(id))
                {
                    continue;
                }
                if (TryParseRaceId(id, out var 場名, out var レース番号))
                {
                    result.Add((id, 場名, レース番号));
                }
            }
            return result
                .OrderBy(r => r.Item2)
                .ThenBy(r => r.Item3)
                .ToList();
        }

        /// <summary>
        /// race_id(12桁)からJRA場名とレース番号を取り出します。JRA場コード(01-10)以外はfalse。
        /// </summary>
        private static bool TryParseRaceId(string raceId, out string 場名, out int レース番号)
        {
            場名 = string.Empty;
            レース番号 = 0;
            if (string.IsNullOrWhiteSpace(raceId) || raceId.Length != 12 || !raceId.All(char.IsDigit))
            {
                return false;
            }
            if (!場コード.TryGetValue(raceId.Substring(4, 2), out var name))
            {
                return false;
            }
            場名 = name;
            レース番号 = int.Parse(raceId.Substring(10, 2));
            return レース番号 > 0;
        }

        /// <summary>
        /// 指定開催日について、既に競走結果が保存済み(走破時計入りの行がある)のレースキーを取得します。
        /// </summary>
        private static HashSet<(string 場名, int レース番号)> GetStoredRaceKeys(DateOnly date)
        {
            using var context = new DBContext();
            return context.競走結果
                .AsNoTracking()
                .Where(r => r.開催日 == date && r.走破時計 > 0)
                .Select(r => new { r.開催場所, r.レース番号 })
                .Distinct()
                .AsEnumerable()
                .Select(r => (r.開催場所, r.レース番号))
                .ToHashSet();
        }

        // ---- 保存 ----

        private sealed class 解析結果
        {
            public List<競走結果モデル> 競走結果 { get; } = new();
            public List<レース情報モデル> レース情報 { get; } = new();
            public List<払戻金モデル> 払戻金 { get; } = new();
            public List<リアルタイムオッズモデル> オッズ { get; } = new();
        }

        private static void Store(解析結果 解析)
        {
            using var context = new DBContext();

            foreach (var r in 解析.競走結果)
            {
                var existing = context.競走結果.FirstOrDefault(h =>
                    h.開催日 == r.開催日 && h.開催場所 == r.開催場所 && h.レース番号 == r.レース番号 && h.馬名 == r.馬名);
                if (existing != null)
                {
                    existing.着順 = r.着順; existing.枠番 = r.枠番; existing.馬番 = r.馬番;
                    existing.一着馬着差タイム = r.一着馬着差タイム; existing.先着馬着差タイム = r.先着馬着差タイム; existing.後着馬着差タイム = r.後着馬着差タイム;
                    existing.上り3F = r.上り3F; existing.走破時計 = r.走破時計; existing.着差 = r.着差;
                    existing.一コーナー = r.一コーナー; existing.二コーナー = r.二コーナー; existing.三コーナー = r.三コーナー; existing.四コーナー = r.四コーナー;
                }
                else
                {
                    context.競走結果.Add(r);
                }
            }

            foreach (var r in 解析.レース情報)
            {
                var existing = context.レース情報.FirstOrDefault(h =>
                    h.開催日 == r.開催日 && h.開催場所 == r.開催場所 && h.レース番号 == r.レース番号 && h.馬名 == r.馬名);
                if (existing != null)
                {
                    // SetValuesはIdも上書きするが、Idは主キーで変更不可。先に既存Idを写して同値にし、キー変更扱いを避ける。
                    r.Id = existing.Id;
                    context.Entry(existing).CurrentValues.SetValues(r);
                }
                else
                {
                    context.レース情報.Add(r);
                }
            }

            foreach (var p in 解析.払戻金)
            {
                var existing = context.払戻金.FirstOrDefault(h =>
                    h.開催日 == p.開催日 && h.開催場所 == p.開催場所 && h.レース番号 == p.レース番号 && h.馬券 == p.馬券 && h.組番 == p.組番);
                if (existing != null)
                {
                    existing.金額 = p.金額;
                }
                else
                {
                    context.払戻金.Add(p);
                }
            }

            foreach (var o in 解析.オッズ)
            {
                var existing = context.リアルタイムオッズ.FirstOrDefault(h =>
                    h.開催日 == o.開催日 && h.開催場所 == o.開催場所 && h.レース番号 == o.レース番号 && h.馬番 == o.馬番);
                if (existing != null)
                {
                    existing.単勝オッズ = o.単勝オッズ; existing.人気 = o.人気; existing.日時 = o.日時; existing.馬名 = o.馬名;
                }
                else
                {
                    context.リアルタイムオッズ.Add(o);
                }
            }

            context.SaveChanges();
        }

        // ---- 解析 ----

        private static 解析結果? Parse(string html, DateOnly raceDate, string 場名, int レース番号)
        {
            var meta = ParseMeta(html);
            var 発走時刻 = meta.発走時刻.HasValue
                ? raceDate.ToDateTime(meta.発走時刻.Value)
                : raceDate.ToDateTime(new TimeOnly(0, 0));

            var resultTable = Regex.Match(html,
                @"<table class=""race_table_01 nk_tb_common"".*?</table>",
                RegexOptions.Singleline);
            if (!resultTable.Success)
            {
                return null;
            }

            var rows = Regex.Matches(resultTable.Value, @"<tr[^>]*>(?<row>.*?)</tr>", RegexOptions.Singleline)
                .Select(m => m.Groups["row"].Value)
                .ToList();
            if (rows.Count < 2)
            {
                return null;
            }

            // ヘッダ名→列index。列順がページ更新で変わっても名前で引けるようにする。
            var header = SplitCells(rows[0]).Select(c => Compact(GetText(c))).ToList();
            int Col(string name) => header.FindIndex(h => h == name);
            var i着順 = Col("着順");
            var i枠 = Col("枠番");
            var i馬番 = Col("馬番");
            var i馬名 = Col("馬名");
            var i性齢 = Col("性齢");
            var i斤量 = Col("斤量");
            var i騎手 = Col("騎手");
            var iタイム = Col("タイム");
            var i着差 = Col("着差");
            var i通過 = Col("通過");
            var i上り = Col("上り");
            var i単勝 = Col("単勝");
            var i人気 = Col("人気");
            var i馬体重 = Col("馬体重");
            var i調教師 = Col("調教師");
            var i馬主 = Col("馬主");

            if (i馬番 < 0 || i馬名 < 0)
            {
                Logger.Log("競走結果テーブルのヘッダを認識できません(馬番/馬名なし)。");
                return null;
            }

            var 解析 = new 解析結果();
            var 通過リスト = new List<(競走結果モデル Model, string 通過)>();

            foreach (var row in rows.Skip(1))
            {
                var cells = SplitCells(row);
                if (cells.Count <= i馬名)
                {
                    continue;
                }

                string Cell(int idx) => idx >= 0 && idx < cells.Count ? GetText(cells[idx]) : string.Empty;
                string Raw(int idx) => idx >= 0 && idx < cells.Count ? cells[idx] : string.Empty;

                var 馬名 = NameValue(Raw(i馬名));
                if (string.IsNullOrWhiteSpace(馬名))
                {
                    continue;
                }

                var 馬番 = ServiceErrorHandling.ParseInt(Cell(i馬番));
                var (性別, 馬齢) = Parse性齢(Cell(i性齢));
                var (馬体重, 馬体重増減) = Parse馬体重(Cell(i馬体重));
                var 単勝オッズ = double.TryParse(Compact(Cell(i単勝)), NumberStyles.Any, CultureInfo.InvariantCulture, out var od) ? od : 0.0;
                var 人気 = ServiceErrorHandling.ParseInt(Cell(i人気));

                var 結果 = new 競走結果モデル
                {
                    開催日 = raceDate,
                    開催場所 = 場名,
                    レース番号 = レース番号,
                    着順 = ServiceErrorHandling.ParseInt(Cell(i着順)),
                    枠番 = ServiceErrorHandling.ParseInt(Cell(i枠)),
                    馬番 = 馬番,
                    馬名 = Trunc(馬名, 9),
                    走破時計 = ParseRaceTime(Cell(iタイム)),
                    着差 = Trunc(Compact(Cell(i着差)), 16),
                    上り3F = ServiceErrorHandling.ParseDecimal(Cell(i上り)),
                };
                通過リスト.Add((結果, Compact(Cell(i通過))));
                解析.競走結果.Add(結果);

                解析.レース情報.Add(new レース情報モデル
                {
                    開催日 = raceDate,
                    開催場所 = 場名,
                    レース番号 = レース番号,
                    発走時刻 = 発走時刻,
                    コース種別 = meta.コース種別,
                    周回方向 = meta.周回方向,
                    距離 = meta.距離,
                    天候 = meta.天候,
                    馬場 = meta.馬場,
                    条件 = Trunc(meta.条件, 128),
                    競走名 = Trunc(meta.競走名, 128),
                    着順 = 結果.着順,
                    枠番 = 結果.枠番,
                    馬番 = 馬番,
                    馬名 = Trunc(馬名, 9),
                    馬齢 = 馬齢,
                    性別 = 性別,
                    騎手 = Trunc(NameValue(Raw(i騎手)), 10),
                    斤量 = (float)ServiceErrorHandling.ParseDecimal(Cell(i斤量)),
                    馬体重 = 馬体重,
                    馬体重増減 = 馬体重増減,
                    調教師 = Trunc(NameValue(Raw(i調教師)), 10),
                    調教師所属 = Parse所属(Raw(i調教師)),
                    馬主 = Trunc(NameValue(Raw(i馬主)), 32),
                    馬情報URL = Trunc(Href(Raw(i馬名)), 512),
                    騎手情報URL = Trunc(Href(Raw(i騎手)), 512),
                    調教師情報URL = Trunc(Href(Raw(i調教師)), 512),
                });

                if (馬番 > 0)
                {
                    解析.オッズ.Add(new リアルタイムオッズモデル
                    {
                        開催日 = raceDate,
                        開催場所 = 場名,
                        レース番号 = レース番号,
                        馬番 = 馬番,
                        馬名 = Trunc(馬名, 9),
                        単勝オッズ = 単勝オッズ,
                        人気 = 人気,
                        日時 = 発走時刻,
                    });
                }
            }

            ApplyCornerPositions(通過リスト);
            解析.払戻金.AddRange(ParsePayouts(html, raceDate, 場名, レース番号));
            return 解析;
        }

        private struct RaceMeta
        {
            public string 競走名;
            public string コース種別;
            public string 周回方向;
            public int 距離;
            public string 天候;
            public string 馬場;
            public string 条件;
            public TimeOnly? 発走時刻;
        }

        private static RaceMeta ParseMeta(string html)
        {
            var meta = new RaceMeta
            {
                競走名 = string.Empty,
                コース種別 = string.Empty,
                周回方向 = string.Empty,
                天候 = string.Empty,
                馬場 = string.Empty,
                条件 = string.Empty,
            };

            // 競走名: dl.racedata 内の h1。
            var racedata = Regex.Match(html, @"<dl class=""racedata.*?</dl>", RegexOptions.Singleline);
            if (racedata.Success)
            {
                var h1 = Regex.Match(racedata.Value, @"<h1[^>]*>(?<v>.*?)</h1>", RegexOptions.Singleline);
                if (h1.Success)
                {
                    meta.競走名 = GetText(h1.Groups["v"].Value);
                }

                // 距離・コース・天候・馬場・発走の入った span。
                var span = Regex.Match(racedata.Value, @"<span>(?<v>.*?)</span>", RegexOptions.Singleline);
                if (span.Success)
                {
                    var line = GetText(span.Groups["v"].Value);
                    // 例「芝左2000m」「ダ右1200m」「芝右 外1800m」(京都の内/外回り)「障芝 ダート3000m」。
                    // 方向(左右直)と距離の間に 内/外 や空白が入ることがあるため、間を非貪欲に読み飛ばす。
                    var dist = Regex.Match(line, @"(芝|ダ|障)(?<mid>[^\d]*?)(?<dist>\d{3,4})\s*[mｍＭ]");
                    if (dist.Success)
                    {
                        meta.コース種別 = dist.Groups[1].Value == "ダ" ? "ダ" : dist.Groups[1].Value; // 芝/ダ/障
                        var dir = Regex.Match(dist.Groups["mid"].Value, @"[左右直]");
                        meta.周回方向 = dir.Success ? dir.Value : string.Empty;
                        meta.距離 = int.Parse(dist.Groups["dist"].Value);
                    }
                    var tenki = Regex.Match(line, @"天候\s*:?\s*(晴|曇|小雨|雨|小雪|雪)");
                    if (tenki.Success) meta.天候 = tenki.Groups[1].Value;
                    var baba = Regex.Match(line, @"[芝ダ]\s*:?\s*(不良|稍重|重|良)");
                    if (baba.Success) meta.馬場 = baba.Groups[1].Value;
                    var hasso = Regex.Match(line, @"発走\s*:?\s*(\d{1,2}):(\d{2})");
                    if (hasso.Success) meta.発走時刻 = new TimeOnly(int.Parse(hasso.Groups[1].Value), int.Parse(hasso.Groups[2].Value));
                }
            }

            // 条件(クラス): p.smalltxt の中ほど。例「2024年11月24日 5回東京8日目 3歳以上3勝クラス (国際)(特指)(定量)」
            var small = Regex.Match(html, @"<p class=""smalltxt"">(?<v>.*?)</p>", RegexOptions.Singleline);
            if (small.Success)
            {
                var text = GetText(small.Groups["v"].Value);
                // 「N回場名N日目」の後ろからクラス文言を取り出す。
                var cond = Regex.Match(text, @"\d+回\S+?\d+日目\s*(?<c>[^()（）]+)");
                if (cond.Success)
                {
                    meta.条件 = cond.Groups["c"].Value.Trim();
                }
            }
            return meta;
        }

        private static IEnumerable<払戻金モデル> ParsePayouts(string html, DateOnly raceDate, string 場名, int レース番号)
        {
            var models = new List<払戻金モデル>();
            foreach (Match table in Regex.Matches(html, @"<table[^>]*class=""pay_table_01"".*?</table>", RegexOptions.Singleline))
            {
                foreach (Match row in Regex.Matches(table.Value, @"<tr[^>]*>(?<row>.*?)</tr>", RegexOptions.Singleline))
                {
                    var th = Regex.Match(row.Groups["row"].Value, @"<th[^>]*>(?<v>.*?)</th>", RegexOptions.Singleline);
                    if (!th.Success)
                    {
                        continue;
                    }
                    var 馬券 = Compact(GetText(th.Groups["v"].Value));
                    var tds = Regex.Matches(row.Groups["row"].Value, @"<td[^>]*>(?<v>.*?)</td>", RegexOptions.Singleline)
                        .Select(m => m.Groups["v"].Value).ToList();
                    if (string.IsNullOrWhiteSpace(馬券) || tds.Count < 2)
                    {
                        continue;
                    }

                    // 複勝・ワイド等は1行に複数組が <br> 区切りで入る。組番と金額を分割してzipする。
                    var 組番群 = SplitByBr(tds[0]);
                    var 金額群 = SplitByBr(tds[1]);
                    for (var i = 0; i < 組番群.Count; i++)
                    {
                        var 組番 = Compact(組番群[i]);
                        var 金額 = i < 金額群.Count ? Regex.Replace(金額群[i], @"[^\d]", "") : string.Empty;
                        if (string.IsNullOrWhiteSpace(組番) || string.IsNullOrWhiteSpace(金額))
                        {
                            continue;
                        }
                        models.Add(new 払戻金モデル
                        {
                            開催日 = raceDate,
                            開催場所 = 場名,
                            レース番号 = レース番号,
                            馬券 = Trunc(馬券, 3),
                            組番 = Trunc(組番, 8),
                            金額 = decimal.TryParse(金額, out var v) ? v : 0,
                        });
                    }
                }
            }
            return models;
        }

        // ---- セル・テキスト補助 ----

        private static List<string> SplitCells(string rowHtml)
        {
            return Regex.Matches(rowHtml, @"<t[dh][^>]*>(?<v>.*?)</t[dh]>", RegexOptions.Singleline)
                .Select(m => m.Groups["v"].Value)
                .ToList();
        }

        private static List<string> SplitByBr(string cellHtml)
        {
            return Regex.Split(cellHtml, @"<br\s*/?>", RegexOptions.IgnoreCase)
                .Select(s => s)
                .ToList();
        }

        /// <summary>HTML断片からタグ・エンティティを除き表示テキスト化(連続空白は1つに)。</summary>
        private static string GetText(string html)
        {
            var text = Regex.Replace(html, @"<br\s*/?>", " ", RegexOptions.IgnoreCase);
            text = Regex.Replace(text, @"<[^>]+>", " ");
            text = WebUtility.HtmlDecode(text);
            return Regex.Replace(text, @"\s+", " ").Trim();
        }

        /// <summary>馬名・騎手・調教師・馬主セルから名前を取得。アンカーのtitle属性を優先(表示truncate対策)。</summary>
        private static string NameValue(string cellHtml)
        {
            var title = Regex.Match(cellHtml, @"<a[^>]*\btitle=""(?<v>[^""]+)""", RegexOptions.IgnoreCase);
            if (title.Success)
            {
                return WebUtility.HtmlDecode(title.Groups["v"].Value).Trim();
            }
            return GetText(cellHtml);
        }

        /// <summary>セル内アンカーのhrefを絶対URL化して返す。</summary>
        private static string Href(string cellHtml)
        {
            var m = Regex.Match(cellHtml, @"<a[^>]*\bhref=""(?<v>[^""]+)""", RegexOptions.IgnoreCase);
            if (!m.Success)
            {
                return string.Empty;
            }
            var href = m.Groups["v"].Value;
            if (href.StartsWith("http", StringComparison.OrdinalIgnoreCase))
            {
                return href;
            }
            return "https://db.netkeiba.com" + href;
        }

        /// <summary>調教師セルの [西]/[東] から所属を取り出す。</summary>
        private static string Parse所属(string cellHtml)
        {
            var m = Regex.Match(GetText(cellHtml), @"\[(?<v>東|西|地|外|招|北)\]");
            return m.Success ? m.Groups["v"].Value : string.Empty;
        }

        private static (string 性別, int 馬齢) Parse性齢(string text)
        {
            var t = Compact(text);
            if (string.IsNullOrEmpty(t))
            {
                return (string.Empty, 0);
            }
            var 性別 = t.Substring(0, 1); // 牡/牝/セ/騙
            var 馬齢 = ServiceErrorHandling.ParseInt(t);
            return (性別, 馬齢);
        }

        private static (int 馬体重, int 増減) Parse馬体重(string text)
        {
            // 例「540(+16)」「498(-4)」「計不」
            var m = Regex.Match(text, @"(?<w>\d+)\s*\(\s*(?<d>[+\-]?\d+)\s*\)");
            if (m.Success)
            {
                return (int.Parse(m.Groups["w"].Value), int.Parse(m.Groups["d"].Value));
            }
            var w = Regex.Match(text, @"\d+");
            return (w.Success ? int.Parse(w.Value) : 0, 0);
        }

        /// <summary>分秒(1:59.5)または秒形式の走破時計を秒へ変換。</summary>
        private static decimal ParseRaceTime(string? timeText)
        {
            var text = (timeText ?? string.Empty).Trim();
            if (string.IsNullOrWhiteSpace(text) || !Regex.IsMatch(text, @"\d"))
            {
                return 0m;
            }
            var parts = text.Split(':');
            decimal minutes = parts.Length > 1 ? ServiceErrorHandling.ParseDecimal(parts[0]) : 0m;
            decimal seconds = ServiceErrorHandling.ParseDecimal(parts.Length > 1 ? parts[1] : parts[0]);
            return Math.Round(minutes * 60 + seconds, 1);
        }

        /// <summary>通過順「1-1-1」を最終要素=四コーナーとして右詰めで各コーナー列へ割り当てる。</summary>
        private static void ApplyCornerPositions(IEnumerable<(競走結果モデル Model, string 通過)> rows)
        {
            foreach (var (model, 通過) in rows)
            {
                var positions = Regex.Matches(通過 ?? string.Empty, @"\d+")
                    .Select(m => ServiceErrorHandling.ParseInt(m.Value))
                    .Where(v => v > 0)
                    .ToList();
                if (positions.Count == 0)
                {
                    continue;
                }
                // 末尾を四コーナーに合わせて右詰め(2点=三四角, 3点=二三四角, 4点=一～四角)。
                var corners = new int[4];
                for (var i = 0; i < positions.Count && i < 4; i++)
                {
                    corners[3 - i] = positions[positions.Count - 1 - i];
                }
                model.一コーナー = corners[0];
                model.二コーナー = corners[1];
                model.三コーナー = corners[2];
                model.四コーナー = corners[3];
            }
        }

        /// <summary>走破時計差から一着馬・先着馬・後着馬との着差タイムを計算(地方の競走結果と同方式)。</summary>
        private static void CalculateGapTimes(List<競走結果モデル> results)
        {
            decimal 一着時計 = results.Where(r => r.着順 == 1).Select(r => r.走破時計).FirstOrDefault();
            foreach (var result in results)
            {
                if (result.着順 == 1)
                {
                    var 後着 = results.Where(r => r.走破時計 > 一着時計).OrderBy(r => r.走破時計).FirstOrDefault();
                    result.後着馬着差タイム = 後着 != null ? Math.Abs(後着.走破時計 - 一着時計) : 0m;
                }
                else if (result.着順 > 1)
                {
                    var 先着 = results.Where(r => r.着順 < result.着順).OrderByDescending(r => r.走破時計).FirstOrDefault();
                    var 後着 = results.Where(r => r.着順 > result.着順).OrderBy(r => r.走破時計).FirstOrDefault();
                    result.一着馬着差タイム = result.走破時計 > 0 && 一着時計 > 0 ? Math.Abs(result.走破時計 - 一着時計) : 0m;
                    result.先着馬着差タイム = 先着 != null ? Math.Abs(result.走破時計 - 先着.走破時計) : 0m;
                    result.後着馬着差タイム = 後着 != null ? Math.Abs(後着.走破時計 - result.走破時計) : 0m;
                }
            }
        }

        private static string Compact(string? text) => Regex.Replace(text ?? string.Empty, @"[\s　]", "");

        private static string Trunc(string? text, int max)
        {
            text ??= string.Empty;
            return text.Length <= max ? text : text.Substring(0, max);
        }
    }
}
