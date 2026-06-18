using OpenQA.Selenium;
using OpenQA.Selenium.Chrome;

namespace 中央競馬.Utilities
{
    /// <summary>
    /// 現在は参照されていない旧WebDriverヘルパーです。
    /// 現行処理では 共通.Libraly.WebDriverHelper を使用します。
    /// </summary>
    public static class ___WebDriverHelper
    {
        /// <summary>
        /// ChromeDriver を初期化して指定した URL に遷移するメソッド。
        /// </summary>
        /// <param name="url">遷移先の URL</param>
        /// <returns>初期化された ChromeDriver インスタンス</returns>
        public static IWebDriver ___InitializeDriverAndNavigate(string url)
        {
            var options = new ChromeOptions();
//            options.AddArgument("--headless");
            options.AddArgument("--disable-gpu");
            options.AddArgument("--no-sandbox");
            options.AddArgument("--disable-dev-shm-usage");
            options.AddArgument("--log-level=3"); // ログレベルを最小化
            options.AddArgument("--silent");

            var driver = new ChromeDriver(options);
            if(url != null)
            {
                driver.Navigate().GoToUrl(url);
            }

            return driver;
        }

    }
}

