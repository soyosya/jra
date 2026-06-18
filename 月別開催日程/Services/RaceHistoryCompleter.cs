// 役割: 馬情報ページの競走履歴から、過去の出馬表・競走結果・払戻金を補完します。
// 当日の出馬表だけでは不足する履歴データを、馬単位で広げて取得するためのサービスです。
// 必要な名前空間のusing定義
using Microsoft.EntityFrameworkCore;
using OpenQA.Selenium;
using OpenQA.Selenium.Chrome;
using OpenQA.Selenium.Support.UI;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text.RegularExpressions;
using System.Web;
using 中央競馬.共通.Data;
using 中央競馬.共通.Libraly;
using 中央競馬.共通.Models;

namespace 中央競馬.Services
{
    /// <summary>
    /// 馬情報ページから競走履歴を取得し、履歴上で不足している出馬表・競走結果・払戻金を補完します。
    /// 当日の出馬表だけでは過去成績が不足するため、馬単位でデータを広げるためのサービスです。
    /// </summary>
    public class RaceHistoryCompleter
    {
        /// <summary>
        /// 馬情報ページで期待要素(競走履歴へのナビゲーションボタン)の表示を待つ最大秒数。
        /// </summary>
        private const int HorseInfoWaitSeconds = 15;

        /// <summary>
        /// 開催日、開催場所、レース番号から馬別履歴補完に使用する出馬表URLを生成します。
        /// </summary>
        /// <param name="開催日">保存または解析結果へ設定する開催日。</param>
        /// <param name="開催場所">保存または解析結果へ設定する開催場所。</param>
        /// <param name="レース番号">保存または解析結果へ設定するレース番号。</param>
        /// <returns>指定レースの出馬表ページURL。生成できない場合は空文字列。</returns>
        public static string CreateURL(DateOnly 開催日, string 開催場所, int レース番号)
        {
            Logger.Log($"IN 開催日:{開催日},開催場所:{開催場所},レース番号:{レース番号}");
            try
            {
                string k_raceDate = Uri.EscapeDataString(開催日.ToString("yyyy/MM/dd"));
                string k_babaCode = 場名マスタ.GetByPlace(開催場所);
                return $"https://www.keiba.go.jp/KeibaWeb/TodayRaceInfo/DebaTable?k_raceDate={k_raceDate}&k_raceNo={レース番号}&k_babaCode={k_babaCode}";
            }
            catch (Exception ex)
            {
                Logger.LogError("URL生成中にエラーが発生しました。", ex);
                return string.Empty;
            }
        }

        /// <summary>
        /// 出馬表上の馬情報URLを起点に、馬プロフィールと過去競走履歴を保存します。 既にDBに存在する履歴は自然キーで判定し、未取得分だけを追加取得します。
        /// </summary>
        /// <param name="driver">取得対象ページを操作するSelenium WebDriver。nullを許可するメソッドでは内部で生成します。</param>
        /// <param name="url">取得または解析の対象となるkeiba.go.jpのページURL。</param>
        /// <param name="horse">履歴補完対象の馬名。DB既存データの判定に使用します。</param>
        public static void FetchAndStoreData(IWebDriver? driver, string url, string horse)
        {
            Logger.Log($"IN {horse} {url}");
            try
            {
                if (string.IsNullOrWhiteSpace(url))
                {
                    Logger.Log("競走履歴URLが空のため処理をスキップします。");
                    return;
                }

                driver ??= WebDriverHelper.InitializeDriverAndNavigate(url);
                if (driver == null)
                {
                    Logger.Log($"WebDriverの初期化に失敗したため処理をスキップします: {url}");
                    return;
                }

                driver.Navigate().GoToUrl(url);
                // 待機が3秒だと、ネットワーク遅延やHTTP 429のリトライで馬情報ページの描画が間に合わず
                // 高頻度でタイムアウトしていたため、許容時間を延ばします。
                string xpath = "//a[@class='cNaviBtn']";
                IWebElement? webElement;
                try
                {
                    var wait = new WebDriverWait(driver, TimeSpan.FromSeconds(HorseInfoWaitSeconds));
                    webElement = wait.Until(d =>
                    {
                        var elements = d.FindElements(By.XPath(xpath));
                        return elements.FirstOrDefault(e => e.Displayed);
                    });
                }
                catch (WebDriverTimeoutException)
                {
                    // 期待要素が時間内に現れないのは、未掲載ページや一時的な取得失敗で起こり得る想定内の事象のため、
                    // ERRORではなくスキップ扱いにして次の馬の処理を続けます。
                    Logger.Log($"馬情報ページの読み込みがタイムアウトしたため競走履歴取得をスキップします: {url}");
                    return;
                }

                if (webElement == null)
                {
                    Logger.Log("馬情報URLのリンクが見つからないため競走履歴取得をスキップします。");
                    return;
                }

                if (!ServiceErrorHandling.TryBuildAbsoluteUrl("https://www.keiba.go.jp/", webElement.GetDomAttribute("href"), out var horsePropertyURL, out var horseUrlError))
                {
                    Logger.Log($"馬情報URLを生成できないため競走履歴取得をスキップします: {horseUrlError}");
                    return;
                }

                馬情報.FetchAndStoreData(driver, horsePropertyURL);
                xpath = "//table[@class='HorseMarkInfo_table']/tbody/tr";
                var RaceResultHistory = new List<(string resultUrl, DateOnly raceDate, string venue, int raceNo, string racetableUrl)>();
                foreach (var tr in driver.FindElements(By.XPath(xpath)))
                {
                    try
                    {
                        var resultHref = tr.FindElements(By.XPath("td[4]/a")).FirstOrDefault()?.GetAttribute("href");
                        if (!ServiceErrorHandling.TryBuildAbsoluteUrl(url, resultHref, out var resultUrl, out var resultUrlError))
                        {
                            Logger.Log($"競走履歴の成績URLを生成できないため行をスキップします: {resultUrlError}");
                            continue;
                        }

                        if (!ServiceErrorHandling.TryGetText(tr, By.XPath("td[1]"), out var raceDateText) ||
                            !DateOnly.TryParse(raceDateText, out var raceDate))
                        {
                            Logger.Log($"競走履歴の日付を取得できないため行をスキップします: {raceDateText}");
                            continue;
                        }

                        var venue = ServiceErrorHandling.FirstElement(tr, By.XPath("td[2]"))?.Text.Trim() ?? string.Empty;
                        venue = venue == "帯広" ? "帯広ば" : venue;
                        var raceNo = ServiceErrorHandling.ParseInt(ServiceErrorHandling.FirstElement(tr, By.XPath("td[3]"))?.Text);
                        var racetableUrl = resultUrl.Replace("RaceMarkTable", "DebaTable");
                        RaceResultHistory.Add((resultUrl, raceDate, venue, raceNo, racetableUrl));
                    }
                    catch (Exception ex)
                    {
                        Logger.LogError("競走履歴行の解析中にエラーが発生しました。", ex);
                    }
                }

                if (RaceResultHistory.Count == 0)
                {
                    Logger.Log($"競走履歴が取得できませんでした: {url}");
                    return;
                }

                using var context = new DBContext();
                const string binaryCollation = "Japanese_Bin";
                var raceDates = RaceResultHistory.Select(r => r.raceDate).Distinct().ToList();
                var raceVenues = RaceResultHistory.Select(r => r.venue).Distinct().ToList();

                var existingRaceInfo = context.レース情報.Where(h =>
                    EF.Functions.Collate(h.馬名, binaryCollation) == horse &&
                    raceVenues.Contains(h.開催場所) &&
                    raceDates.Contains(h.開催日)
                ).ToList();

                var existingRaceResult = context.競走結果.Where(h =>
                    EF.Functions.Collate(h.馬名, binaryCollation) == horse &&
                    raceVenues.Contains(h.開催場所) &&
                    raceDates.Contains(h.開催日)
                ).ToList();

                var existingPayout = context.払戻金.Where(h =>
                    raceVenues.Contains(h.開催場所) &&
                    raceDates.Contains(h.開催日)
                ).ToList();

                var raceInfoKeys = new HashSet<(string 馬名, string 開催場所, DateOnly 開催日)>(existingRaceInfo.Select(h => (h.馬名, h.開催場所, h.開催日)));
                var raceResultKeys = new HashSet<(string 馬名, string 開催場所, DateOnly 開催日)>(existingRaceResult.Select(h => (h.馬名, h.開催場所, h.開催日)));
                var payoutKeys = new HashSet<(string 開催場所, DateOnly 開催日)>(existingPayout.Select(h => (h.開催場所, h.開催日)));

                foreach (var race in RaceResultHistory)
                {
                    if (!raceInfoKeys.Contains((horse, race.venue, race.raceDate)))
                        レース情報.FetchAndStoreData(driver, race.racetableUrl);

                    if (!raceResultKeys.Contains((horse, race.venue, race.raceDate)))
                        競走結果.FetchAndStoreData(driver, race.resultUrl);

                    if (!payoutKeys.Contains((race.venue, race.raceDate)))
                        払戻金.FetchAndStoreData(driver, race.resultUrl);
                }
            }
            catch (Exception ex)
            {
                Logger.LogError($"競走履歴取得時にエラー発生 URL:{driver?.Url}", ex);
            }
        }
    }
}
