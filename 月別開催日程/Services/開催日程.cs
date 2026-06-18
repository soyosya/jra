// 役割: keiba.go.jp の月別開催情報ページから開催日と開催場所を取得します。
// 開催情報テーブルは全データ取得の起点であり、当日メニューURLを保存します。
// 後続処理はこのテーブルのURLから当日メニュー、出馬表、成績ページへ進みます。
using System; // 基本的なシステム機能を提供する名前空間
using System.Linq; // LINQ 機能を提供する名前空間
using OpenQA.Selenium; // Selenium WebDriver の基本機能を提供する名前空間
using OpenQA.Selenium.Chrome; // Chrome ブラウザ用の Selenium WebDriver を提供する名前空間
using Microsoft.EntityFrameworkCore; // Entity Framework Core のデータベース操作をサポートする名前空間
using System.Web; // URL クエリ パラメータの操作を提供する名前空間
using 中央競馬.共通.Libraly; // ログ機能を提供するカスタムクラスの名前空間
using 中央競馬.共通.Data; // DB を使用する名前空間
using 中央競馬.共通.Models;
using System.Diagnostics; // データベースモデルを使用する名前空間

namespace 中央競馬.Services
{
    /// <summary>
    /// 開催日程のデータ取得と保存を行うバッチ処理クラス。
    /// </summary>
    public class 開催日程
    {
        private static readonly string baseUrl = "https://www.keiba.go.jp/KeibaWeb/MonthlyConveneInfo/MonthlyConveneInfoTop";

        /// <summary>
        /// データ取得処理のエントリーポイント。
        /// </summary>
        /// <param name="args">サービス単体実行時に渡されるコマンドライン引数。固定URLの確認処理では参照しない場合があります。</param>
        public static void 取得(string[] args)
        {
            Logger.Log("バッチ処理を開始しました。");

            int selectedYear = DateTime.Now.Year; // デフォルトで現在の年
            Debug.WriteLine("データを取得する年を入力してください（Enterキーで現在の年を使用）:");
//            string? inputYear = Console.ReadLine();
            string? inputYear = "2025";

            if (int.TryParse(inputYear, out int year))
            {
                selectedYear = year;
            }

            try
            {
                FetchAndStoreData(null,selectedYear);
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
        /// 指定された年のデータを取得してデータベースに保存します。
        /// </summary>
        /// <param name="driver">取得対象ページを操作するSelenium WebDriver。nullを許可するメソッドでは内部で生成します。</param>
        /// <param name="year">取得対象の年。</param>
        /// <param name="month">取得対象の月。省略時は1月を対象にします。</param>
        public static void FetchAndStoreData(IWebDriver? driver, int year,int month=1)
        {
            Logger.Log($"IN Year:{year} Month:{month}",1);
            try
            {
                if (driver == null)
                {
                    driver = WebDriverHelper.InitializeDriverAndNavigate(baseUrl);
                    if (driver == null)
                    {
                        Logger.Log($"WebDriverの初期化に失敗したため処理をスキップします: {baseUrl}");
                        return;
                    }
                }
                // 年の選択
                var yearSelect = ServiceErrorHandling.FirstElement(driver, By.Id("selectedYear"));
                if (yearSelect == null)
                {
                    Logger.Log("年選択リストが見つからないため開催日程取得をスキップします。");
                    return;
                }

                var optionsList = yearSelect.FindElements(By.TagName("option"));
                optionsList.FirstOrDefault(o => o.Text == year.ToString())?.Click();

                Logger.Log($"{year}年{month}月のデータを処理中です。");
                string monthTabId = $"monthTab{month}";

                try
                {
                    var monthTab = ServiceErrorHandling.FirstElement(driver, By.Id(monthTabId));
                    if (monthTab == null)
                    {
                        Logger.Log($"{month}月のタブが見つかりませんでした。");
                        return;
                    }

                    monthTab.Click();
                    var raceDateOfMonth = driver.FindElements(By.XPath("//table[@class='schedule']//a[@href]"));

                    foreach (var raceInfo in raceDateOfMonth)
                    {
                        try
                        {
                            if (!ServiceErrorHandling.TryBuildAbsoluteUrl(baseUrl, raceInfo.GetDomAttribute("href"), out var url, out var urlError))
                            {
                                Logger.Log($"開催日程URLを生成できないため行をスキップします: {urlError}");
                                continue;
                            }

                            if (!ServiceErrorHandling.TryReadRaceDateAndCourse(url, out var 開催日, out var 開催場所, out var queryError))
                            {
                                Logger.Log($"開催日程URLのクエリが不正なため行をスキップします: {queryError}");
                                continue;
                            }

                            Logger.Log($"開催場所: {開催場所}, 開催日: {開催日}, メニューURL: {url}");
                            SaveToDatabase(開催日, 開催場所, url);
                        }
                        catch (Exception ex)
                        {
                            Logger.LogError("開催日程行の処理中にエラーが発生しました。", ex);
                        }
                    }
                }
                catch (NoSuchElementException ex)
                {
                    Logger.LogError($"{month}月のデータが見つかりませんでした。", ex);
                }
            }
            catch(Exception ex)
            {
                Logger.LogError("開催情報 エラーが発生しました。", ex);
            }
            finally
            {
                Logger.Log("終了しました。");
            }
        }

        /// <summary>
        /// データをデータベースに保存します。
        /// </summary>
        /// <param name="開催日">保存または解析結果へ設定する開催日。</param>
        /// <param name="開催場所">保存または解析結果へ設定する開催場所。</param>
        /// <param name="当日メニューURL">開催情報ページから取得した当日メニューへのURL。</param>
        private static void SaveToDatabase(DateOnly 開催日, string 開催場所, string 当日メニューURL)
        {
            Logger.Log($"開催情報 データベースに保存中: 開催日={開催日}, 開催場所={開催場所}, URL={当日メニューURL}");

            try
            {
                using var context = new DBContext();
                var existingData = context.開催情報.FirstOrDefault(h => h.開催日 == 開催日 && h.開催場所 == 開催場所);

                if (existingData != null)
                {
                    existingData.当日メニューURL = 当日メニューURL;
                }
                else
                {
                    context.開催情報.Add(new 開催情報モデル
                    {
                        開催日 = 開催日,
                        開催場所 = 開催場所,
                        当日メニューURL = 当日メニューURL
                    });
                }

                context.SaveChanges();
//                Logger.Log("データの保存に成功しました。");
            }
            catch (Exception ex)
            {
                Logger.LogError($"データベースエラーが発生しました。{Environment.NewLine}{当日メニューURL}", ex);
            }
        }
    }
}
