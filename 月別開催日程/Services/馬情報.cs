// 役割: 馬情報URLから競走馬プロフィールを取得して馬情報テーブルへ保存します。
// 馬名だけでは重複する可能性があるため、馬名と調教師を組み合わせて既存データを検索します。
// 血統、賞金、馬主、生産牧場など、出馬表だけでは取れない情報を補完します。
// using定義（必要な名前空間のみ残す）
using Microsoft.EntityFrameworkCore;
using OpenQA.Selenium;
using OpenQA.Selenium.Support.UI;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Web;
using 中央競馬.共通.Data;
using 中央競馬.共通.Libraly;
using 中央競馬.共通.Models;

namespace 中央競馬.Services
{
    public class 馬情報
    {
        /// <summary>
        /// エントリーポイント
        /// </summary>
        /// <param name="args">サービス単体実行時に渡されるコマンドライン引数。固定URLの確認処理では参照しない場合があります。</param>
        public static void 取得(string[] args)
        {
            Logger.Log("取得 IN");
            try
            {
                FetchAndStoreData(null, "https://www.keiba.go.jp/KeibaWeb/DataRoom/RaceHorseInfo?k_lineageLoginCode=30024400286&k_activeCode=1");
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
        /// 指定された取得元からデータを読み取り、DBへ保存します。
        /// </summary>
        /// <param name="driver">取得対象ページを操作するSelenium WebDriver。nullを許可するメソッドでは内部で生成します。</param>
        /// <param name="url">取得または解析の対象となるkeiba.go.jpのページURL。</param>
        public static void FetchAndStoreData(IWebDriver? driver, string url)
        {
            Logger.Log($"IN {url}");
            馬情報モデル HorseModel = new 馬情報モデル();
            try
            {
                if (string.IsNullOrWhiteSpace(url))
                {
                    Logger.Log("馬情報URLが空のため処理をスキップします。");
                    return;
                }

                driver ??= WebDriverHelper.InitializeDriverAndNavigate(url);
                if (driver == null)
                {
                    Logger.Log($"WebDriverの初期化に失敗したため処理をスキップします: {url}");
                    return;
                }

                driver.Navigate().GoToUrl(url);
                var nameElement = ServiceErrorHandling.WaitForFirstElement(driver, By.XPath("//h4[@class='odd_title']"), TimeSpan.FromSeconds(3));
                if (nameElement == null)
                {
                    Logger.Log($"馬名が取得できないため処理をスキップします: {url}");
                    return;
                }
                HorseModel.馬名 = nameElement.Text.Trim();

                var sexElement = ServiceErrorHandling.WaitForFirstElement(driver, By.XPath("//span[@class='sex ']"), TimeSpan.FromSeconds(3));
                if (sexElement == null)
                {
                    Logger.Log($"性別が取得できないため処理をスキップします: {url}");
                    return;
                }
                HorseModel.性別 = sexElement.Text.Trim();

                var webElements = ServiceErrorHandling.WaitForElements(driver, By.XPath("//table[@class='horse_info_table']/tbody/tr"), TimeSpan.FromSeconds(3));
                if (webElements.Count < 3)
                {
                    Logger.Log($"馬情報テーブルの行数が不足しているため処理をスキップします: 行数={webElements.Count}, URL={url}");
                    return;
                }

                var birthdayText = ServiceErrorHandling.FirstElement(webElements[0], By.XPath("td[2]"))?.Text.Trim().Replace(".", "-").Replace("生", "") ?? string.Empty;
                if (!DateOnly.TryParse(birthdayText, out var birthday))
                {
                    Logger.Log($"生年月日を解析できないため処理をスキップします: {birthdayText}, URL={url}");
                    return;
                }

                HorseModel.生年月日 = birthday;
                string 調教師 = ServiceErrorHandling.Compact(ServiceErrorHandling.FirstElement(webElements[0], By.XPath("td[4]"))?.Text);
                HorseModel.調教師 = Regex.Match(調教師, @"^(.*?)(?=（)").Value;
                HorseModel.所属 = Regex.Match(調教師, @"(?<=（).*?(?=）)").Value;
                HorseModel.地方収得賞金 = ServiceErrorHandling.ParseInt(ServiceErrorHandling.FirstElement(webElements[0], By.XPath("td[6]"))?.Text);
                HorseModel.毛色 = ServiceErrorHandling.FirstElement(webElements[1], By.XPath("td[2]"))?.Text.Trim() ?? string.Empty;
                HorseModel.馬主 = ServiceErrorHandling.Compact(ServiceErrorHandling.FirstElement(webElements[1], By.XPath("td[4]"))?.Text);
                HorseModel.中央収得賞金 = ServiceErrorHandling.ParseInt(ServiceErrorHandling.FirstElement(webElements[1], By.XPath("td[6]"))?.Text);
                HorseModel.産地 = ServiceErrorHandling.FirstElement(webElements[2], By.XPath("td[2]"))?.Text.Trim() ?? string.Empty;
                HorseModel.生産牧場 = ServiceErrorHandling.Compact(ServiceErrorHandling.FirstElement(webElements[2], By.XPath("td[4]"))?.Text);
                HorseModel.中央付加賞金 = ServiceErrorHandling.ParseInt(ServiceErrorHandling.FirstElement(webElements[2], By.XPath("td[6]"))?.Text);

                webElements = ServiceErrorHandling.WaitForElements(driver, By.XPath("//div[@class='pedigree']/table/tbody/tr"), TimeSpan.FromSeconds(3));
                if (webElements.Count < 4)
                {
                    Logger.Log($"血統テーブルの行数が不足しているため処理をスキップします: 行数={webElements.Count}, URL={url}");
                    return;
                }

                HorseModel.父 = ServiceErrorHandling.Compact(ServiceErrorHandling.FirstElement(webElements[0], By.XPath("td[@class='fathername']"))?.Text);
                HorseModel.父父 = ServiceErrorHandling.Compact(ServiceErrorHandling.FirstElement(webElements[0], By.XPath("td[@class='Paternalfathername']"))?.Text);
                HorseModel.父母 = ServiceErrorHandling.Compact(ServiceErrorHandling.FirstElement(webElements[1], By.XPath("td[2]"))?.Text);
                HorseModel.母 = ServiceErrorHandling.Compact(ServiceErrorHandling.FirstElement(webElements[2], By.XPath("td[2]"))?.Text);
                HorseModel.母父 = ServiceErrorHandling.Compact(ServiceErrorHandling.FirstElement(webElements[2], By.XPath("td[4]"))?.Text);
                HorseModel.母母 = ServiceErrorHandling.Compact(ServiceErrorHandling.FirstElement(webElements[3], By.XPath("td[2]"))?.Text);
                HorseModel.更新日 = DateOnly.FromDateTime(DateTime.Today);

                using var context = new DBContext();
                var existing = context.馬情報.FirstOrDefault(h =>
                    h.馬名 == HorseModel.馬名 &&
                    h.調教師 == HorseModel.調教師);

                if (existing != null)
                {
                    HorseModel.Id = existing.Id;
                    context.Entry(existing).CurrentValues.SetValues(HorseModel);
                    if (context.ChangeTracker.HasChanges())
                    {
                        context.SaveChanges();
                        Logger.Log($"馬情報を更新しました：{HorseModel.馬名}");
                    }
                    else
                    {
                        Logger.Log($"馬情報に変更なし：{HorseModel.馬名}");
                    }
                }
                else
                {
                    context.馬情報.Add(HorseModel);
                    context.SaveChanges();
                    Logger.Log($"新規馬情報を追加しました：{HorseModel.馬名}");
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("馬情報でエラー", ex);
                return;
            }
            finally
            {
                Logger.Log("OUT");
            }
        }
    }
}
