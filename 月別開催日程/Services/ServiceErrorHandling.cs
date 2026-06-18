// 役割: サービス層で共通利用するURL解析、Selenium待機、テキスト変換の補助処理です。
// ページ構造変更や未掲載ページで例外が連鎖しないよう、取得失敗をfalseや空リストとして扱います。
using OpenQA.Selenium;
using OpenQA.Selenium.Support.UI;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Web;
using 中央競馬.共通.Models;

namespace 中央競馬.Services
{
    /// <summary>
    /// サービス層で共通利用する、小さな取得・変換・待機処理をまとめたヘルパーです。
    /// Seleniumの例外を呼び出し側へ直接漏らさず、取得できない場合は空値やfalseを返す方針にしています。
    /// </summary>
    internal static class ServiceErrorHandling
    {
        /// <summary>
        /// レースURLのクエリから開催日、競馬場、レース番号を読み取ります。 keiba.go.jp のURLは複数ページで同じクエリ形式を使うため、各サービスの入口で共通利用します。
        /// </summary>
        /// <param name="url">取得または解析の対象となるkeiba.go.jpのページURL。</param>
        /// <param name="raceDate">URLへ設定する開催日。</param>
        /// <param name="racecourse">URLへ設定する開催場所。場名マスタで競馬場コードへ変換します。</param>
        /// <param name="raceNumber">URLまたは解析結果へ設定するレース番号。</param>
        /// <param name="error">読み取りまたは生成に失敗した場合の理由を格納する出力引数。</param>
        /// <returns>開催日、競馬場名、レース番号をすべて読み取れた場合はtrue。いずれかが不正な場合はfalse。</returns>
        public static bool TryReadRaceQuery(string url, out DateOnly raceDate, out string racecourse, out int raceNumber, out string error)
        {
            raceNumber = 0;
            if (!TryReadRaceDateAndCourse(url, out raceDate, out racecourse, out error))
            {
                return false;
            }

            var query = HttpUtility.ParseQueryString(new Uri(url).Query);
            var raceNoText = query["k_raceNo"];
            if (!int.TryParse(raceNoText, out raceNumber) || raceNumber <= 0)
            {
                error = $"k_raceNo が不正です: {raceNoText}";
                return false;
            }

            return true;
        }

        /// <summary>
        /// レースURLのクエリから開催日と競馬場を読み取ります。 競馬場はk_babaCodeを場名マスタで変換して、DB保存時の開催場所名に揃えます。
        /// </summary>
        /// <param name="url">取得または解析の対象となるkeiba.go.jpのページURL。</param>
        /// <param name="raceDate">URLへ設定する開催日。</param>
        /// <param name="racecourse">URLへ設定する開催場所。場名マスタで競馬場コードへ変換します。</param>
        /// <param name="error">読み取りまたは生成に失敗した場合の理由を格納する出力引数。</param>
        /// <returns>開催日と競馬場名を読み取れた場合はtrue。URLやクエリが不正な場合はfalse。</returns>
        public static bool TryReadRaceDateAndCourse(string url, out DateOnly raceDate, out string racecourse, out string error)
        {
            raceDate = default;
            racecourse = string.Empty;
            error = string.Empty;

            if (!Uri.TryCreate(url, UriKind.Absolute, out var uri))
            {
                error = $"URLが不正です: {url}";
                return false;
            }

            var query = HttpUtility.ParseQueryString(uri.Query);
            var raceDateText = query["k_raceDate"];
            if (!DateOnly.TryParse(raceDateText, out raceDate))
            {
                error = $"k_raceDate が不正です: {raceDateText}";
                return false;
            }

            var babaCode = query["k_babaCode"];
            if (string.IsNullOrWhiteSpace(babaCode))
            {
                error = "k_babaCode が見つかりません。";
                return false;
            }

            racecourse = 場名マスタ.GetByCode(babaCode);
            if (string.IsNullOrWhiteSpace(racecourse))
            {
                error = $"競馬場コードを変換できません: {babaCode}";
                return false;
            }

            return true;
        }

        /// <summary>
        /// ページ内の相対リンクを絶対URLへ変換します。 URL生成に失敗した理由も返し、呼び出し側がログへ残せるようにしています。
        /// </summary>
        /// <param name="baseUrl">相対リンクを解決するための基準URL。</param>
        /// <param name="href">ページから取得したhref属性値。</param>
        /// <param name="absoluteUrl">生成した絶対URLを格納する出力引数。</param>
        /// <param name="error">読み取りまたは生成に失敗した場合の理由を格納する出力引数。</param>
        /// <returns>絶対URLを生成できた場合はtrue。hrefや基準URLが不正な場合はfalse。</returns>
        public static bool TryBuildAbsoluteUrl(string baseUrl, string? href, out string absoluteUrl, out string error)
        {
            absoluteUrl = string.Empty;
            error = string.Empty;

            if (string.IsNullOrWhiteSpace(href))
            {
                error = "href が空です。";
                return false;
            }

            if (!Uri.TryCreate(baseUrl, UriKind.Absolute, out var baseUri))
            {
                error = $"基準URLが不正です: {baseUrl}";
                return false;
            }

            if (!Uri.TryCreate(baseUri, href, out var uri))
            {
                error = $"URLを生成できません: base={baseUrl}, href={href}";
                return false;
            }

            absoluteUrl = uri.ToString();
            return true;
        }

        /// <summary>
        /// 指定セレクタに一致する最初の要素を返します。 見つからない場合はnullを返すため、NoSuchElementExceptionを避けたい解析処理で使います。
        /// </summary>
        /// <param name="context">検索対象となるWebDriverまたは親要素。</param>
        /// <param name="by">検索に使用するSeleniumセレクタ。</param>
        /// <returns>最初に見つかったSelenium要素。該当要素がない場合はnull。</returns>
        public static IWebElement? FirstElement(ISearchContext context, By by)
        {
            return context.FindElements(by).FirstOrDefault();
        }

        /// <summary>
        /// 指定要素のテキストを取得します。 テキストが空の場合はfalseを返し、必須項目の検証に使えるようにしています。
        /// </summary>
        /// <param name="context">検索対象となるWebDriverまたは親要素。</param>
        /// <param name="by">検索に使用するSeleniumセレクタ。</param>
        /// <param name="text">取得した要素テキストを格納する出力引数。</param>
        /// <returns>空でないテキストを取得できた場合はtrue。要素がない、またはテキストが空の場合はfalse。</returns>
        public static bool TryGetText(ISearchContext context, By by, out string text)
        {
            text = FirstElement(context, by)?.Text.Trim() ?? string.Empty;
            return !string.IsNullOrWhiteSpace(text);
        }

        /// <summary>
        /// 表示済みの最初の要素が現れるまで待機します。 取得できない場合はnullを返し、ページ構造変更や未掲載ページを安全にスキップします。
        /// </summary>
        /// <param name="driver">取得対象ページを操作するSelenium WebDriver。nullを許可するメソッドでは内部で生成します。</param>
        /// <param name="by">検索に使用するSeleniumセレクタ。</param>
        /// <param name="timeout">要素の表示を待機する最大時間。</param>
        /// <returns>表示済みで見つかった最初のSelenium要素。タイムアウトした場合はnull。</returns>
        public static IWebElement? WaitForFirstElement(IWebDriver driver, By by, TimeSpan timeout)
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
        /// 表示済みの要素一覧が現れるまで待機します。 タイムアウトやDOM更新による例外は空リストに変換します。
        /// </summary>
        /// <param name="driver">取得対象ページを操作するSelenium WebDriver。nullを許可するメソッドでは内部で生成します。</param>
        /// <param name="by">検索に使用するSeleniumセレクタ。</param>
        /// <param name="timeout">要素の表示を待機する最大時間。</param>
        /// <returns>表示済みで見つかったSelenium要素一覧。タイムアウトした場合は空リスト。</returns>
        public static List<IWebElement> WaitForElements(IWebDriver driver, By by, TimeSpan timeout)
        {
            try
            {
                var wait = new WebDriverWait(driver, timeout);
                return wait.Until(d =>
                {
                    var elements = d.FindElements(by).Where(e => e.Displayed).ToList();
                    return elements.Count > 0 ? elements : null;
                }) ?? new List<IWebElement>();
            }
            catch (WebDriverTimeoutException)
            {
                return new List<IWebElement>();
            }
            catch (NoSuchElementException)
            {
                return new List<IWebElement>();
            }
            catch (StaleElementReferenceException)
            {
                return new List<IWebElement>();
            }
        }

        /// <summary>
        /// 文字列から整数として読める部分だけを抽出します。 カンマや単位が含まれる画面テキストをDB値に変換するための処理です。
        /// </summary>
        /// <param name="text">整数へ変換する画面テキスト。</param>
        /// <returns>抽出した整数値。数値を読み取れない場合は0。</returns>
        public static int ParseInt(string? text)
        {
            return int.TryParse(Regex.Replace(text ?? string.Empty, @"[^\d-]", ""), out var value) ? value : 0;
        }

        /// <summary>
        /// 文字列から小数として読める部分だけを抽出します。 上り3Fや着差タイムなど、小数表記の画面テキストに使います。
        /// </summary>
        /// <param name="text">小数へ変換する画面テキスト。</param>
        /// <returns>抽出した小数値。数値を読み取れない場合は0。</returns>
        public static decimal ParseDecimal(string? text)
        {
            return decimal.TryParse(Regex.Replace(text ?? string.Empty, @"[^\d\.-]", ""), out var value) ? value : 0m;
        }

        /// <summary>
        /// 半角・全角スペースや改行を取り除いた比較用文字列を作ります。 馬主名や調教師名など、画面上で空白が混ざる値の正規化に使います。
        /// </summary>
        /// <param name="text">半角空白、全角空白、改行を除去する対象文字列。</param>
        /// <returns>空白類を取り除いた文字列。入力がnullの場合は空文字列。</returns>
        public static string Compact(string? text)
        {
            return Regex.Replace(text ?? string.Empty, @"[\s\u3000]", "");
        }
    }
}
