// 役割: 開催情報の当日メニューURLを開き、開催日・開催場所ごとのレース一覧を保存します。
// 出馬表URLと成績URLもここで保存し、レース情報・競走結果・払戻金取得の入口を作ります。
// 変更情報テーブルも同じページから取得します。
using System;
using System.Linq;
using System.Text.RegularExpressions;
using System.Web;
using OpenQA.Selenium;
using Microsoft.EntityFrameworkCore;
using 中央競馬.共通.Libraly;
using 中央競馬.共通.Data;
using 中央競馬.共通.Models;

namespace 中央競馬.Services
{
    public class 当日メニュー
    {
        /// <summary>
        /// 当日メニュー取得エントリーポイント
        /// </summary>
        /// <param name="args">サービス単体実行時に渡されるコマンドライン引数。固定URLの確認処理では参照しない場合があります。</param>
        public static void 取得(string[] args)
        {
            Logger.Log("取得 IN");
            try
            {
                FetchAndStoreData(null, "https://www.keiba.go.jp/KeibaWeb/TodayRaceInfo/RaceList?k_raceDate=2025%2f01%2f01&k_babaCode=21");
            }
            catch (Exception ex)
            {
                Logger.LogError("当日メニュー取得中にエラーが発生しました。", ex);
            }
            finally
            {
                Logger.Log("取得 OUT");
            }
        }

        /// <summary>
        /// 当日メニューと変更情報を取得・保存
        /// </summary>
        /// <param name="driver">取得対象ページを操作するSelenium WebDriver。nullを許可するメソッドでは内部で生成します。</param>
        /// <param name="url">取得または解析の対象となるkeiba.go.jpのページURL。</param>
        public static void FetchAndStoreData(IWebDriver? driver, string url)
        {
            Logger.Log("FetchAndStoreData IN");
            try
            {
                if (string.IsNullOrWhiteSpace(url))
                {
                    Logger.Log("当日メニューURLが空のため処理をスキップします。");
                    return;
                }

                driver ??= WebDriverHelper.InitializeDriverAndNavigate(url);
                if (driver == null)
                {
                    Logger.Log($"WebDriverの初期化に失敗したため処理をスキップします: {url}");
                    return;
                }

                driver.Navigate().GoToUrl(url);

                if (!ServiceErrorHandling.TryReadRaceDateAndCourse(url, out var 開催日, out var 開催場所, out var queryError))
                {
                    Logger.Log($"当日メニューURLのクエリが不正なため処理をスキップします: {queryError}");
                    return;
                }

                SaveRaceMenu(driver, url, 開催日, 開催場所);
                SaveChangeInfo(driver, 開催日, 開催場所);
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
        /// レースメニューを解析しDB保存
        /// </summary>
        /// <param name="driver">取得対象ページを操作するSelenium WebDriver。nullを許可するメソッドでは内部で生成します。</param>
        /// <param name="url">取得または解析の対象となるkeiba.go.jpのページURL。</param>
        /// <param name="開催日">保存または解析結果へ設定する開催日。</param>
        /// <param name="開催場所">保存または解析結果へ設定する開催場所。</param>
        private static void SaveRaceMenu(IWebDriver driver, string url, DateOnly 開催日, string 開催場所)
        {
            Logger.Log("SaveRaceMenu IN");
            try
            {
                string xpath = "//section[@class='raceTable']/table[1]/tbody/tr[@class='data']";
                var raceTable = driver.FindElements(By.XPath(xpath));

                using var context = new DBContext();
                foreach (var row in raceTable)
                {
                    var cells = row.FindElements(By.TagName("td"));
                    if (cells.Count < 10)
                    {
                        Logger.Log($"当日メニュー行の列数が不足しているためスキップします: 列数={cells.Count}");
                        continue;
                    }

                    var race = new 当日メニューモデル
                    {
                        開催日 = 開催日,
                        開催場所 = 開催場所,
                        レース番号 = int.TryParse(Regex.Replace(cells[0].Text, "R", ""), out var no) ? no : 0,
                        発走時刻 = DateTime.TryParse($"{開催日:yyyy/MM/dd} {cells[1].Text}:00", out var 発走) ? 発走 : DateTime.MinValue,
                        変更 = cells[2].Text.Trim(),
                        競走種類 = cells[3].Text.Trim(),
                        周回方向 = Regex.Match(cells[5].Text, "右|左").Value,
                        距離 = int.TryParse(Regex.Match(cells[5].Text, @"\d+").Value, out var dist) ? dist : 0,
                        天候 = cells[6].Text.Trim(),
                        馬場 = cells[7].Text.Trim(),
                        頭数 = int.TryParse(cells[8].Text, out var horses) ? horses : 0
                    };

                    var link = cells[4].FindElements(By.TagName("a")).FirstOrDefault();
                    race.競走名 = link != null ? link.Text.Trim() : cells[4].Text.Trim();
                    if (link != null)
                    {
                        if (ServiceErrorHandling.TryBuildAbsoluteUrl(url, link.GetDomAttribute("href"), out var debaUrl, out var debaUrlError))
                        {
                            race.出馬表URL = debaUrl;
                        }
                        else
                        {
                            Logger.Log($"出馬表URLを生成できませんでした: {debaUrlError}");
                        }
                    }

                    var resultLink = cells[9].FindElements(By.XPath("a[text()='成績' and @href]")).FirstOrDefault();
                    if (resultLink != null)
                    {
                        if (ServiceErrorHandling.TryBuildAbsoluteUrl(url, resultLink.GetDomAttribute("href"), out var resultUrl, out var resultUrlError))
                        {
                            race.成績URL = resultUrl;
                        }
                        else
                        {
                            Logger.Log($"成績URLを生成できませんでした: {resultUrlError}");
                        }
                    }

                    var existing = context.当日メニュー.FirstOrDefault(h => h.開催日 == race.開催日 && h.開催場所 == race.開催場所 && h.レース番号 == race.レース番号);
                    if (existing != null) context.当日メニュー.Remove(existing);
                    context.当日メニュー.Add(race);
                }
                context.SaveChanges();
            }
            catch (Exception ex)
            {
                Logger.LogError("SaveRaceMenuエラー", ex);
            }
            finally
            {
                Logger.Log("SaveRaceMenu OUT");
            }
        }

        /// <summary>
        /// 変更情報を解析しDB保存
        /// </summary>
        /// <param name="driver">取得対象ページを操作するSelenium WebDriver。nullを許可するメソッドでは内部で生成します。</param>
        /// <param name="開催日">保存または解析結果へ設定する開催日。</param>
        /// <param name="開催場所">保存または解析結果へ設定する開催場所。</param>
        private static void SaveChangeInfo(IWebDriver driver, DateOnly 開催日, string 開催場所)
        {
            Logger.Log("SaveChangeInfo IN");
            try
            {
                string xpath = "//table[@class='changeInfo']//tr[@class='data']";
                var changeTable = driver.FindElements(By.XPath(xpath));

                using var context = new DBContext();
                foreach (var row in changeTable)
                {
                    var cells = row.FindElements(By.TagName("td"));
                    if (cells.Count < 5)
                    {
                        Logger.Log($"変更情報行の列数が不足しているためスキップします: 列数={cells.Count}");
                        continue;
                    }

                    var changeInfo = new 変更情報モデル
                    {
                        開催日 = 開催日,
                        開催場所 = 開催場所,
                        レース番号 = int.TryParse(Regex.Replace(cells[0].Text, "R", ""), out var no) ? no : 0,
                        馬番 = int.TryParse(cells[1].Text.Trim(), out var horseNo) ? horseNo : 0,
                        馬名 = cells[2].Text.Trim(),
                        変更内容 = cells[3].Text.Trim(),
                        変更区分 = cells[4].Text.Trim()
                    };

                    var existing = context.変更情報.FirstOrDefault(h => h.開催日 == changeInfo.開催日 && h.開催場所 == changeInfo.開催場所 && h.レース番号 == changeInfo.レース番号 && h.馬番 == changeInfo.馬番);
                    if (existing != null) context.変更情報.Remove(existing);
                    context.変更情報.Add(changeInfo);
                }
                context.SaveChanges();
            }
            catch (Exception ex)
            {
                Logger.LogError("SaveChangeInfoエラー", ex);
            }
            finally
            {
                Logger.Log("SaveChangeInfo OUT");
            }
        }
    }
}
