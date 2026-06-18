// 役割: 当日メニューに保存された出馬表URLから、出走馬ごとのレース情報を取得します。
// 馬名、騎手、調教師、馬情報URLなどを保存し、馬情報や馬別履歴補完へつなげます。
// 出馬表ページは複数行で1頭を表すため、行の状態を保持しながら解析します。
using System; // 基本的なシステム機能を提供する名前空間
using System.Linq; // LINQ 機能を提供する名前空間
using OpenQA.Selenium; // Selenium WebDriver の基本機能を提供する名前空間
using OpenQA.Selenium.Chrome; // Chrome ブラウザ用の Selenium WebDriver を提供する名前空間
using Microsoft.EntityFrameworkCore; // Entity Framework Core のデータベース操作をサポートする名前空間
using System.Web; // URL クエリ パラメータの操作を提供する名前空間
using 中央競馬.共通.Libraly; // ログ機能を提供するカスタムクラスの名前空間
using 中央競馬.共通.Data; // DB を使用する名前空間
using 中央競馬.共通.Models; // データベースモデルを使用する名前空間
using System.Text.RegularExpressions;
using Microsoft.Extensions.Configuration;
using System.IO;
using System.Diagnostics;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

namespace 中央競馬.Services
{
    /// <summary>
    /// レース情報のデータ取得と保存を行うバッチ処理クラス。
    /// </summary>
    public class レース情報
    {
        /// <summary>
        /// データ取得処理のエントリーポイント。
        /// </summary>
        /// <param name="args">サービス単体実行時に渡されるコマンドライン引数。固定URLの確認処理では参照しない場合があります。</param>
        public static void 取得(string[] args)
        {
            Logger.Log("バッチ処理を開始しました。");

            try
            {
                string url = "https://www.keiba.go.jp/KeibaWeb/TodayRaceInfo/DebaTable?k_raceDate=2025%2f01%2f01&k_raceNo=1&k_babaCode=21";
                FetchAndStoreData(null, url);
            }
            catch (Exception ex)
            {
                Logger.LogError("バッチ処理中にエラーが発生しました。", ex);
            }
            finally
            {
                Logger.Log("バッチ処理を終了しました。");
            }
        }
        /// <summary>
        /// 開催日、開催場所、レース番号からkeiba.go.jpの出馬表URLを生成します。
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

                string k_raceDate = Uri.EscapeDataString(開催日.ToString());
                // 場名を取得する
                string k_babaCode = 場名マスタ.GetByPlace(開催場所);

                return ($"https://www.keiba.go.jp/KeibaWeb/TodayRaceInfo/DebaTable?k_raceDate={k_raceDate}&k_raceNo={レース番号}&k_babaCode={k_babaCode}");
            }
            catch (Exception ex)
            {
                Logger.LogError("バッチ処理中にエラーが発生しました。", ex);
                return string.Empty;
            }
            finally
            {
                Logger.Log("処理を終了しました。");
            }
        }

        /// <summary>
        /// 出馬表を取得してデータベースに保存します。
        /// </summary>
        /// <param name="driver">取得対象ページを操作するSelenium WebDriver。nullを許可するメソッドでは内部で生成します。</param>
        /// <param name="url">取得または解析の対象となるkeiba.go.jpのページURL。</param>
        public static void FetchAndStoreData(IWebDriver? driver, string url)
        {
            Logger.Log($"IN url:{url}");
            try
            {
                //                url = "https://www.keiba.go.jp/KeibaWeb/TodayRaceInfo/DebaTable?k_raceDate=2015%2f04%2f25&k_raceNo=11&k_babaCode=11";
                if (string.IsNullOrWhiteSpace(url))
                {
                    Logger.Log("レース情報URLが空のため処理をスキップします。");
                    return;
                }

                if (driver == null)
                {
                    driver = WebDriverHelper.InitializeDriverAndNavigate(url);
                }
                if (driver == null)
                {
                    Logger.Log($"WebDriverの初期化に失敗したため処理をスキップします: {url}");
                    return;
                }

                if (driver.Url != url)
                {
                    driver.Navigate().GoToUrl(url);
                }

                レース情報モデル raceInfo = new();
                if (!ServiceErrorHandling.TryReadRaceQuery(url, out var 開催日, out var 開催場所, out var レース番号, out var queryError))
                {
                    Logger.Log($"レース情報URLのクエリが不正なため処理をスキップします: {queryError}");
                    return;
                }

                raceInfo.開催日 = 開催日;
                raceInfo.開催場所 = 開催場所;
                raceInfo.レース番号 = レース番号;
                //                Logger.Log($"{raceInfo.開催日} {raceInfo.開催場所} {raceInfo.レース番号}R");
                string xpath = "//article[@class='raceCard']/div[@class='innerWrapper']/h4";
                IWebElement webElement;
                try
                {
                    webElement = ServiceErrorHandling.FirstElement(driver, By.XPath(xpath)) ?? throw new NoSuchElementException(xpath);
                }
                catch (Exception ex)
                {
                    Logger.LogError($"レース情報　レース情報ページが表示されない: {url}", ex);
                    return;
                }
                string 発走時刻txt = Regex.Match(webElement.Text, @"\d+:\d+").Value;
                DateTime 発走時刻;
                if (!DateTime.TryParse($"{raceInfo.開催日.ToString("yyyy/MM/dd")} {発走時刻txt}:00", out 発走時刻))
                {
                    発走時刻 = new DateTime(1900, 1, 1, 0, 0, 0);
                }
                raceInfo.発走時刻 = 発走時刻;
                xpath = "//section[@class='raceTitle']/p[@class='roundInfo']";
                webElement = ServiceErrorHandling.FirstElement(driver, By.XPath(xpath)) ?? throw new NoSuchElementException(xpath);
                string roundInfo = webElement.Text.Trim();
                xpath = "//section[@class='raceTitle']/p[@class='date']";
                webElement = ServiceErrorHandling.FirstElement(driver, By.XPath(xpath)) ?? throw new NoSuchElementException(xpath);
                string date = webElement.Text.Trim();
                xpath = "//section[@class='raceTitle']/p[@class='subTitle']";
                webElement = ServiceErrorHandling.FirstElement(driver, By.XPath(xpath)) ?? throw new NoSuchElementException(xpath);
                string subTitle = webElement.Text.Trim();
                xpath = "//section[@class='raceTitle']/h3";
                webElement = ServiceErrorHandling.FirstElement(driver, By.XPath(xpath)) ?? throw new NoSuchElementException(xpath);
                string h3 = webElement.Text.Trim();
                raceInfo.競走名 = $"{roundInfo}{date}{subTitle}{h3}";

                xpath = "//ul[@class='dataArea']";
                webElement = ServiceErrorHandling.FirstElement(driver, By.XPath(xpath)) ?? throw new NoSuchElementException(xpath);
                if (Regex.Match(webElement.Text.Trim(), "ダート|芝").Value.Equals("ダート"))
                {
                    raceInfo.コース種別 = "ダ";
                }
                else
                {
                    raceInfo.コース種別 = "芝";
                }
                int 距離;
                if (Int32.TryParse(Regex.Match(webElement.Text.Trim(), @"\d+(?=ｍ)").Value, out 距離))
                {
                    raceInfo.距離 = 距離;
                }
                raceInfo.周回方向 = Regex.Match(webElement.Text.Trim(), "右|左").Value;
                raceInfo.天候 = Regex.Match(webElement.Text.Trim(), @"(?<=天候：).*?　").Value.Trim();
                raceInfo.馬場 = Regex.Match(webElement.Text.Trim(), @"(?<=馬場：).*?　").Value.Trim();
                raceInfo.条件 = Regex.Match(webElement.Text.Trim(), $"(?<={raceInfo.馬場}).*?(?=＊電話投票コード)").Value.Trim();
                int 賞金;
                if (Int32.TryParse(Regex.Match(webElement.Text.Trim(), @"(?<=賞金.+1着).*?円").Value.Replace(",", "").Replace("円", ""), out 賞金))
                {
                    raceInfo.一着賞金 = 賞金;
                }
                else
                {
                    raceInfo.一着賞金 = 0;
                }
                if (Int32.TryParse(Regex.Match(webElement.Text.Trim(), @"(?<=賞金.+2着).*?円").Value.Replace(",", "").Replace("円", ""), out 賞金))
                {
                    raceInfo.二着賞金 = 賞金;
                }
                else
                {
                    raceInfo.二着賞金 = 0;
                }
                if (Int32.TryParse(Regex.Match(webElement.Text.Trim(), @"(?<=賞金.+3着).*?円").Value.Replace(",", "").Replace("円", ""), out 賞金))
                {
                    raceInfo.三着賞金 = 賞金;
                }
                else
                {
                    raceInfo.三着賞金 = 0;
                }
                if (Int32.TryParse(Regex.Match(webElement.Text.Trim(), @"(?<=賞金.+4着).*?円").Value.Replace(",", "").Replace("円", ""), out 賞金))
                {
                    raceInfo.四着賞金 = 賞金;
                }
                else
                {
                    raceInfo.四着賞金 = 0;
                }
                if (Int32.TryParse(Regex.Match(webElement.Text.Trim(), @"(?<=賞金.+5着).*?円").Value.Replace(",", "").Replace("円", ""), out 賞金))
                {
                    raceInfo.五着賞金 = 賞金;
                }
                else
                {
                    raceInfo.五着賞金 = 0;
                }
                // 出馬表取得
                int rowspanCounter = 0;
                int adjustIndex = 0;
                int rowspan = 0;
                int rowCount = 0; //出走馬情報を5行読み取って保存
                bool rowRetrievedFlag = false;
                int 枠番 = 0;
                xpath = "//section[@class='cardTable']/table[1]/tbody/tr[position() > 2]";
                var RacingProgram = driver.FindElements(By.XPath(xpath));
                using var context = new DBContext();
                レース情報モデル racingProgram = new レース情報モデル()
                {
                    開催日 = raceInfo.開催日,
                    開催場所 = raceInfo.開催場所,
                    レース番号 = raceInfo.レース番号,
                    発走時刻 = raceInfo.発走時刻,
                    コース種別 = raceInfo.コース種別,
                    一着賞金 = raceInfo.一着賞金,
                    二着賞金 = raceInfo.二着賞金,
                    三着賞金 = raceInfo.三着賞金,
                    四着賞金 = raceInfo.四着賞金,
                    五着賞金 = raceInfo.五着賞金,
                    周回方向 = raceInfo.周回方向,
                    天候 = raceInfo.天候,
                    競走名 = raceInfo.競走名,
                    条件 = raceInfo.条件,
                    馬場 = raceInfo.馬場,
                    距離 = raceInfo.距離
                };

                foreach (var row in RacingProgram)
                {
                    try
                    {
                        xpath = "td";
                        var webElements = row.FindElements(By.XPath(xpath));
                        if (webElements.Count == 0)
                        {
                            continue;
                        }

                        bool isClass_tBorder = row.GetDomAttribute("class") == "tBorder";
                        if (isClass_tBorder)
                        {
                            /*
                             * 1頭分の情報を読み取っていれば保存する
                             */

                            if (rowRetrievedFlag)
                            {
                                var existingData = context.レース情報.FirstOrDefault(h => h.開催日 == racingProgram.開催日 && h.開催場所 == racingProgram.開催場所 && h.レース番号 == racingProgram.レース番号 && h.馬名 == racingProgram.馬名);
                                if (existingData != null)
                                {
                                    Logger.Log($"レース情報　既存データを削除: 開催日={existingData.開催日}, 開催場所={existingData.開催場所}, レース番号={existingData.レース番号}, 馬番={existingData.馬番}, 馬名={existingData.馬名}");
                                    context.レース情報.Remove(existingData);
                                }
                                context.レース情報.Add(racingProgram);
                                context.SaveChanges();
                                racingProgram = new レース情報モデル()
                                {
                                    開催日 = raceInfo.開催日,
                                    開催場所 = raceInfo.開催場所,
                                    レース番号 = raceInfo.レース番号,
                                    発走時刻 = raceInfo.発走時刻,
                                    コース種別 = raceInfo.コース種別,
                                    一着賞金 = raceInfo.一着賞金,
                                    二着賞金 = raceInfo.二着賞金,
                                    三着賞金 = raceInfo.三着賞金,
                                    四着賞金 = raceInfo.四着賞金,
                                    五着賞金 = raceInfo.五着賞金,
                                    周回方向 = raceInfo.周回方向,
                                    天候 = raceInfo.天候,
                                    競走名 = raceInfo.競走名,
                                    条件 = raceInfo.条件,
                                    馬場 = raceInfo.馬場,
                                    距離 = raceInfo.距離
                                };
                            }
                            /*
                             * 枠番が結合されていると配列の要素数が変わるので配慮する
                             */
                            rowCount = 1;
                            rowRetrievedFlag = false;
                            xpath = "td";
                            webElements = row.FindElements(By.XPath(xpath));
                            if (webElements[0].GetDomAttribute("class")!.IndexOf("course") >= 0)
                            {
                                if (rowspanCounter > 0)
                                {
                                    adjustIndex = -1;
                                    racingProgram.枠番 = 枠番;
                                    rowspanCounter--;
                                }
                                else
                                {
                                    Int32.TryParse(webElements[0].GetDomAttribute("rowspan"), out rowspan);
                                    rowspanCounter = rowspan / 5; //枠番の結合が何頭分あるか計算する。1頭の情報は5行使われている。
                                    adjustIndex = 0;
                                    if (Int32.TryParse(webElements[0].Text.ToString(), out 枠番))
                                    {
                                        racingProgram.枠番 = 枠番;
                                    }
                                    adjustIndex = 0;
                                }
                            }
                            else
                            {
                                adjustIndex = -1;
                                racingProgram.枠番 = 枠番;
                                rowspanCounter--;
                            }
                            int 馬番;
                            if (Int32.TryParse(webElements[1 + adjustIndex].Text.ToString(), out 馬番))
                            {
                                racingProgram.馬番 = 馬番;
                            }
                            var horseLink = ServiceErrorHandling.FirstElement(webElements[2 + adjustIndex], By.XPath("a"));
                            if (horseLink == null)
                            {
                                Logger.Log("馬情報リンクが見つからないため行をスキップします。");
                                continue;
                            }

                            racingProgram.馬名 = horseLink.Text.Trim();
                            if (ServiceErrorHandling.TryBuildAbsoluteUrl(url, horseLink.GetDomAttribute("href"), out var horseUrl, out var horseUrlError))
                            {
                                racingProgram.馬情報URL = horseUrl;
                            }
                            else
                            {
                                Logger.Log($"馬情報URLを生成できませんでした: {horseUrlError}");
                            }

                            var jockeyLink = ServiceErrorHandling.FirstElement(webElements[3 + adjustIndex], By.XPath("a"));
                            if (jockeyLink != null)
                            {
                                if (ServiceErrorHandling.TryBuildAbsoluteUrl(url, jockeyLink.GetDomAttribute("href"), out var jockeyUrl, out var jockeyUrlError))
                                {
                                    racingProgram.騎手情報URL = jockeyUrl;
                                }
                                else
                                {
                                    Logger.Log($"騎手情報URLを生成できませんでした: {jockeyUrlError}");
                                }
                            }
                            racingProgram.騎手所属 = ServiceErrorHandling.FirstElement(webElements[3 + adjustIndex], By.XPath("a/span[@class='jockeyarea']"))?.Text.Trim().Replace("（", "").Replace("）", "") ?? string.Empty;
                            racingProgram.騎手 = ServiceErrorHandling.FirstElement(webElements[3 + adjustIndex], By.XPath("a[@class='jockeyName']"))?.Text.Trim().Replace($"（{racingProgram.騎手所属}）", "") ?? string.Empty;
                        }
                        else
                        {
                            rowCount++;
                            if (rowCount == 2)
                            {
                                racingProgram.性別 = Regex.Match(webElements[0].Text, "牝|セ|牡").Value;
                                int 馬齢;
                                if (
                                    Int32.TryParse(Regex.Match(webElements[0].Text, @"\d+").Value, out 馬齢)
                                )
                                {
                                    racingProgram.馬齢 = 馬齢;
                                }
                                racingProgram.毛色 = webElements.Count > 1 ? webElements[1].Text.Trim() : string.Empty;

                                string[] TDtxt = webElements.Count > 3 ? webElements[3].Text.Replace("　", " ").Split(" ") : Array.Empty<string>();
                                float 斤量;
                                string 斤量txt = string.Empty;
                                if (TDtxt.Length == 2)
                                {
                                    斤量txt = TDtxt[0];
                                }
                                else if (TDtxt.Length > 1)
                                {
                                    racingProgram.減量記号 = TDtxt[0].Trim();
                                    斤量txt = TDtxt[1];
                                }
                                if (float.TryParse(斤量txt, out 斤量))
                                {
                                    racingProgram.斤量 = 斤量;
                                }
                            }
                            else if (rowCount == 3)
                            {
                                var trainerLink = webElements.Count > 1 ? ServiceErrorHandling.FirstElement(webElements[1], By.XPath("a")) : null;
                                if (trainerLink != null)
                                {
                                    string[] 調教師txt = trainerLink.Text.Trim().Split("（");
                                    racingProgram.調教師 = 調教師txt.ElementAtOrDefault(0) ?? string.Empty;
                                    racingProgram.調教師所属 = (調教師txt.ElementAtOrDefault(1) ?? string.Empty).Replace("）", "");
                                    if (ServiceErrorHandling.TryBuildAbsoluteUrl(url, trainerLink.GetDomAttribute("href"), out var trainerUrl, out var trainerUrlError))
                                    {
                                        racingProgram.調教師情報URL = trainerUrl;
                                    }
                                    else
                                    {
                                        Logger.Log($"調教師情報URLを生成できませんでした: {trainerUrlError}");
                                    }
                                }

                                string[] TDtxt = webElements.Count > 2 ? webElements[2].Text.Split($"{Environment.NewLine}") : Array.Empty<string>();
                                int 馬体重;
                                int 増減;
                                if (TDtxt.Length == 1)
                                {
                                    if (Int32.TryParse(TDtxt[0], out 馬体重))
                                    {
                                        racingProgram.馬体重 = 馬体重;
                                    }
                                }
                                else if (TDtxt.Length == 2)
                                {
                                    if (Int32.TryParse(TDtxt[0], out 馬体重))
                                    {
                                        racingProgram.馬体重 = 馬体重;
                                    }
                                    if (Int32.TryParse(TDtxt[1].Replace("(", "").Replace(")", ""), out 増減))
                                    {
                                        racingProgram.馬体重増減 = 増減;
                                    }
                                }
                            }
                            else if (rowCount == 4)
                            {
                                racingProgram.馬主 = webElements.Count > 1 ? webElements[1].Text.Trim() : string.Empty;
                                rowRetrievedFlag = true;
                                if (rowspanCounter > 0) rowspanCounter--;
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        rowRetrievedFlag = false;
                        Logger.LogError($"レース情報行の解析中にエラーが発生しました。URL:{url}", ex);
                    }
                }
                if (rowRetrievedFlag)
                {
                    var existingData = context.レース情報.FirstOrDefault(h => h.開催日 == racingProgram.開催日 && h.開催場所 == racingProgram.開催場所 && h.レース番号 == racingProgram.レース番号 && h.馬名 == racingProgram.馬名);
                    if (existingData != null)
                    {
                        Logger.Log($"出馬表 既存データを削除: 開催日={existingData.開催日}, 開催場所={existingData.開催場所}, レース番号={existingData.レース番号}, 馬番={existingData.馬番}, 馬名={existingData.馬名}");
                        context.レース情報.Remove(existingData);
                    }
                    context.レース情報.Add(racingProgram);
                    context.SaveChanges();
                }
                Logger.Log("当日メニューデータの保存に成功しました。");
            }
            catch (Exception ex)
            {
                Logger.LogError($"レース情報　レース情報 データベースエラーが発生しました。{Environment.NewLine}{url}", ex);
            }
            finally
            {
                Logger.Log("OUT 終了しました。");
            }
        }
    }
}
