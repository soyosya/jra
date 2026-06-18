// 役割: 成績URLから払戻金テーブルを取得し、馬券種別、組番、金額を保存します。
// 新旧ページ構造に対応するため、HTTP解析とSelenium解析の両方を持っています。
// 最終レースの払戻金有無は、当日のレース終了判定にも使います。
// using定義（必要な名前空間のみ残す）
using Microsoft.EntityFrameworkCore;
using OpenQA.Selenium;
using OpenQA.Selenium.Support.UI;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Web;
using 中央競馬.共通.Data;
using 中央競馬.共通.Libraly;
using 中央競馬.共通.Models;

namespace 中央競馬.Services
{
    /// <summary>
    /// 払戻金のデータ取得と保存を行うバッチ処理クラス
    /// </summary>
    public class 払戻金
    {
        private static readonly HttpClient httpClient = CreateHttpClient();

        /// <summary>
        /// エントリーポイント
        /// </summary>
        /// <param name="args">サービス単体実行時に渡されるコマンドライン引数。固定URLの確認処理では参照しない場合があります。</param>
        public static void 取得(string[] args)
        {
            Logger.Log("取得 IN");
            try
            {
                FetchAndStoreData(null, "https://www.keiba.go.jp/KeibaWeb/TodayRaceInfo/RaceMarkTable?k_raceDate=2025%2f01%2f01&k_raceNo=1&k_babaCode=21");
            }
            catch (Exception ex)
            {
                Logger.LogError("取得中にエラー", ex);
            }
            finally
            {
                Logger.Log("取得 OUT");
            }
        }

        /// <summary>
        /// 払戻金データを取得しDBに保存する
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
                    Logger.Log("払戻金URLが空のため処理をスキップします。");
                    return;
                }

                if (!ServiceErrorHandling.TryReadRaceQuery(url, out var 開催日, out var 開催場所, out var レース番号, out var queryError))
                {
                    Logger.Log($"払戻金URLのクエリが不正なため処理をスキップします: {queryError}");
                    return;
                }

                var models = FetchPayoutDataByHttp(url, 開催日, 開催場所, レース番号);
                if (models.Count == 0)
                {
                    if (!allowSeleniumFallback)
                    {
                        Logger.Log($"HTTPで払戻金を取得できないため処理をスキップします: {url}");
                        return;
                    }

                    driver ??= WebDriverHelper.InitializeDriverAndNavigate(url);
                    if (driver == null)
                    {
                        Logger.Log($"WebDriverの初期化に失敗したため処理をスキップします: {url}");
                        return;
                    }

                    driver.Navigate().GoToUrl(url);

                    var newPayoutTable = WaitForDisplayedElement(driver, By.CssSelector("section.newRefundTable"), TimeSpan.FromSeconds(3));
                    models = newPayoutTable != null
                        ? ParseNewPayoutData(newPayoutTable, 開催日, 開催場所, レース番号)
                        : new List<払戻金モデル>();

                    if (newPayoutTable == null)
                    {
                        var refundListTable = WaitForDisplayedElement(driver, By.CssSelector("section.refundTable"), TimeSpan.FromSeconds(1));
                        if (refundListTable != null)
                        {
                            models = ParseRefundListData(refundListTable, 開催日, 開催場所, レース番号);
                        }
                    }

                    if (models.Count == 0)
                    {
                        var oldPayoutTable = WaitForDisplayedElement(driver, By.XPath("//span[normalize-space()='払戻金']/ancestor::table[1]"), TimeSpan.FromSeconds(1));
                        if (oldPayoutTable != null)
                        {
                            models = ParsePayoutData(oldPayoutTable, 開催日, 開催場所, レース番号);
                        }
                    }
                }

                if (models.Count == 0)
                {
                    Logger.Log($"払戻金データが見つかりません: {url}");
                    return;
                }

                using var context = new DBContext();
                foreach (var model in models)
                {
                    var existing = context.払戻金.FirstOrDefault(h => h.開催日 == model.開催日 && h.開催場所 == model.開催場所 && h.レース番号 == model.レース番号 && h.馬券 == model.馬券 && h.組番 == model.組番);
                    if (existing != null)
                    {
                        existing.金額 = model.金額;
                    }
                    else
                    {
                        context.払戻金.Add(model);
                    }
                }
                context.SaveChanges();

                Logger.Log("払戻金データ保存完了");
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
        /// keiba.go.jpの払戻金ページをHTTP取得するため、タイムアウトとUser-Agentを設定したHttpClientを生成します。
        /// </summary>
        /// <returns>払戻金ページ取得に使用する、タイムアウトとUser-Agent設定済みのHttpClient。</returns>
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
        /// 成績ページHTMLをHTTPで取得し、現在形式の払戻金テーブルを解析します。
        /// </summary>
        /// <param name="url">取得または解析の対象となるkeiba.go.jpのページURL。</param>
        /// <param name="開催日">保存または解析結果へ設定する開催日。</param>
        /// <param name="開催場所">保存または解析結果へ設定する開催場所。</param>
        /// <param name="レース番号">保存または解析結果へ設定するレース番号。</param>
        /// <returns>HTTP取得したHTMLから解析できた払戻金モデル一覧。解析できない場合は空リスト。</returns>
        private static List<払戻金モデル> FetchPayoutDataByHttp(string url, DateOnly 開催日, string 開催場所, int レース番号)
        {
            try
            {
                var html = httpClient.GetStringAsync(url).GetAwaiter().GetResult();
                return ParseNewPayoutDataFromHtml(html, 開催日, 開催場所, レース番号);
            }
            catch (Exception ex)
            {
                Logger.LogError($"HTTPで払戻金を取得できませんでした。Seleniumにフォールバックします。URL:{url}", ex);
                return new List<払戻金モデル>();
            }
        }

        /// <summary>
        /// Seleniumで指定要素が表示されるまで待機し、タイムアウト時は例外ではなくnullを返します。
        /// </summary>
        /// <param name="driver">取得対象ページを操作するSelenium WebDriver。nullを許可するメソッドでは内部で生成します。</param>
        /// <param name="by">検索に使用するSeleniumセレクタ。</param>
        /// <param name="timeout">要素の表示を待機する最大時間。</param>
        /// <returns>表示状態で見つかったSelenium要素。指定時間内に見つからない場合はnull。</returns>
        private static IWebElement? WaitForDisplayedElement(IWebDriver driver, By by, TimeSpan timeout)
        {
            try
            {
                var wait = new WebDriverWait(driver, timeout);
                return wait.Until(d => d.FindElements(by).FirstOrDefault(e => e.Displayed));
            }
            catch (WebDriverTimeoutException)
            {
                return null;
            }
            catch (NoSuchElementException)
            {
                return null;
            }
            catch (StaleElementReferenceException)
            {
                return null;
            }
        }

        /// <summary>
        /// 現在形式の払戻金セクションから、馬券種別、組番、金額を読み取りモデル一覧を作成します。
        /// </summary>
        /// <param name="payoutSection">払戻金情報を含むセクション要素。</param>
        /// <param name="開催日">保存または解析結果へ設定する開催日。</param>
        /// <param name="開催場所">保存または解析結果へ設定する開催場所。</param>
        /// <param name="レース番号">保存または解析結果へ設定するレース番号。</param>
        /// <returns>現在形式セクションから作成した払戻金モデル一覧。</returns>
        private static List<払戻金モデル> ParseNewPayoutData(IWebElement payoutSection, DateOnly 開催日, string 開催場所, int レース番号)
        {
            Logger.Log("ParseNewPayoutData IN");
            var models = new List<払戻金モデル>();
            try
            {
                string ticketType = string.Empty;
                var rows = payoutSection.FindElements(By.XPath(".//table//tbody/tr"));

                foreach (var row in rows)
                {
                    var cells = row.FindElements(By.TagName("td"));
                    if (cells.Count == 0) continue;

                    var titleCell = cells.FirstOrDefault(c => (c.GetDomAttribute("class") ?? "").Contains("title"));
                    if (titleCell != null && !string.IsNullOrWhiteSpace(titleCell.Text))
                    {
                        ticketType = titleCell.Text.Trim();
                    }

                    var numberCell = cells.FirstOrDefault(c =>
                    {
                        var className = c.GetDomAttribute("class") ?? "";
                        return className.Split(' ', StringSplitOptions.RemoveEmptyEntries).Any(x => x == "a" || x == "d");
                    });
                    var amountCell = cells.FirstOrDefault(c => (c.GetDomAttribute("class") ?? "").Contains("refundMoney"));

                    if (string.IsNullOrWhiteSpace(ticketType) || numberCell == null || amountCell == null)
                    {
                        continue;
                    }

                    models.Add(CreateModel(開催日, 開催場所, レース番号, ticketType, numberCell.Text, amountCell.Text));
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("ParseNewPayoutDataエラー", ex);
            }
            finally
            {
                Logger.Log("ParseNewPayoutData OUT");
            }
            return models;
        }

        /// <summary>
        /// HTTPで取得した現在形式の払戻金HTMLから、払戻金行をモデルへ変換します。
        /// </summary>
        /// <param name="html">解析対象となるHTML文字列またはHTML断片。</param>
        /// <param name="開催日">保存または解析結果へ設定する開催日。</param>
        /// <param name="開催場所">保存または解析結果へ設定する開催場所。</param>
        /// <param name="レース番号">保存または解析結果へ設定するレース番号。</param>
        /// <returns>HTMLから解析できた払戻金モデル一覧。払戻金セクションが見つからない場合は空リスト。</returns>
        private static List<払戻金モデル> ParseNewPayoutDataFromHtml(string html, DateOnly 開催日, string 開催場所, int レース番号)
        {
            Logger.Log("ParseNewPayoutDataFromHtml IN");
            var models = new List<払戻金モデル>();
            try
            {
                var decodedHtml = WebUtility.HtmlDecode(html);
                var sectionMatches = Regex.Matches(decodedHtml, @"<section\b[^>]*class\s*=\s*[""'][^""']*\bnewRefundTable\b[^""']*[""'][^>]*>(?<section>.*?)</section>", RegexOptions.IgnoreCase | RegexOptions.Singleline);
                foreach (Match sectionMatch in sectionMatches)
                {
                    string ticketType = string.Empty;
                    var rows = Regex.Matches(sectionMatch.Groups["section"].Value, @"<tr\b[^>]*>(?<row>.*?)</tr>", RegexOptions.IgnoreCase | RegexOptions.Singleline);
                    foreach (Match row in rows)
                    {
                        var cells = GetHtmlCells(row.Groups["row"].Value);
                        if (cells.Count == 0) continue;

                        var titleCell = cells.FirstOrDefault(c => HasClass(c.ClassName, "title"));
                        if (titleCell != null && !string.IsNullOrWhiteSpace(titleCell.Text))
                        {
                            ticketType = titleCell.Text.Trim();
                        }

                        var numberCell = cells.FirstOrDefault(c => HasClass(c.ClassName, "a") || HasClass(c.ClassName, "d"));
                        var amountCell = cells.FirstOrDefault(c => HasClass(c.ClassName, "refundMoney"));

                        if (string.IsNullOrWhiteSpace(ticketType) || numberCell == null || amountCell == null)
                        {
                            continue;
                        }

                        models.Add(CreateModel(開催日, 開催場所, レース番号, ticketType, numberCell.Text, amountCell.Text));
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("ParseNewPayoutDataFromHtmlエラー", ex);
            }
            finally
            {
                Logger.Log("ParseNewPayoutDataFromHtml OUT");
            }
            return models;
        }

        /// <summary>
        /// 旧形式の払戻金テーブルから、馬券種別、組番、金額を読み取りモデル一覧を作成します。
        /// </summary>
        /// <param name="payoutTable">旧形式の払戻金テーブル要素。</param>
        /// <param name="開催日">保存または解析結果へ設定する開催日。</param>
        /// <param name="開催場所">保存または解析結果へ設定する開催場所。</param>
        /// <param name="レース番号">保存または解析結果へ設定するレース番号。</param>
        /// <returns>旧形式テーブルから作成した払戻金モデル一覧。</returns>
        private static List<払戻金モデル> ParsePayoutData(IWebElement payoutTable, DateOnly 開催日, string 開催場所, int レース番号)
        {
            Logger.Log("ParsePayoutData IN");
            var models = new List<払戻金モデル>();
            try
            {
                var headers = payoutTable.FindElements(By.XPath(".//tr[@class='dbitem'][1]/td"));
                var datas = payoutTable.FindElements(By.XPath(".//tr[@class='dbdata'][1]/td"));

                int dataIndex = 1;
                for (int headerIndex = 1; headerIndex < headers.Count; headerIndex++)
                {
                    var ticketType = headers[headerIndex].Text.Trim();
                    var numberCell = datas[dataIndex];
                    var amountCell = datas[dataIndex + 1];

                    if (numberCell.FindElements(By.XPath("./*")).Count == 0)
                    {
                        models.Add(CreateModel(開催日, 開催場所, レース番号, ticketType, numberCell.Text, amountCell.Text));
                        dataIndex += 3;
                    }
                    else
                    {
                        var numbers = numberCell.Text.Split(Environment.NewLine);
                        var amounts = amountCell.Text.Split(Environment.NewLine);

                        for (int i = 0; i < numbers.Length; i++)
                        {
                            models.Add(CreateModel(開催日, 開催場所, レース番号, ticketType, numbers[i], amounts.ElementAtOrDefault(i) ?? ""));
                        }
                        dataIndex += 3;
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("ParsePayoutDataエラー", ex);
            }
            finally
            {
                Logger.Log("ParsePayoutData OUT");
            }
            return models;
        }

        /// <summary>
        /// 当日払戻金ページ形式の払戻金セクションから、払戻金モデル一覧を作成します。
        /// </summary>
        /// <param name="payoutSection">払戻金情報を含むセクション要素。</param>
        /// <param name="開催日">保存または解析結果へ設定する開催日。</param>
        /// <param name="開催場所">保存または解析結果へ設定する開催場所。</param>
        /// <param name="レース番号">保存または解析結果へ設定するレース番号。</param>
        /// <returns>当日払戻金ページ形式から作成した払戻金モデル一覧。</returns>
        private static List<払戻金モデル> ParseRefundListData(IWebElement payoutSection, DateOnly 開催日, string 開催場所, int レース番号)
        {
            Logger.Log("ParseRefundListData IN");
            var models = new List<払戻金モデル>();
            try
            {
                var wrappers = payoutSection.FindElements(By.CssSelector("div.roundWrapper"));
                IEnumerable<IWebElement> targetWrappers = wrappers.Count > 0 ? wrappers : new[] { payoutSection };

                foreach (var wrapper in targetWrappers)
                {
                    var roundText = wrapper.FindElements(By.CssSelector("p.roundNum")).FirstOrDefault()?.Text ?? string.Empty;
                    if (int.TryParse(Regex.Match(roundText, @"\d+").Value, out var roundNo) && roundNo != レース番号)
                    {
                        continue;
                    }

                    string ticketType = string.Empty;
                    var rows = wrapper.FindElements(By.XPath(".//table[contains(@class,'refund')]//tbody/tr"));

                    foreach (var row in rows)
                    {
                        var ticketCell = row.FindElements(By.XPath(".//th[contains(@class,'ticket')]")).FirstOrDefault();
                        if (ticketCell != null && !string.IsNullOrWhiteSpace(ticketCell.Text))
                        {
                            ticketType = ticketCell.Text.Trim();
                        }

                        var numberCell = row.FindElements(By.XPath(".//td[contains(concat(' ', normalize-space(@class), ' '), ' b ') or contains(concat(' ', normalize-space(@class), ' '), ' f ')]")).FirstOrDefault();
                        var amountCell = row.FindElements(By.XPath(".//td[contains(concat(' ', normalize-space(@class), ' '), ' c ') or contains(concat(' ', normalize-space(@class), ' '), ' g ')]")).FirstOrDefault();

                        if (string.IsNullOrWhiteSpace(ticketType) || numberCell == null || amountCell == null)
                        {
                            continue;
                        }

                        models.Add(CreateModel(開催日, 開催場所, レース番号, ticketType, numberCell.Text, amountCell.Text));
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("ParseRefundListDataエラー", ex);
            }
            finally
            {
                Logger.Log("ParseRefundListData OUT");
            }
            return models;
        }

        /// <summary>
        /// 開催情報、馬券種別、組番、金額テキストをもとに、保存用の払戻金モデルを作成します。
        /// </summary>
        /// <param name="開催日">保存または解析結果へ設定する開催日。</param>
        /// <param name="開催場所">保存または解析結果へ設定する開催場所。</param>
        /// <param name="レース番号">保存または解析結果へ設定するレース番号。</param>
        /// <param name="馬券">単勝、複勝、馬連などの馬券種別。</param>
        /// <param name="組番">払戻対象の馬番または組番。</param>
        /// <param name="金額テキスト">画面から取得した払戻金額の文字列。</param>
        /// <returns>DBへ保存するための払戻金モデル。金額は数値へ変換済み。</returns>
        private static 払戻金モデル CreateModel(DateOnly 開催日, string 開催場所, int レース番号, string 馬券, string 組番, string 金額テキスト)
        {
            var model = new 払戻金モデル
            {
                開催日 = 開催日,
                開催場所 = 開催場所,
                レース番号 = レース番号,
                馬券 = Regex.Replace(馬券, @"\s+", ""),
                組番 = Regex.Replace(組番, @"\s+", ""),
                金額 = int.TryParse(Regex.Replace(金額テキスト, @"[^\d]", ""), out var amount) ? amount : 0
            };
            return model;
        }

        private sealed class HtmlCell
        {
            public string ClassName { get; set; } = string.Empty;
            public string Text { get; set; } = string.Empty;
        }

        /// <summary>
        /// HTMLのtr断片からtdまたはthセルを抽出し、属性と本文を保持する内部セル一覧を作成します。
        /// </summary>
        /// <param name="rowHtml">セルを抽出するHTMLのtr行断片。</param>
        /// <returns>行内から抽出したHtmlCell一覧。セルがない場合は空リスト。</returns>
        private static List<HtmlCell> GetHtmlCells(string rowHtml)
        {
            var cells = new List<HtmlCell>();
            var matches = Regex.Matches(rowHtml, @"<t[dh]\b(?<attrs>[^>]*)>(?<cell>.*?)</t[dh]>", RegexOptions.IgnoreCase | RegexOptions.Singleline);
            foreach (Match match in matches)
            {
                cells.Add(new HtmlCell
                {
                    ClassName = GetClassAttribute(match.Groups["attrs"].Value),
                    Text = GetHtmlText(match.Groups["cell"].Value)
                });
            }

            return cells;
        }

        /// <summary>
        /// HTMLタグの属性文字列からclass属性の値だけを取り出します。
        /// </summary>
        /// <param name="attributes">HTMLタグから切り出した属性文字列。</param>
        /// <returns>class属性に指定されていたクラス名文字列。class属性がない場合は空文字列。</returns>
        private static string GetClassAttribute(string attributes)
        {
            var match = Regex.Match(attributes, @"class\s*=\s*[""'](?<class>[^""']*)[""']", RegexOptions.IgnoreCase);
            return match.Success ? match.Groups["class"].Value : string.Empty;
        }

        /// <summary>
        /// class属性値に指定されたクラス名が単独のクラスとして含まれているか確認します。
        /// </summary>
        /// <param name="className">HTML要素のclass属性値。</param>
        /// <param name="targetClass">含まれているか確認するクラス名。</param>
        /// <returns>targetClassがclass属性に含まれていればtrue、含まれていなければfalse。</returns>
        private static bool HasClass(string className, string targetClass)
        {
            return className.Split(' ', StringSplitOptions.RemoveEmptyEntries)
                            .Any(c => string.Equals(c, targetClass, StringComparison.OrdinalIgnoreCase));
        }

        /// <summary>
        /// HTML断片からタグを取り除き、HTMLエンティティをデコードして表示テキストへ変換します。
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
    }
}
