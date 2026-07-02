using OpenQA.Selenium;
using OpenQA.Selenium.Chrome;
using OpenQA.Selenium.Support.UI;
using System.Text.RegularExpressions;

namespace 中央競馬.IpatVote;

/// <summary>IPAT(即PAT)のブラウザセッション。RakutenSession相当。★セレクタはipat.jsonで較正必要。</summary>
public sealed class IpatSession : IDisposable
{
    readonly IpatOptions _opt;
    public IWebDriver? Driver { get; private set; }
    public IpatSession(IpatOptions opt) => _opt = opt;

    static bool IsTodo(string sel) => string.IsNullOrWhiteSpace(sel) || sel.StartsWith("TODO_");

    void EnsureDriver()
    {
        if (Driver != null) return;
        var o = new ChromeOptions();
        if (_opt.Headless) o.AddArgument("--headless=new");
        o.AddArgument("--disable-blink-features=AutomationControlled");
        o.AddArgument("--window-size=1280,1000");
        // 入金の「入金します。よろしいですか？」等ネイティブJS確認ダイアログを自動で打ち消さない(人がOKを押せるよう開いたまま残す)
        o.UnhandledPromptBehavior = UnhandledPromptBehavior.Ignore;
        Driver = new ChromeDriver(o);
    }

    /// <summary>INET-ID → 加入者番号/暗証番号/P-ARS番号 でログイン。セレクタ未較正(TODO)時は安全に false。</summary>
    public bool Login()
    {
        if (IsTodo(_opt.Selectors.LoginInetIdInput) || IsTodo(_opt.Selectors.LoginSubscriberInput))
        {
            Log.Line("【未較正】ログインセレクタがプレースホルダ(TODO)です。ipat.jsonのSelectorsを実機で較正してください。ログインは行いません。");
            return false;
        }
        var inet = Secrets.InetId; var sub = Secrets.Subscriber; var pin = Secrets.Pin; var pars = Secrets.Pars;
        if (string.IsNullOrWhiteSpace(inet) || string.IsNullOrWhiteSpace(sub) || string.IsNullOrWhiteSpace(pin) || string.IsNullOrWhiteSpace(pars))
        {
            Log.Line("IPAT認証情報が不足(環境変数 IPAT_INETID/IPAT_SUBSCRIBER/IPAT_PIN/IPAT_PARS か secrets.local.json)。");
            return false;
        }
        try
        {
            EnsureDriver();
            Driver!.Navigate().GoToUrl(_opt.Urls.Top);
            // ① INET-ID
            if (WaitForExists(_opt.Selectors.LoginInetIdInput, TimeSpan.FromSeconds(10)))
            {
                TrySendKeys(_opt.Selectors.LoginInetIdInput, inet!);
                TryClick(_opt.Selectors.LoginInetIdSubmit);
            }
            // ② 加入者番号/暗証番号/P-ARS番号
            if (WaitForExists(_opt.Selectors.LoginSubscriberInput, TimeSpan.FromSeconds(10)))
            {
                TrySendKeys(_opt.Selectors.LoginSubscriberInput, sub!);
                TrySendKeys(_opt.Selectors.LoginPinInput, pin!);
                TrySendKeys(_opt.Selectors.LoginParsInput, pars!);
                TryClick(_opt.Selectors.LoginSubmit);
            }
            // ③ ログイン確認。LoggedInMarker較正済ならそれを待つ。未較正(TODO)時は「加入者情報入力欄の消失=メニューへ遷移」を暫定確認。
            bool markerTodo = IsTodo(_opt.Selectors.LoggedInMarker);
            if (!markerTodo)
            {
                if (WaitForExists(_opt.Selectors.LoggedInMarker, TimeSpan.FromSeconds(12))) { Log.Line("ログイン成功(投票メニューを確認)。"); return true; }
            }
            else if (WaitForGone(_opt.Selectors.LoginSubscriberInput, TimeSpan.FromSeconds(12)))
            {
                Log.Line("ログイン遷移を確認(加入者情報画面を通過)。※LoggedInMarker未較正のため投票/残高/入金は無効(安全)。メニュー画面HTMLで較正してください。");
                return true;
            }
            if (_opt.ManualLoginAssistSeconds > 0)
            {
                Log.Line($"ログイン未確認。最大{_opt.ManualLoginAssistSeconds}秒、手動操作(約定同意/画像認証等)を待ちます。");
                if (markerTodo)
                {
                    if (WaitForGone(_opt.Selectors.LoginSubscriberInput, TimeSpan.FromSeconds(_opt.ManualLoginAssistSeconds)))
                    {
                        Log.Line("ログイン遷移を確認(手動操作後)。※LoggedInMarker未較正のため以降は安全に無効。");
                        return true;
                    }
                }
                else if (WaitForExists(_opt.Selectors.LoggedInMarker, TimeSpan.FromSeconds(_opt.ManualLoginAssistSeconds))) return true;
            }
            Log.Line("ログイン/投票メニューを確認できませんでした。");
            return false;
        }
        catch (Exception ex) { Log.Line($"ログイン処理で例外: {ex.Message}"); return false; }
    }

    /// <summary>購入予定リストの「合計金額：N円」表示額を読む(getCalcTotalAmount)。読めなければ -1。</summary>
    public int ReadCartTotal()
    {
        if (Driver == null) return -1;
        try
        {
            var el = Driver.FindElements(By.CssSelector("span[ng-bind*=\"getCalcTotalAmount\"]")).FirstOrDefault();
            if (el == null) return -1;
            var digits = Regex.Replace(el.Text ?? "", "[^0-9]", "");
            return int.TryParse(digits, out var v) ? v : -1;
        }
        catch { return -1; }
    }

    /// <summary>「選択中の投票内容 N組」(vm.nTotalNum)を読む。馬選択が登録されたかの確認用。読めなければ -1。</summary>
    public int ReadSelectedCount()
    {
        if (Driver == null) return -1;
        try
        {
            var el = Driver.FindElements(By.CssSelector("strong[ng-bind=\"vm.nTotalNum\"]")).FirstOrDefault(e => e.Displayed);
            if (el == null) return -1;
            var digits = Regex.Replace(el.Text ?? "", "[^0-9]", "");
            return int.TryParse(digits, out var v) ? v : -1;
        }
        catch { return -1; }
    }

    /// <summary>残高(購入可能額)を読む。読めなければ -1。</summary>
    public int ReadBalance(string css)
    {
        if (IsTodo(css) || Driver == null) return -1;
        try
        {
            var el = Driver.FindElements(By.CssSelector(css)).FirstOrDefault();
            if (el == null) return -1;
            var digits = Regex.Replace(el.Text ?? "", "[^0-9]", "");
            return int.TryParse(digits, out var v) ? v : -1;
        }
        catch { return -1; }
    }

    /// <summary>ネイティブJS確認ダイアログ(「入金します。よろしいですか？」等)が出たらOK(Accept)。Autoのみ使用。
    /// UnhandledPromptBehavior=Ignoreでも明示Accept()は可能。出なければfalse。</summary>
    public bool AcceptAlert(TimeSpan timeout)
    {
        if (Driver == null) return false;
        try
        {
            var a = new WebDriverWait(Driver, timeout).Until(d => { try { return d.SwitchTo().Alert(); } catch { return (IAlert?)null; } });
            if (a == null) return false; a.Accept(); return true;
        }
        catch { return false; }
    }

    /// <summary>確認停止後、人が最終操作して完了表示が出るまで監視(ConfirmStop)。</summary>
    public bool WaitForVoteCompleted(string completedRegex, int timeoutSec)
    {
        if (Driver == null) return false;
        var rx = new Regex(completedRegex);
        var end = DateTime.Now.AddSeconds(timeoutSec);
        while (DateTime.Now < end)
        {
            try { if (rx.IsMatch(Driver.PageSource)) return true; } catch { }
            Thread.Sleep(1000);
        }
        return false;
    }

    public bool WaitForExists(string css, TimeSpan timeout)
    {
        if (Driver == null || IsTodo(css)) return false;
        try { new WebDriverWait(Driver, timeout).Until(d => d.FindElements(By.CssSelector(css)).Any(e => e.Displayed)); return true; }
        catch { return false; }
    }
    /// <summary>指定要素が表示されなくなる(=画面遷移)まで待つ。較正済セレクタのみ。</summary>
    public bool WaitForGone(string css, TimeSpan timeout)
    {
        if (Driver == null || IsTodo(css)) return false;
        try { new WebDriverWait(Driver, timeout).Until(d => !d.FindElements(By.CssSelector(css)).Any(e => e.Displayed)); return true; }
        catch { return false; }
    }
    /// <summary>現在のウィンドウ(タブ)数。</summary>
    public int WindowCount => Driver?.WindowHandles.Count ?? 0;
    /// <summary>priorCountより増えた新規ウィンドウ(別窓)へ切替。入金サイトはtarget=_blankで開くため使用。</summary>
    public bool SwitchToNewWindow(int priorCount, TimeSpan timeout)
    {
        if (Driver == null) return false;
        try { new WebDriverWait(Driver, timeout).Until(d => d.WindowHandles.Count > priorCount); Driver.SwitchTo().Window(Driver.WindowHandles.Last()); return true; }
        catch { return false; }
    }
    public void TrySendKeys(string css, string text) { if (IsTodo(css)) return; try { var e = Driver!.FindElement(By.CssSelector(css)); e.Clear(); e.SendKeys(text); } catch { } }

    /// <summary>テキスト入力をAngularJS(ng-model/model-pattern)へ確実反映。SendKeys後にネイティブvalueセッター+input/changeを発火
    /// (金額欄など、SendKeysだけだとセット時に金額0=合計金額未入力になる対策)。要素が見つからなければ false。</summary>
    public bool SetText(string css, string value)
    {
        if (IsTodo(css) || Driver == null) return false;
        try
        {
            var e = Driver.FindElement(By.CssSelector(css));
            try { e.Clear(); e.SendKeys(value); } catch { }
            ((IJavaScriptExecutor)Driver).ExecuteScript(
                "var el=arguments[0],v=arguments[1];" +
                "var d=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value');" +
                "if(d&&d.set){d.set.call(el,v);}else{el.value=v;}" +
                "el.dispatchEvent(new Event('input',{bubbles:true}));" +
                "el.dispatchEvent(new Event('change',{bubbles:true}));" +
                "el.dispatchEvent(new Event('blur',{bubbles:true}));", e, value);
            return true;
        }
        catch { return false; }
    }
    public void TryClick(string css) { if (IsTodo(css)) return; try { Driver!.FindElement(By.CssSelector(css)).Click(); } catch { } }

    /// <summary>&lt;select&gt;を可視テキストで選択(IPATのoption値はAngularハッシュで不安定なため場/式別/方式はテキスト指定)。</summary>
    public bool TrySelectByText(string css, string text)
    {
        if (IsTodo(css) || Driver == null) return false;
        try { new SelectElement(Driver.FindElement(By.CssSelector(css))).SelectByText(text); return true; } catch { return false; }
    }
    /// <summary>&lt;select&gt;をoption値で選択(レースは値=raceIndexで安定)。</summary>
    public bool TrySelectByValue(string css, string value)
    {
        if (IsTodo(css) || Driver == null) return false;
        try { new SelectElement(Driver.FindElement(By.CssSelector(css))).SelectByValue(value); return true; } catch { return false; }
    }
    /// <summary>&lt;select&gt;でテキストに部分一致するoptionを選択(場名「東京」→option「東京(日)」)。</summary>
    public bool TrySelectOptionContaining(string css, string substr)
    {
        if (IsTodo(css) || Driver == null) return false;
        try
        {
            var sel = new SelectElement(Driver.FindElement(By.CssSelector(css)));
            var opt = sel.Options.FirstOrDefault(o => (o.Text ?? "").Contains(substr));
            if (opt == null) return false;
            if (!opt.Selected) opt.Click();
            return true;
        }
        catch { return false; }
    }
    /// <summary>チェックボックス/ラジオを目標状態へ。IPATは&lt;input&gt;を隠し&lt;span class="check"&gt;で描画するため
    /// inputへの直接clickは不可(non-interactable)。①関連&lt;label for=id&gt;→②祖先&lt;label&gt;→③JSクリック(ng-change発火)の順で押下。</summary>
    public bool SetCheckbox(string css, bool wantChecked)
    {
        if (IsTodo(css) || Driver == null) return false;
        try
        {
            var e = Driver.FindElement(By.CssSelector(css));
            if (e.Selected == wantChecked) return true;
            var js = (IJavaScriptExecutor)Driver;
            // ① <label for="<id>">(可視。spanごとクリックでき、ネイティブにinputをトグル→AngularJS ng-change発火)
            var id = e.GetAttribute("id");
            IWebElement? lbl = null;
            if (!string.IsNullOrEmpty(id))
                lbl = Driver.FindElements(By.CssSelector($"label[for=\"{id}\"]")).FirstOrDefault(x => x.Displayed);
            // ② なければ祖先label
            if (lbl == null) { try { lbl = e.FindElement(By.XPath("ancestor::label[1]")); } catch { } }
            if (lbl != null)
            {
                try { lbl.Click(); }
                catch { js.ExecuteScript("arguments[0].click();", lbl); }
            }
            else // ③ 最終手段: input自体をJSクリック+changeイベント明示発火
            {
                js.ExecuteScript("arguments[0].click(); arguments[0].dispatchEvent(new Event('change',{bubbles:true}));", e);
            }
            return true;
        }
        catch { return false; }
    }
    /// <summary>要素の存在(表示問わず)。</summary>
    public bool Exists(string css)
    {
        if (IsTodo(css) || Driver == null) return false;
        try { return Driver.FindElements(By.CssSelector(css)).Any(); } catch { return false; }
    }
    /// <summary>表示されている要素が1つでもあるか(プルダウン/ボタンのレイアウト判定用)。</summary>
    public bool IsDisplayed(string css)
    {
        if (IsTodo(css) || Driver == null) return false;
        try { return Driver.FindElements(By.CssSelector(css)).Any(e => e.Displayed); } catch { return false; }
    }
    /// <summary>cssに一致する表示中要素のうち、テキストにsubstrを含む最初の要素をクリック(場名ボタン等)。</summary>
    public bool TryClickContaining(string css, string substr)
    {
        if (IsTodo(css) || Driver == null) return false;
        try
        {
            var el = Driver.FindElements(By.CssSelector(css)).FirstOrDefault(e => e.Displayed && (e.Text ?? "").Contains(substr));
            if (el == null) return false; el.Click(); return true;
        }
        catch { return false; }
    }
    /// <summary>レース番号ボタンをクリック(テキスト先頭の「N R」を厳密一致。11Rと1Rを誤認しない)。</summary>
    public bool TryClickRaceButton(string css, int raceNo)
    {
        if (IsTodo(css) || Driver == null) return false;
        try
        {
            foreach (var e in Driver.FindElements(By.CssSelector(css)))
            {
                if (!e.Displayed) continue;
                var m = Regex.Match(e.Text ?? "", @"(\d+)\s*R");   // 「2R (10:39)」等の先頭数字
                if (m.Success && int.Parse(m.Groups[1].Value) == raceNo) { e.Click(); return true; }
            }
        }
        catch { }
        return false;
    }
    public bool PageContains(string regex) { try { return Driver != null && new Regex(regex).IsMatch(Driver.PageSource); } catch { return false; } }

    public void Dispose() { try { Driver?.Quit(); } catch { } }
}
