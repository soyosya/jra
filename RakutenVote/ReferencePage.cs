// 役割: 照会(/reference)で暗証番号を入力し「残高照会」を実行、投票資金の内訳(購入限度額・当日購入/払戻 等)を取得します。
// 実DOM(2026-06提供): #passcodeInput に暗証番号 → #balanceInquiry 送信 → .balancePointInfo__list の各 li を解析。
using OpenQA.Selenium;
using CommonLogger = 中央競馬.共通.Libraly.Logger;

namespace 中央競馬.RakutenVote
{
    public sealed class ReferencePage
    {
        private readonly RakutenOptions _opt;
        private readonly RakutenSession _sess;
        private IWebDriver D => _sess.Driver!;
        public ReferencePage(RakutenOptions opt, RakutenSession sess) { _opt = opt; _sess = sess; }

        /// <summary>暗証番号で残高照会を実行し、ラベル→値(円)の内訳を返す。失敗時は空。</summary>
        public List<(string label, string value)> ReadDetailedBalance(string pin)
        {
            var result = new List<(string, string)>();
            var r = _opt.Reference; var s = r.Selectors;
            if (D == null) return result;
            try
            {
                D.Navigate().GoToUrl(r.Url);
                if (!_sess.WaitForExists(s.PinInput, TimeSpan.FromSeconds(15)))
                { CommonLogger.Log("  照会画面(暗証番号欄)が出ません。", 1); return result; }

                var pinEl = D.FindElements(By.CssSelector(s.PinInput)).FirstOrDefault();
                pinEl?.Clear(); pinEl?.SendKeys(pin);
                var submit = D.FindElements(By.CssSelector(s.BalanceSubmit)).FirstOrDefault();
                if (submit == null) { CommonLogger.Log("  残高照会ボタンが見つかりません。", 1); return result; }
                try { submit.Click(); } catch { ((IJavaScriptExecutor)D).ExecuteScript("arguments[0].click();", submit); }

                // 残高・有効期限照会画面に到達。明示的に「残高照会」タブを選択(有効期限照会が出ていても確実に残高へ)。
                if (!string.IsNullOrWhiteSpace(s.BalanceTab))
                {
                    var tab = D.FindElements(By.CssSelector(s.BalanceTab)).FirstOrDefault(x => x.Displayed);
                    if (tab != null) { try { tab.Click(); } catch { ((IJavaScriptExecutor)D).ExecuteScript("arguments[0].click();", tab); } Thread.Sleep(400); }
                }

                if (!_sess.WaitForExists(s.ItemRow, TimeSpan.FromSeconds(15)))
                { CommonLogger.Log("  残高内訳が表示されません(暗証番号誤り/セレクタ要確認)。", 1); return result; }

                foreach (var row in D.FindElements(By.CssSelector(s.ItemRow)))
                {
                    try
                    {
                        var label = row.FindElements(By.CssSelector(s.ItemLabel)).FirstOrDefault()?.Text?.Trim() ?? "";
                        var val = row.FindElements(By.CssSelector(s.ItemValue)).FirstOrDefault()?.Text?.Trim() ?? "";
                        if (!string.IsNullOrEmpty(label)) result.Add((label, val));
                    }
                    catch { }
                }
            }
            catch (Exception ex) { CommonLogger.LogError("残高照会に失敗", ex); }
            return result;
        }
    }
}
