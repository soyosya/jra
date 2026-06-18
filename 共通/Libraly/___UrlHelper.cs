using System;
using System.Text.RegularExpressions;

namespace 中央競馬.共通.Libraly
{
    /// <summary>
    /// 現在は参照されていない旧URL正規化ヘルパーです。
    /// 再利用する場合は、ServiceErrorHandling.TryBuildAbsoluteUrl との役割重複を確認してください。
    /// </summary>
    public static class ___UrlHelper
    {
        public static string ___ToAbsoluteUrl(string baseUrl, string? href)
        {
            if (string.IsNullOrWhiteSpace(href))
            {
                return string.Empty;
            }

            var absoluteUrl = Uri.TryCreate(href.Trim(), UriKind.Absolute, out var absoluteUri)
                ? absoluteUri
                : new Uri(new Uri(baseUrl), href.Trim());

            var builder = new UriBuilder(absoluteUrl)
            {
                Path = Regex.Replace(absoluteUrl.AbsolutePath, "/{2,}", "/")
            };

            return builder.Uri.ToString();
        }
    }
}
