using System;
using System.Collections.Generic;
using OpenQA.Selenium;
using 中央競馬.Utilities;

namespace 中央競馬.園田
{
    /// <summary>
    /// 現在は参照されていない旧園田ポイント抽出クラスです。
    /// 指定されたURLからレースデータを抽出します。
    /// </summary>
    public class ___HorsePoints
    {
        /// <summary>
        /// 指定されたURLからレースデータを取得します。
        /// </summary>
        /// <param name="driver">使用するWebDriverのインスタンス</param>
        /// <param name="url">データを取得する対象のURL</param>
        /// <returns>抽出したレースデータのリスト</returns>
        public static List<(string 馬名, string 性, string 齢, string ポイント, string 格, string 調教師, string 備考)> ___Get(IWebDriver driver, string url)
        {
            ___Logger.___Log($"メソッド開始: ___Get(url: {url})");

            var raceDataList = new List<(string 馬名, string 性, string 齢, string ポイント, string 格, string 調教師, string 備考)>();

            try
            {
                driver.Navigate().GoToUrl(url);

                // 指定されたテーブルを取得
                var table = driver.FindElement(By.XPath("//table[@class='table field_info']"));
                var rows = table.FindElements(By.TagName("tr"));

                foreach (var row in rows)
                {
                    var cells = row.FindElements(By.TagName("td"));

                    // セルが不足している場合はスキップ
                    if (cells.Count < 7) continue;

                    // 必要なデータを抽出（null 許容型でエラー回避）
                    string 馬名 = cells[0]?.Text.Trim() ?? string.Empty;
                    string 性 = cells[1]?.Text.Trim() ?? string.Empty;
                    string 齢 = cells[2]?.Text.Trim() ?? string.Empty;
                    string ポイント = cells[3]?.Text.Trim() ?? string.Empty;
                    string 格 = cells[4]?.Text.Trim() ?? string.Empty;
                    string 調教師 = cells[5]?.Text.Trim() ?? string.Empty;
                    string 備考 = cells[6]?.Text.Trim() ?? string.Empty;

                    raceDataList.Add((馬名, 性, 齢, ポイント, 格, 調教師, 備考));
                }

                ___Logger.___Log($"データ抽出が正常に完了しました。件数: {raceDataList.Count}");
            }
            catch (Exception ex)
            {
                ___Logger.___LogError("エラーが発生しました", ex);
            }
            finally
            {
                ___Logger.___Log("メソッド終了: ___Get");
            }

            return raceDataList;
        }
    }
}
