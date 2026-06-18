// 役割: Selenium ChromeDriverを共通設定で初期化するヘルパーです。
// UI実行とバッチ実行の両方から使われ、必要に応じてヘッドレスモードでページを開きます。
using OpenQA.Selenium;
using OpenQA.Selenium.Chrome;

namespace 中央競馬.共通.Libraly
{
    public static class WebDriverHelper
    {
        /// <summary>
        /// Selenium のコマンドタイムアウト。
        /// 既定の60秒のままだと、ブラウザがクラッシュした際に1コマンドあたり60秒待たされ、
        /// 監視ループが「1分に1エラー」で一晩中空転する原因になるため短縮します。
        /// </summary>
        private static readonly TimeSpan CommandTimeout = TimeSpan.FromSeconds(30);

        /// <summary>
        /// ページ読み込みのタイムアウト。応答しないページで無限待機しないように設定します。
        /// </summary>
        private static readonly TimeSpan PageLoadTimeout = TimeSpan.FromSeconds(30);

        /// <summary>
        /// ChromeDriver を初期化して指定した URL に遷移するメソッド。
        /// </summary>
        /// <param name="url">遷移先の URL</param>
        /// <param name="isHeadless">ブラウザを非表示にする(True)</param>
        /// <returns>初期化された ChromeDriver インスタンス</returns>
        public static IWebDriver? InitializeDriverAndNavigate(string url, bool isHeadless = false)
        {
            Logger.Log($"IN isHeadless:{isHeadless} url:{url}", 1);
            try
            {
                var options = new ChromeOptions();
                if (isHeadless)
                {
                    options.AddArgument("--headless"); // ブラウザ非表示
                    // ヘッドレス時の既定UAは「HeadlessChrome/～」となり、keiba.go.jpがHTTP 429で拒否するため、
                    // 通常ブラウザと同じUAを名乗らせて回避します。
                    options.AddArgument("--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36");
                }
                options.AddArgument("--disable-gpu");
                options.AddArgument("--no-sandbox");
                options.AddArgument("--disable-dev-shm-usage");

                var service = ChromeDriverService.CreateDefaultService();
                service.SuppressInitialDiagnosticInformation = true; // 初期診断ログ抑制
                service.HideCommandPromptWindow = true;              // 黒いコンソール非表示

                var driver = new ChromeDriver(service, options, CommandTimeout);
                driver.Manage().Timeouts().PageLoad = PageLoadTimeout;
                if (url != string.Empty)
                {
                    driver.Navigate().GoToUrl(url);
                }

                return driver;

            }
            catch (Exception ex)
            {
                Logger.LogError("WebDriverHelper.InitializeDriverAndNavigate エラー", ex);
                return null;
            }
        }

        /// <summary>
        /// 永続プロファイル(user-data-dir)付きでChromeDriverを初期化して指定URLに遷移します。
        /// PIANO ID(極ウマ)のようにクロスドメインiframeでログインするサイトは、
        /// 認証Cookieをプロファイルに残すことで「初回だけ手動ログイン→以降は自動でログイン状態維持」を実現できます。
        /// </summary>
        /// <param name="url">遷移先URL(空文字なら遷移しない)。</param>
        /// <param name="profileDir">Chromeのユーザーデータフォルダ。存在しなければ作成されます。</param>
        /// <param name="isHeadless">ブラウザを非表示にする(初回手動ログイン時はfalse推奨)。</param>
        /// <returns>初期化されたChromeDriver。失敗時はnull。</returns>
        public static IWebDriver? InitializeDriverWithProfile(string url, string profileDir, bool isHeadless = false)
        {
            Logger.Log($"IN(profile) isHeadless:{isHeadless} profile:{profileDir} url:{url}", 1);
            try
            {
                if (!string.IsNullOrWhiteSpace(profileDir))
                {
                    Directory.CreateDirectory(profileDir);
                }

                var options = new ChromeOptions();
                if (!string.IsNullOrWhiteSpace(profileDir))
                {
                    // 認証Cookieを残す永続プロファイル。これによりPIANOログインを毎回やり直さずに済みます。
                    options.AddArgument($"--user-data-dir={profileDir}");
                }
                if (isHeadless)
                {
                    options.AddArgument("--headless=new");
                    options.AddArgument("--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36");
                }
                options.AddArgument("--disable-gpu");
                options.AddArgument("--no-sandbox");
                options.AddArgument("--disable-dev-shm-usage");

                var service = ChromeDriverService.CreateDefaultService();
                service.SuppressInitialDiagnosticInformation = true;
                service.HideCommandPromptWindow = true;

                var driver = new ChromeDriver(service, options, CommandTimeout);
                driver.Manage().Timeouts().PageLoad = PageLoadTimeout;
                if (!string.IsNullOrEmpty(url))
                {
                    driver.Navigate().GoToUrl(url);
                }
                return driver;
            }
            catch (Exception ex)
            {
                Logger.LogError("WebDriverHelper.InitializeDriverWithProfile エラー", ex);
                return null;
            }
        }

        /// <summary>
        /// WebDriver(背後のChromeブラウザ)が生存していて操作可能かを判定します。
        /// 軽量なコマンドを1つ投げ、例外が出れば死亡とみなします。
        /// </summary>
        /// <param name="driver">判定対象のWebDriver。</param>
        /// <returns>操作可能ならtrue。nullまたは応答しない場合はfalse。</returns>
        public static bool IsAlive(IWebDriver? driver)
        {
            if (driver == null)
            {
                return false;
            }

            try
            {
                // ウィンドウハンドルの取得は軽量で、セッションが死んでいると例外になります。
                _ = driver.WindowHandles;
                return true;
            }
            catch
            {
                return false;
            }
        }

        /// <summary>
        /// WebDriverが生存していればそのまま返し、死亡していれば破棄して作り直します。
        /// 長時間動き続ける監視ループで、ブラウザがクラッシュしても処理を継続させるために使います。
        /// </summary>
        /// <param name="driver">現在のWebDriver。死亡している場合は内部でQuitします。</param>
        /// <param name="isHeadless">作り直す際にヘッドレスで起動するならtrue。</param>
        /// <returns>生存中のWebDriver。再生成に失敗した場合はnull。</returns>
        public static IWebDriver? EnsureAlive(IWebDriver? driver, bool isHeadless = false)
        {
            if (IsAlive(driver))
            {
                return driver;
            }

            Logger.Log("WebDriverが応答しないため再初期化します。", 1);
            try
            {
                driver?.Quit();
            }
            catch
            {
                // 既に死んでいるセッションのQuitは失敗することがあるため無視します。
            }

            return InitializeDriverAndNavigate(string.Empty, isHeadless);
        }
    }
}

