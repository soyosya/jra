// 役割: 成績URLから競走結果を取得し、着順・走破時計・上り3F・通過順などを保存します。
// 現在のHTML構造をHTTPで解析し、必要に応じてSeleniumフォールバックも利用します。
// 払戻金と同じ成績ページを起点にするため、当日メニューの成績URLが重要です。
// 必要なusing定義
using System;
using System.Linq;
using System.Text.RegularExpressions;
using System.Web;
using System.Collections.ObjectModel;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using OpenQA.Selenium;
using Microsoft.EntityFrameworkCore;
using 中央競馬.共通.Libraly;
using 中央競馬.共通.Data;
using 中央競馬.共通.Models;

namespace 中央競馬.Services
{
    /// <summary>
    /// 競走結果を取得・保存するクラス
    /// </summary>
    public class 競走結果
    {
        private static readonly HttpClient httpClient = CreateHttpClient();

        /// <summary>
        /// 競走結果を指定URLから取得し、DBに保存する
        /// </summary>
        /// <param name="driver">取得対象ページを操作するSelenium WebDriver。nullを許可するメソッドでは内部で生成します。</param>
        /// <param name="url">取得または解析の対象となるkeiba.go.jpのページURL。</param>
        /// <param name="allowSeleniumFallback">HTTP解析で取得できない場合にSelenium解析へ切り替えるならtrue。</param>
        public static void FetchAndStoreData(IWebDriver? driver, string url, bool allowSeleniumFallback = true)
        {
            Logger.Log("FetchAndStoreData IN");
            try
            {
                if (string.IsNullOrWhiteSpace(url))
                {
                    Logger.Log("競走結果URLが空のため処理をスキップします。");
                    return;
                }

                if (!ServiceErrorHandling.TryReadRaceQuery(url, out var 開催日, out var 開催場所, out var レース番号, out var queryError))
                {
                    Logger.Log($"競走結果URLのクエリが不正なため処理をスキップします: {queryError}");
                    return;
                }

                var results = FetchRaceResultsByHttp(url, 開催日, 開催場所, レース番号);
                if (results.Count == 0)
                {
                    if (!allowSeleniumFallback)
                    {
                        Logger.Log($"HTTPで競走結果を取得できないため処理をスキップします: {url}");
                        return;
                    }

                    driver ??= WebDriverHelper.InitializeDriverAndNavigate(url);
                    if (driver == null)
                    {
                        Logger.Log($"WebDriverの初期化に失敗したため処理をスキップします: {url}");
                        return;
                    }

                    driver.Navigate().GoToUrl(url);
                    results = ParseRaceResults(driver, 開催日, 開催場所, レース番号);
                }

                if (results.Count == 0)
                {
                    Logger.Log($"保存対象の競走結果がありません: {url}");
                    return;
                }

                CalculateGapTimes(results);

                using var context = new DBContext();
                var resultIdIsIdentity = DbIdentityHelper.IsIdentityColumn(context, "競走結果");
                var nextResultId = resultIdIsIdentity ? 0 : DbIdentityHelper.GetNextId(context, "競走結果");
                foreach (var result in results)
                {
                    var existing = context.競走結果.FirstOrDefault(h => h.開催日 == result.開催日 && h.開催場所 == result.開催場所 && h.レース番号 == result.レース番号 && h.馬名 == result.馬名);
                    if (existing != null)
                    {
                        UpdateRaceResult(existing, result);
                    }
                    else
                    {
                        if (!resultIdIsIdentity) result.Id = nextResultId++;
                        context.競走結果.Add(result);
                    }
                }
                context.SaveChanges();

                Logger.Log("競走結果保存完了");
            }
            catch (Exception ex)
            {
                Logger.LogError("FetchAndStoreDataエラー", ex);
            }
            finally
            {
                Logger.Log("FetchAndStoreData OUT");
            }
        }

        /// <summary>
        /// keiba.go.jpの成績ページをHTTP取得するため、タイムアウトとUser-Agentを設定したHttpClientを生成します。
        /// </summary>
        /// <returns>成績ページ取得に使用する、タイムアウトとUser-Agent設定済みのHttpClient。</returns>
        private static HttpClient CreateHttpClient()
        {
            var client = new HttpClient
            {
                Timeout = TimeSpan.FromSeconds(60)
            };
            // ボット的なUAだとkeiba.go.jpに絞られて遅延・拒否されるため、通常ブラウザと同じUAを名乗る。
            client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36");
            return client;
        }

        /// <summary>
        /// 成績ページHTMLをHTTPで取得し、現在形式の競走結果テーブルを解析します。
        /// </summary>
        /// <param name="url">取得または解析の対象となるkeiba.go.jpのページURL。</param>
        /// <param name="開催日">保存または解析結果へ設定する開催日。</param>
        /// <param name="開催場所">保存または解析結果へ設定する開催場所。</param>
        /// <param name="レース番号">保存または解析結果へ設定するレース番号。</param>
        /// <returns>HTTP取得した成績ページから解析できた競走結果モデル一覧。解析できない場合は空リスト。</returns>
        private static List<競走結果モデル> FetchRaceResultsByHttp(string url, DateOnly 開催日, string 開催場所, int レース番号)
        {
            try
            {
                var html = httpClient.GetStringAsync(url).GetAwaiter().GetResult();
                return ParseCurrentRaceResultsFromHtml(html, 開催日, 開催場所, レース番号);
            }
            catch (Exception ex)
            {
                Logger.LogError($"HTTPで競走結果を取得できませんでした。Seleniumにフォールバックします。URL:{url}", ex);
                return new List<競走結果モデル>();
            }
        }

        /// <summary>
        /// Seleniumで表示中の成績ページから、現在形式または旧形式の競走結果テーブルを解析します。
        /// </summary>
        /// <param name="driver">取得対象ページを操作するSelenium WebDriver。nullを許可するメソッドでは内部で生成します。</param>
        /// <param name="開催日">保存または解析結果へ設定する開催日。</param>
        /// <param name="開催場所">保存または解析結果へ設定する開催場所。</param>
        /// <param name="レース番号">保存または解析結果へ設定するレース番号。</param>
        /// <returns>Seleniumで解析できた競走結果モデル一覧。対象テーブルがない場合は空リスト。</returns>
        private static List<競走結果モデル> ParseRaceResults(IWebDriver driver, DateOnly 開催日, string 開催場所, int レース番号)
        {
            var currentRows = ServiceErrorHandling.WaitForElements(driver, By.CssSelector("section.gradeTable table tbody tr.tBorder"), TimeSpan.FromSeconds(5));
            if (currentRows.Count > 0)
            {
                var cornerSectionNumbers = FindCornerSectionNumbers(driver);
                return ParseCurrentRaceResults(currentRows, 開催日, 開催場所, レース番号, cornerSectionNumbers);
            }

            string oldXpath = "//table[@class='bs'][3]/tbody/tr[1]/td[@class='dbtbl']/table[1]/tbody/tr[position() > 2]";
            var oldRows = ServiceErrorHandling.WaitForElements(driver, By.XPath(oldXpath), TimeSpan.FromSeconds(1));
            if (oldRows.Count > 0)
            {
                var cornerSectionNumbers = FindCornerSectionNumbers(driver);
                return ParseOldRaceResults(oldRows, 開催日, 開催場所, レース番号, cornerSectionNumbers);
            }

            Logger.Log("競走結果ページが存在しません。");
            return new List<競走結果モデル>();
        }

        /// <summary>
        /// 現在形式の成績テーブル行から、着順、馬番、馬名、走破時計、通過順を読み取ります。
        /// </summary>
        /// <param name="rows">解析対象となるテーブル行要素の一覧。</param>
        /// <param name="開催日">保存または解析結果へ設定する開催日。</param>
        /// <param name="開催場所">保存または解析結果へ設定する開催場所。</param>
        /// <param name="レース番号">保存または解析結果へ設定するレース番号。</param>
        /// <returns>現在形式テーブルから作成した競走結果モデル一覧。</returns>
        private static List<競走結果モデル> ParseCurrentRaceResults(IEnumerable<IWebElement> rows, DateOnly 開催日, string 開催場所, int レース番号, IReadOnlyList<int> cornerSectionNumbers)
        {
            Logger.Log("ParseCurrentRaceResults IN");
            var results = new List<競走結果モデル>();
            var parsedRows = new List<(競走結果モデル Model, string CornerText)>();
            try
            {
                foreach (var row in rows)
                {
                    var td = row.FindElements(By.TagName("td"));
                    if (td.Count < 14)
                    {
                        Logger.Log($"現行競走結果行の列数が不足しているためスキップします: 列数={td.Count}");
                        continue;
                    }

                    var cellTexts = td.Select(GetCellText).ToList();
                    var horseName = cellTexts[3].Trim();
                    if (string.IsNullOrWhiteSpace(horseName))
                    {
                        Logger.Log("現行競走結果行の馬名が空のためスキップします。");
                        continue;
                    }

                    var model = new 競走結果モデル
                    {
                        開催日 = 開催日,
                        開催場所 = 開催場所,
                        レース番号 = レース番号,
                        着順 = ServiceErrorHandling.ParseInt(cellTexts[0]),
                        枠番 = ServiceErrorHandling.ParseInt(cellTexts[1]),
                        馬番 = ServiceErrorHandling.ParseInt(cellTexts[2]),
                        馬名 = horseName,
                        走破時計 = ParseRaceTime(cellTexts[10]),
                        着差 = cellTexts[11].Trim(),
                        上り3F = ServiceErrorHandling.ParseDecimal(cellTexts[12])
                    };

                    parsedRows.Add((model, FindCornerPositionText(row, cellTexts, 13)));
                }

                ApplyCornerPositions(parsedRows, cornerSectionNumbers);
                results.AddRange(parsedRows.Select(r => r.Model));
            }
            catch (Exception ex)
            {
                Logger.LogError("ParseCurrentRaceResultsエラー", ex);
            }
            finally
            {
                Logger.Log("ParseCurrentRaceResults OUT");
            }
            return results;
        }

        /// <summary>
        /// HTTPで取得した現在形式の成績HTMLから、競走結果テーブルの各行をモデルへ変換します。
        /// </summary>
        /// <param name="html">解析対象となるHTML文字列またはHTML断片。</param>
        /// <param name="開催日">保存または解析結果へ設定する開催日。</param>
        /// <param name="開催場所">保存または解析結果へ設定する開催場所。</param>
        /// <param name="レース番号">保存または解析結果へ設定するレース番号。</param>
        /// <returns>HTMLから解析できた競走結果モデル一覧。成績テーブルが見つからない場合は空リスト。</returns>
        private static List<競走結果モデル> ParseCurrentRaceResultsFromHtml(string html, DateOnly 開催日, string 開催場所, int レース番号)
        {
            Logger.Log("ParseCurrentRaceResultsFromHtml IN");
            var results = new List<競走結果モデル>();
            var parsedRows = new List<(競走結果モデル Model, string CornerText)>();
            try
            {
                var decodedHtml = WebUtility.HtmlDecode(html);
                var cornerSectionNumbers = ExtractCornerSectionNumbersFromHtml(decodedHtml);
                var rows = Regex.Matches(decodedHtml, @"<tr\b[^>]*class\s*=\s*[""'][^""']*\btBorder\b[^""']*[""'][^>]*>(?<row>.*?)</tr>", RegexOptions.IgnoreCase | RegexOptions.Singleline);

                foreach (Match row in rows)
                {
                    var cellMatches = Regex.Matches(row.Groups["row"].Value, @"<td\b[^>]*>(?<cell>.*?)</td>", RegexOptions.IgnoreCase | RegexOptions.Singleline);
                    var cells = cellMatches
                        .Select(m => GetHtmlText(m.Groups["cell"].Value))
                        .ToList();
                    if (cells.Count < 14)
                    {
                        Logger.Log($"HTML競走結果行の列数が不足しているためスキップします: 列数={cells.Count}");
                        continue;
                    }

                    var horseName = cells[3].Trim();
                    if (string.IsNullOrWhiteSpace(horseName))
                    {
                        Logger.Log("HTML競走結果行の馬名が空のためスキップします。");
                        continue;
                    }

                    var model = new 競走結果モデル
                    {
                        開催日 = 開催日,
                        開催場所 = 開催場所,
                        レース番号 = レース番号,
                        着順 = ServiceErrorHandling.ParseInt(cells[0]),
                        枠番 = ServiceErrorHandling.ParseInt(cells[1]),
                        馬番 = ServiceErrorHandling.ParseInt(cells[2]),
                        馬名 = horseName,
                        走破時計 = ParseRaceTime(cells[10]),
                        着差 = cells[11].Trim(),
                        上り3F = ServiceErrorHandling.ParseDecimal(cells[12])
                    };

                    parsedRows.Add((model, FindCornerPositionText(cellMatches, cells, 13)));
                }

                ApplyCornerPositions(parsedRows, cornerSectionNumbers);
                results.AddRange(parsedRows.Select(r => r.Model));
            }
            catch (Exception ex)
            {
                Logger.LogError("ParseCurrentRaceResultsFromHtmlエラー", ex);
            }
            finally
            {
                Logger.Log("ParseCurrentRaceResultsFromHtml OUT");
            }
            return results;
        }

        /// <summary>
        /// 旧形式の成績テーブル行から、競走結果モデルを作成します。
        /// </summary>
        /// <param name="rows">解析対象となるテーブル行要素の一覧。</param>
        /// <param name="開催日">保存または解析結果へ設定する開催日。</param>
        /// <param name="開催場所">保存または解析結果へ設定する開催場所。</param>
        /// <param name="レース番号">保存または解析結果へ設定するレース番号。</param>
        /// <returns>旧形式テーブルから作成した競走結果モデル一覧。</returns>
        private static List<競走結果モデル> ParseOldRaceResults(IEnumerable<IWebElement> rows, DateOnly 開催日, string 開催場所, int レース番号, IReadOnlyList<int> cornerSectionNumbers)
        {
            Logger.Log("ParseOldRaceResults IN");
            var results = new List<競走結果モデル>();
            var parsedRows = new List<(競走結果モデル Model, string CornerText)>();
            try
            {
                foreach (var row in rows)
                {
                    var td = row.FindElements(By.TagName("td"));
                    if (td.Count < 14)
                    {
                        Logger.Log($"旧競走結果行の列数が不足しているためスキップします: 列数={td.Count}");
                        continue;
                    }

                    int.TryParse(td[0].Text, out var 着順);
                    int.TryParse(td[1].Text, out var 枠番);
                    int.TryParse(td[2].Text, out var 馬番);

                    var model = new 競走結果モデル
                    {
                        開催日 = 開催日,
                        開催場所 = 開催場所,
                        レース番号 = レース番号,
                        着順 = 着順,
                        枠番 = 枠番,
                        馬番 = 馬番,
                        馬名 = td[3].Text.Trim(),
                        着差 = td[12].Text.Trim(),
                        上り3F = ServiceErrorHandling.ParseDecimal(td[13].Text)
                    };

                    model.走破時計 = ParseRaceTime(td[11].Text);
                    parsedRows.Add((model, FindCornerPositionText(td.Select(GetCellText).ToList(), 14)));
                }

                ApplyCornerPositions(parsedRows, cornerSectionNumbers);
                results.AddRange(parsedRows.Select(r => r.Model));
            }
            catch (Exception ex)
            {
                Logger.LogError("ParseOldRaceResultsエラー", ex);
            }
            finally
            {
                Logger.Log("ParseOldRaceResults OUT");
            }
            return results;
        }

        /// <summary>
        /// Seleniumのセル要素から表示テキストを取得し、連続空白を1つの空白へ整えます。
        /// </summary>
        /// <param name="cell">テキストを取得するテーブルセル要素。</param>
        /// <returns>セル内の表示テキスト。セルが空の場合は空文字列。</returns>
        private static string GetCellText(IWebElement cell)
        {
            return Regex.Replace(cell.Text ?? string.Empty, @"\s+", " ").Trim();
        }

        /// <summary>
        /// HTML断片からタグとエンティティを取り除き、画面表示に近い文字列へ整形します。
        /// </summary>
        /// <param name="html">解析対象となるHTML文字列またはHTML断片。</param>
        /// <returns>タグ除去とHTMLデコード後のテキスト。</returns>
        private static string GetHtmlText(string html)
        {
            var text = Regex.Replace(html, @"<br\s*/?>", " ", RegexOptions.IgnoreCase);
            text = Regex.Replace(text, @"<[^>]+>", " ");
            text = WebUtility.HtmlDecode(text);
            return Regex.Replace(text, @"\s+", " ").Trim();
        }

        /// <summary>
        /// Seleniumで表示中の成績ページから、全馬コーナー通過順欄の見出しを読み取ります。
        /// 川崎の短距離戦などで現れる「向正面」はDBに対応列がないため0として扱い、後続の3角・4角との位置合わせに使います。
        /// </summary>
        /// <param name="driver">成績ページを表示しているSelenium WebDriver。</param>
        /// <returns>通過順テキストの各要素に対応するコーナー番号。向正面は0、見出しが取れない場合は空の一覧。</returns>
        private static List<int> FindCornerSectionNumbers(IWebDriver driver)
        {
            try
            {
                return driver.FindElements(By.CssSelector("section.cornerPassTable table tbody tr"))
                    .Select(row => row.FindElements(By.TagName("td")).FirstOrDefault())
                    .Where(cell => cell != null)
                    .Select(cell => ParseCornerSectionNumber(GetCellText(cell!)))
                    .Where(number => number.HasValue)
                    .Select(number => number!.Value)
                    .ToList();
            }
            catch (Exception ex)
            {
                Logger.LogError("全馬コーナー通過順見出しの取得に失敗しました。通過順の点数から推定します。", ex);
                return new List<int>();
            }
        }

        /// <summary>
        /// HTTPで取得した成績ページHTMLから、全馬コーナー通過順欄の見出しを読み取ります。
        /// 見出しが通過順セルの点数と一致する場合は、点数だけの推定よりもこの見出しを優先します。
        /// </summary>
        /// <param name="html">WebUtility.HtmlDecode済みの成績ページHTML。</param>
        /// <returns>通過順テキストの各要素に対応するコーナー番号。向正面は0、見出しが取れない場合は空の一覧。</returns>
        private static List<int> ExtractCornerSectionNumbersFromHtml(string html)
        {
            var cornerSection = Regex.Match(
                html,
                @"<section\b[^>]*class\s*=\s*[""'][^""']*\bcornerPassTable\b[^""']*[""'][^>]*>(?<section>.*?)</section>",
                RegexOptions.IgnoreCase | RegexOptions.Singleline);

            if (!cornerSection.Success)
            {
                return new List<int>();
            }

            return Regex.Matches(cornerSection.Groups["section"].Value, @"<tr\b[^>]*>\s*<td\b[^>]*>(?<label>.*?)</td>", RegexOptions.IgnoreCase | RegexOptions.Singleline)
                .Select(row => ParseCornerSectionNumber(GetHtmlText(row.Groups["label"].Value)))
                .Where(number => number.HasValue)
                .Select(number => number!.Value)
                .ToList();
        }

        /// <summary>
        /// 全馬コーナー通過順欄の見出しを、DB列へ対応させるための番号に変換します。
        /// 「向正面」は通過順テキスト上の位置合わせには必要ですが、一～四コーナー列には保存しないため0を返します。
        /// </summary>
        /// <param name="label">全馬コーナー通過順欄の見出しテキスト。</param>
        /// <returns>一～四コーナーなら1～4、向正面なら0、対象外ならnull。</returns>
        private static int? ParseCornerSectionNumber(string? label)
        {
            var normalized = Regex.Replace(label ?? string.Empty, @"\s+", string.Empty);
            if (string.IsNullOrWhiteSpace(normalized))
            {
                return null;
            }

            if (normalized.Contains("向正面")
                || normalized.Contains("正面")
                || normalized.Contains("直線"))
            {
                return 0;
            }

            var cornerMatches = Regex.Matches(normalized, @"(?<number>１|２|３|４|1|2|3|4|一|二|三|四)(?:コーナー|コーナ|角)");
            if (cornerMatches.Count == 0)
            {
                return null;
            }

            return cornerMatches[cornerMatches.Count - 1].Groups["number"].Value switch
            {
                "１" or "1" or "一" => 1,
                "２" or "2" or "二" => 2,
                "３" or "3" or "三" => 3,
                "４" or "4" or "四" => 4,
                _ => null
            };
        }

        /// <summary>
        /// 分秒形式または秒形式の走破時計テキストを、秒単位の小数値へ変換します。
        /// </summary>
        /// <param name="timeText">成績ページに表示された走破時計テキスト。</param>
        /// <returns>秒単位に変換した走破時計。解析できない場合は0。</returns>
        private static decimal ParseRaceTime(string? timeText)
        {
            var text = (timeText ?? string.Empty).Trim();
            if (string.IsNullOrWhiteSpace(text))
            {
                return 0m;
            }

            var timeParts = text.Split(':');
            decimal minutes = timeParts.Length > 1 ? ServiceErrorHandling.ParseDecimal(timeParts[0]) : 0m;
            decimal seconds = ServiceErrorHandling.ParseDecimal(timeParts.Length > 1 ? timeParts[1] : timeParts[0]);
            return Math.Round(minutes * 60 + seconds, 1);
        }

        /// <summary>
        /// Seleniumで取得した成績行から、コーナー通過順のセルを探して返します。
        /// 現行ページはcorner_positionクラスを持つため、そのセルを優先し、見つからない場合は列位置と文字列形式で補完します。
        /// </summary>
        /// <param name="row">解析対象となる成績行要素。</param>
        /// <param name="cellTexts">行内セルの表示テキスト一覧。</param>
        /// <param name="preferredIndex">通常レイアウトでコーナー通過順が入る列番号。</param>
        /// <returns>コーナー通過順として扱えるテキスト。見つからない場合は空文字列。</returns>
        private static string FindCornerPositionText(IWebElement row, IReadOnlyList<string> cellTexts, int preferredIndex)
        {
            var cornerCellText = row.FindElements(By.CssSelector("td.corner_position"))
                                    .Select(GetCellText)
                                    .FirstOrDefault(IsCornerPositionText);
            return !string.IsNullOrWhiteSpace(cornerCellText)
                ? cornerCellText
                : FindCornerPositionText(cellTexts, preferredIndex);
        }

        /// <summary>
        /// HTTPで取得した成績行のHTMLから、コーナー通過順のセルを探して返します。
        /// class属性にcorner_positionが付いたセルを優先し、HTML構造が変わった場合はセルテキストから候補を探します。
        /// </summary>
        /// <param name="cellMatches">行内td要素の正規表現マッチ一覧。</param>
        /// <param name="cellTexts">行内セルの表示テキスト一覧。</param>
        /// <param name="preferredIndex">通常レイアウトでコーナー通過順が入る列番号。</param>
        /// <returns>コーナー通過順として扱えるテキスト。見つからない場合は空文字列。</returns>
        private static string FindCornerPositionText(MatchCollection cellMatches, IReadOnlyList<string> cellTexts, int preferredIndex)
        {
            for (var index = 0; index < cellMatches.Count && index < cellTexts.Count; index++)
            {
                if (Regex.IsMatch(cellMatches[index].Value, @"class\s*=\s*[""'][^""']*\bcorner_position\b", RegexOptions.IgnoreCase)
                    && IsCornerPositionText(cellTexts[index]))
                {
                    return cellTexts[index];
                }
            }

            return FindCornerPositionText(cellTexts, preferredIndex);
        }

        /// <summary>
        /// セルテキスト一覧から、コーナー通過順らしい値を探して返します。
        /// 通常列を先に確認し、列位置が変わった場合はハイフンやカンマで区切られた数字列を候補にします。
        /// </summary>
        /// <param name="cellTexts">行内セルの表示テキスト一覧。</param>
        /// <param name="preferredIndex">通常レイアウトでコーナー通過順が入る列番号。</param>
        /// <returns>コーナー通過順として扱えるテキスト。見つからない場合は空文字列。</returns>
        private static string FindCornerPositionText(IReadOnlyList<string> cellTexts, int preferredIndex)
        {
            if (preferredIndex >= 0
                && preferredIndex < cellTexts.Count
                && IsCornerPositionText(cellTexts[preferredIndex]))
            {
                return cellTexts[preferredIndex];
            }

            return cellTexts.FirstOrDefault(IsCornerPositionText) ?? string.Empty;
        }

        /// <summary>
        /// 指定された文字列が、馬体重や人気ではなくコーナー通過順として扱える形式かを判定します。
        /// 例: 1-1-1-1、1,1,1,1、1-1 のような複数地点の通過順を対象にします。
        /// </summary>
        /// <param name="text">判定対象のセルテキスト。</param>
        /// <returns>コーナー通過順の形式ならtrue、それ以外ならfalse。</returns>
        private static bool IsCornerPositionText(string? text)
        {
            var normalized = Regex.Replace(text ?? string.Empty, @"\s+", string.Empty);
            return Regex.IsMatch(normalized, @"^\d+(?:[-－ー―,、]\d+)+$");
        }

        /// <summary>
        /// レース内の通過順表記の最大点数から開始コーナーを決め、各行の通過順位をモデルへ設定します。
        /// 2点表記は3角・4角、3点表記は2角・3角・4角、4点表記は1角から4角として扱います。
        /// </summary>
        /// <param name="parsedRows">競走結果モデルと成績ページ上の通過順テキストの組み合わせ一覧。</param>
        private static void ApplyCornerPositions(IEnumerable<(競走結果モデル Model, string CornerText)> parsedRows, IReadOnlyList<int> cornerSectionNumbers)
        {
            var rows = parsedRows.ToList();
            var cornerNumbers = GetCornerNumbers(rows.Select(r => r.CornerText), cornerSectionNumbers);

            foreach (var row in rows)
            {
                SetCornerPositions(row.Model, row.CornerText, cornerNumbers);
            }
        }

        /// <summary>
        /// 全馬コーナー通過順欄の見出し、または通過順テキストの点数から、各要素がどのコーナーを表すかを決めます。
        /// 見出しの数と通過順の最大点数が一致する場合は、向正面のような非コーナー地点も含めて見出しを優先します。
        /// </summary>
        /// <param name="cornerTexts">同一レース内の通過順テキスト一覧。</param>
        /// <param name="cornerSectionNumbers">全馬コーナー通過順欄から読み取った地点番号。向正面は0。</param>
        /// <returns>通過順テキストの各要素に対応する地点番号。一～四コーナーは1～4、保存対象外地点は0。</returns>
        private static List<int> GetCornerNumbers(IEnumerable<string?> cornerTexts, IReadOnlyList<int> cornerSectionNumbers)
        {
            var cornerTextList = cornerTexts.ToList();
            var maxPositionCount = cornerTextList
                .Select(text => ParseCornerPositions(text).Count)
                .DefaultIfEmpty(0)
                .Max();

            if (cornerSectionNumbers.Count >= maxPositionCount
                && maxPositionCount > 0
                && cornerSectionNumbers.Any(number => number is >= 1 and <= 4))
            {
                return cornerSectionNumbers
                    .Skip(cornerSectionNumbers.Count - maxPositionCount)
                    .ToList();
            }

            var startCorner = GetCornerStartPosition(maxPositionCount);
            return Enumerable.Range(startCorner, Math.Max(0, maxPositionCount))
                .Select(number => number <= 4 ? number : 0)
                .ToList();
        }

        /// <summary>
        /// レース内で最も多い通過順点数から、最初の数字が何コーナーを表すかを判定します。
        /// 例として、1-1は3角・4角、1-1-1は2角・3角・4角、1-1-1-1は1角から4角として扱います。
        /// </summary>
        /// <param name="maxPositionCount">同一レース内で最も多い通過順の点数。</param>
        /// <returns>通過順テキストの先頭要素に対応するコーナー番号。判定できない場合は1。</returns>
        private static int GetCornerStartPosition(int maxPositionCount)
        {
            return maxPositionCount switch
            {
                4 => 1,
                3 => 2,
                2 => 3,
                1 => 4,
                _ => 1
            };
        }

        /// <summary>
        /// 通過順テキストを数字の一覧へ分解します。
        /// ハイフンや読点などの区切り文字が異なる場合でも、表示順に数字だけを取り出します。
        /// </summary>
        /// <param name="cornerText">成績ページから取得した通過順テキスト。</param>
        /// <returns>通過順テキストに含まれる正の整数一覧。</returns>
        private static List<int> ParseCornerPositions(string? cornerText)
        {
            return Regex.Matches(cornerText ?? string.Empty, @"\d+")
                .Select(m => ServiceErrorHandling.ParseInt(m.Value))
                .Where(v => v > 0)
                .ToList();
        }

        /// <summary>
        /// 通過順テキストを分解し、指定された開始コーナーから順に通過順位をモデルへ設定します。
        /// </summary>
        /// <param name="model">値を設定する競走結果モデル。</param>
        /// <param name="cornerText">成績ページから取得した通過順テキスト。</param>
        /// <param name="cornerNumbers">通過順テキストの各要素に対応する地点番号。一～四コーナーは1～4、保存対象外地点は0。</param>
        private static void SetCornerPositions(競走結果モデル model, string? cornerText, IReadOnlyList<int> cornerNumbers)
        {
            var positions = ParseCornerPositions(cornerText);
            for (var index = 0; index < positions.Count; index++)
            {
                var cornerNumber = index < cornerNumbers.Count ? cornerNumbers[index] : 0;
                switch (cornerNumber)
                {
                    case 1:
                        model.一コーナー = positions[index];
                        break;
                    case 2:
                        model.二コーナー = positions[index];
                        break;
                    case 3:
                        model.三コーナー = positions[index];
                        break;
                    case 4:
                        model.四コーナー = positions[index];
                        break;
                }
            }
        }

        /// <summary>
        /// 競走結果モデルに、1つ以上のコーナー通過順が設定されているかを判定します。
        /// 再取得したページに通過順が掲載されていない場合に、既存値を0で上書きしないために使用します。
        /// </summary>
        /// <param name="result">判定対象の競走結果モデル。</param>
        /// <returns>いずれかのコーナー通過順が1以上ならtrue、それ以外ならfalse。</returns>
        private static bool HasCornerPositions(競走結果モデル result)
        {
            return result.一コーナー > 0
                || result.二コーナー > 0
                || result.三コーナー > 0
                || result.四コーナー > 0;
        }

        /// <summary>
        /// 既存の競走結果モデルへ、再取得した着順、時計、通過順、着差情報を上書きします。
        /// </summary>
        /// <param name="existing">DBから取得した更新対象の既存競走結果モデル。</param>
        /// <param name="result">成績ページから新しく解析した競走結果モデル。</param>
        private static void UpdateRaceResult(競走結果モデル existing, 競走結果モデル result)
        {
            existing.着順 = result.着順;
            existing.枠番 = result.枠番;
            existing.馬番 = result.馬番;
            existing.一着馬着差タイム = result.一着馬着差タイム;
            existing.先着馬着差タイム = result.先着馬着差タイム;
            existing.後着馬着差タイム = result.後着馬着差タイム;
            existing.上り3F = result.上り3F;
            existing.走破時計 = result.走破時計;
            existing.着差 = result.着差;
            if (HasCornerPositions(result))
            {
                existing.一コーナー = result.一コーナー;
                existing.二コーナー = result.二コーナー;
                existing.三コーナー = result.三コーナー;
                existing.四コーナー = result.四コーナー;
            }
        }

        /// <summary>
        /// 走破時計の一覧から、一着馬との着差、先着馬との差、後着馬との差を計算して各結果へ設定します。
        /// </summary>
        /// <param name="results">走破時計が設定済みの競走結果モデル一覧。</param>
        private static void CalculateGapTimes(List<競走結果モデル> results)
        {
            Logger.Log("CalculateGapTimes IN");
            try
            {
                decimal 一着馬走破時計 = results.Where(r => r.着順 == 1).Select(r => r.走破時計).FirstOrDefault();
                foreach (var result in results)
                {
                    if (result.着順 == 1)
                    {
                        var 後着 = results.Where(r => r.走破時計 > 一着馬走破時計).OrderBy(r => r.走破時計).FirstOrDefault();
                        result.後着馬着差タイム = 後着 != null ? Math.Abs(後着.走破時計 - 一着馬走破時計) : 0m;
                    }
                    else if (result.着順 > 1)
                    {
                        var 先着 = results.Where(r => r.着順 < result.着順).OrderByDescending(r => r.走破時計).FirstOrDefault();
                        var 後着 = results.Where(r => r.着順 > result.着順).OrderBy(r => r.走破時計).FirstOrDefault();
                        result.一着馬着差タイム = Math.Abs(result.走破時計 - 一着馬走破時計);
                        result.先着馬着差タイム = 先着 != null ? Math.Abs(result.走破時計 - 先着.走破時計) : 0m;
                        result.後着馬着差タイム = 後着 != null ? Math.Abs(後着.走破時計 - result.走破時計) : 0m;
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("CalculateGapTimesエラー", ex);
            }
            finally
            {
                Logger.Log("CalculateGapTimes OUT");
            }
        }
    }
}
