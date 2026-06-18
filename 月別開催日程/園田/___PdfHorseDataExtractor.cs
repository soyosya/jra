using System; // 基本的なシステム機能を提供する名前空間
using System.IO; // ファイルおよびデータストリームの操作を提供する名前空間
using System.Net.Http; // HTTP クライアント操作を提供する名前空間
using System.Text.RegularExpressions; // 正規表現を提供する名前空間
using System.Threading.Tasks; // 非同期操作をサポートする名前空間
using System.Collections.Generic; // ジェネリックコレクションをサポートする名前空間
using UglyToad.PdfPig; // PDF解析をサポートする名前空間
using UglyToad.PdfPig.Content;
using 中央競馬.Utilities;

namespace 中央競馬.園田
{
    /// <summary>
    /// 現在は参照されていない旧園田PDF抽出クラスです。
    /// 園田独自資料から馬の格情報を再利用する場合に備えて残しています。
    /// </summary>
    public class ___PdfHorseDataExtractor
    {
        /// <summary>
        /// 指定されたPDFのURLから全項目（馬名、馬性別、馬齢、調教師略名、転入区分、格名称、自場収得賞金）を抽出します。
        /// </summary>
        /// <param name="pdfUrl">PDFファイルのURL</param>
        /// <returns>全項目のリスト</returns>
        public static async Task<List<(string 馬名, string 馬性別, int? 馬齢, string 調教師略名, string 転入区分, string 格名称, string 自場収得賞金)>> ___ExtractAllHorseData(string pdfUrl)
        {
            ___Logger.___Log($"メソッド開始: ___ExtractAllHorseData(pdfUrl: {pdfUrl})");
            var results = new List<(string 馬名, string 馬性別, int? 馬齢, string 調教師略名, string 転入区分, string 格名称, string 自場収得賞金)>();
            string tempFilePath = Path.GetTempFileName();

            try
            {
                // HttpClient を使って PDF をダウンロード
                using (HttpClient client = new HttpClient())
                {
                    var pdfData = await client.GetByteArrayAsync(pdfUrl);
                    await File.WriteAllBytesAsync(tempFilePath, pdfData);
                }

                // PdfPig を使って解析
                using (PdfDocument document = PdfDocument.Open(tempFilePath))
                {
                    foreach (Page page in document.GetPages())
                    {
                        // ページ全体のテキストを取得
                        string pageText = page.Text;

                        // 行ごとに処理するため改行で分割
                        foreach (string line in pageText.Split(Environment.NewLine))
                        {
                            // 正規表現で項目を抽出
                            string pattern = @"(?<馬名>\S+?)\s+(?<馬性別>[牡牝セ]?)\s+(?<馬齢>\d*)\s+(?<調教師略名>\S*?)\s+(?<転入区分>\S*?)\s+(?<格名称>\S*?)\s+(?<自場収得賞金>\d{1,3}(,\d{3})*?)";
                            Match match = Regex.Match(line, pattern);

                            if (match.Success)
                            {
                                // 各項目を取得（null 許容型を使用）
                                string 馬名 = match.Groups["馬名"].Value ?? string.Empty;
                                string 馬性別 = match.Groups["馬性別"].Value ?? string.Empty;
                                int? 馬齢 = int.TryParse(match.Groups["馬齢"].Value, out var age) ? age : null;
                                string 調教師略名 = match.Groups["調教師略名"].Value ?? string.Empty;
                                string 転入区分 = match.Groups["転入区分"].Value ?? string.Empty;
                                string 格名称 = match.Groups["格名称"].Value ?? string.Empty;
                                string 自場収得賞金 = match.Groups["自場収得賞金"].Value ?? string.Empty;

                                // リストに追加
                                results.Add((馬名, 馬性別, 馬齢, 調教師略名, 転入区分, 格名称, 自場収得賞金));
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                ___Logger.___LogError("エラーが発生しました", ex);
            }
            finally
            {
                File.Delete(tempFilePath);
                ___Logger.___Log("メソッド終了: ___ExtractAllHorseData");
            }

            return results;
        }
    }
}
