// 役割: 楽天競馬 投票Lite(bet_lite)へのログインとブラウザ管理を行います。
using OpenQA.Selenium;
using WebHelper = 中央競馬.共通.Libraly.WebDriverHelper;
using CommonLogger = 中央競馬.共通.Libraly.Logger;

namespace 中央競馬.RakutenVote
{
    public sealed class RakutenSession : IDisposable
    {
        private readonly RakutenOptions _opt;
        public IWebDriver? Driver { get; private set; }

        public RakutenSession(RakutenOptions opt) => _opt = opt;

        /// <summary>ブラウザを起動し投票Liteを開く。未ログインなら楽天IDでログインする。</summary>
        public bool Login()
        {
            bool headless = _opt.Headless && _opt.ResolvedMode == BetMode.DryRun;
            Driver = WebHelper.InitializeDriverAndNavigate(_opt.Urls.BetLite, headless);
            if (Driver == null) { CommonLogger.LogError("WebDriver初期化に失敗", new Exception("driver null")); return false; }

            // 既にログイン済みなら投票Liteのレース選択フォームが出る
            if (WaitForExists(_opt.Selectors.LoggedInMarker, TimeSpan.FromSeconds(8))) return true;

            // ログインフォーム(楽天ID Omniウィジェット)が出ていれば認証
            var user = RakutenOptions.UserId; var pass = RakutenOptions.Password;
            if (!string.IsNullOrEmpty(user) && !string.IsNullOrEmpty(pass) &&
                WaitForExists(_opt.Selectors.LoginUserInput, TimeSpan.FromSeconds(8)))
            {
                TrySendKeys(_opt.Selectors.LoginUserInput, user);
                TryClick(_opt.Selectors.LoginUserNext);          // 「次へ」
                if (WaitForExists(_opt.Selectors.LoginPassInput, TimeSpan.FromSeconds(10)))
                {
                    TrySendKeys(_opt.Selectors.LoginPassInput, pass);
                    TryClick(_opt.Selectors.LoginPassNext);      // 「次へ」
                }
            }
            else
            {
                CommonLogger.Log("認証情報未設定かログインフォーム未検出。手動ログインを待ちます。", 1);
            }

            // ログイン完了(=bet_lite表示) or 手動操作(2FA/CAPTCHA)の待機
            if (WaitForExists(_opt.Selectors.LoggedInMarker, TimeSpan.FromSeconds(15))) return true;
            if (_opt.ManualLoginAssistSeconds > 0)
            {
                CommonLogger.Log($"ログイン未確認。最大{_opt.ManualLoginAssistSeconds}秒、手動操作(2段階認証等)を待ちます。", 1);
                // 手動でログイン後 bet_lite に来てもらう。来なければ最後に再度開く。
                if (WaitForExists(_opt.Selectors.LoggedInMarker, TimeSpan.FromSeconds(_opt.ManualLoginAssistSeconds))) return true;
                try { Driver.Navigate().GoToUrl(_opt.Urls.BetLite); } catch { }
                if (WaitForExists(_opt.Selectors.LoggedInMarker, TimeSpan.FromSeconds(8))) return true;
            }
            CommonLogger.Log("ログイン/投票Lite表示を確認できませんでした。", 1);
            return false;
        }

        /// <summary>投票Liteのレース選択トップへ戻す(各レースの開始点)。</summary>
        public void GoToBetLite()
        {
            if (Driver == null) return;
            try { Driver.Navigate().GoToUrl(_opt.Urls.BetLite); } catch { }
            WaitForExists(_opt.Selectors.SelRacecourse, TimeSpan.FromSeconds(10));
        }

        /// <summary>購入限度額(残高)を読み取る。読めなければ -1。</summary>
        public int ReadBalance(string css)
        {
            if (Driver == null || string.IsNullOrWhiteSpace(css)) return -1;
            try
            {
                var e = Driver.FindElements(By.CssSelector(css)).FirstOrDefault();
                if (e == null) return -1;
                var t = System.Text.RegularExpressions.Regex.Replace(e.Text ?? "", "[^0-9]", "");
                return int.TryParse(t, out var v) ? v : -1;
            }
            catch { return -1; }
        }

        /// <summary>確認画面で停止後、人が『投票する』を押して完了表示(completedText)が出るまで監視する。
        /// 出れば true、時間切れ false。コンソール入力に依存しないため無人ランナーからの起動でも機能する。</summary>
        public bool WaitForVoteCompleted(string completedText, int timeoutSec)
        {
            if (Driver == null || string.IsNullOrWhiteSpace(completedText)) return false;
            // 複数マーカー(| 区切り)のいずれかが出れば完了とみなす(実ページの文言ゆれ対策)。
            var markers = completedText.Split('|', StringSplitOptions.RemoveEmptyEntries);
            var end = DateTime.UtcNow + TimeSpan.FromSeconds(Math.Max(1, timeoutSec));
            while (DateTime.UtcNow < end)
            {
                try { var src = Driver.PageSource ?? ""; if (markers.Any(m => src.Contains(m))) return true; }
                catch { }
                Thread.Sleep(1000);
            }
            return false;
        }

        public bool WaitForExists(string css, TimeSpan timeout)
        {
            if (Driver == null || string.IsNullOrWhiteSpace(css)) return false;
            var end = DateTime.UtcNow + timeout;
            while (DateTime.UtcNow < end)
            {
                try { if (Driver.FindElements(By.CssSelector(css)).Any(e => e.Displayed)) return true; }
                catch { }
                Thread.Sleep(500);
            }
            return false;
        }
        private void TrySendKeys(string css, string val)
        {
            try { var e = Driver!.FindElements(By.CssSelector(css)).FirstOrDefault(); e?.Clear(); e?.SendKeys(val); }
            catch (Exception ex) { CommonLogger.LogError($"入力失敗 css={css}", ex); }
        }
        private void TryClick(string css)
        {
            try
            {
                var e = Driver!.FindElements(By.CssSelector(css)).FirstOrDefault();
                if (e == null) return;
                try { e.Click(); } catch { ((IJavaScriptExecutor)Driver).ExecuteScript("arguments[0].click();", e); }
            }
            catch (Exception ex) { CommonLogger.LogError($"クリック失敗 css={css}", ex); }
        }

        public void Dispose() { try { Driver?.Quit(); } catch { } }
    }
}
