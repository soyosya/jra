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

    /// <summary>投票後など別画面にいる時、会員トップ(メニュー)へ戻ってから残高を読む。
    /// 既ログイン状態ならナビゲートのみでメニューが出る想定。出なければ Login() で再確認(既ログインならマーカー確認で即成立)。読めなければ -1。</summary>
    public int ReadBalanceViaMenu(string balCss)
    {
        if (Driver == null || IsTodo(balCss)) return -1;
        try
        {
            Driver.Navigate().GoToUrl(_opt.Urls.Top);
            bool onMenu = !IsTodo(_opt.Selectors.LoggedInMarker)
                          && WaitForExists(_opt.Selectors.LoggedInMarker, TimeSpan.FromSeconds(8));
            if (!onMenu && !Login()) return -1;               // メニューに戻れなければ再ログインで確実にメニューへ
            WaitForExists(balCss, TimeSpan.FromSeconds(6));    // 残高テーブルの描画待ち
            return ReadBalance(balCss);
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

    /// <summary>ページ内の全「受付番号」の数字を集合で収集。IPATはSPAで前回投票の受付番号がDOMに残るため、単純な文字列一致では誤完了する。集合差分で"新規発番"を判定する。</summary>
    public HashSet<string> ReadReceiptNos()
    {
        var set = new HashSet<string>();
        if (Driver == null) return set;
        try { foreach (Match m in Regex.Matches(Driver.PageSource, @"受付番号[\s\S]{0,24}?(\d{2,})")) if (m.Groups[1].Success) set.Add(m.Groups[1].Value); }
        catch { }
        return set;
    }

    /// <summary>送信前の受付番号集合(before)に含まれない"新しい受付番号"が出現するまで待つ。出現=実際に発番された=成立。出現しなければ(前回の残存テキストのみ)=未成立でfalse。★誤完了(phantom 投票完了)防止の要。</summary>
    public bool WaitForNewReceipt(HashSet<string> before, int timeoutSec)
    {
        if (Driver == null) return false;
        var end = DateTime.Now.AddSeconds(timeoutSec);
        while (DateTime.Now < end)
        {
            try { foreach (var r in ReadReceiptNos()) if (!before.Contains(r)) return true; } catch { }
            Thread.Sleep(1000);
        }
        return false;
    }

    /// <summary>投票成立判定(2026-07-05改)。IPAT完了画面の「受け付けました」メッセージが"新規に"出現(送信前は無い→単票は即成立)を主判定にする。受付メッセージが送信前から残存している(=複数買い目カートの前票分)場合のみ、新しい受付番号の発番で二重確認。受付番号regexは実画面で読めない例があり(false-negative)、メッセージ主体に変更。</summary>
    public bool WaitForFreshAcceptance(string acceptRegex, bool beforeAccept, HashSet<string> beforeReceipts, int timeoutSec)
    {
        if (Driver == null) return false;
        var rx = new Regex(acceptRegex);
        var end = DateTime.Now.AddSeconds(timeoutSec);
        while (DateTime.Now < end)
        {
            try
            {
                bool nowAccept = rx.IsMatch(Driver.PageSource);
                if (nowAccept && !beforeAccept) return true;                         // 受付メッセージが新規出現=成立(単票の正常系)
                foreach (var r in ReadReceiptNos()) if (!beforeReceipts.Contains(r)) return true; // 残存時は新受付番号で確認(補助)
            }
            catch { }
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
    /// <summary>レース番号ボタン(ボタン形式)を選択。★締切ガード: 対象レースのボタンが「締切」表示 or 無効(disabled)ならクリックせず Closed を返す(=投票中止)。対象ボタンが見つからない(=投票リンクなし)場合は NotFound(ユーザ規約=リンクなし=締切扱いで中止)。有効ならクリックして Clicked。</summary>
    public RaceSelect ClickRaceButton(string css, int raceNo)
    {
        if (IsTodo(css) || Driver == null) return RaceSelect.NotFound;
        try
        {
            foreach (var e in Driver.FindElements(By.CssSelector(css)))
            {
                if (!e.Displayed) continue;
                var txt = e.Text ?? "";
                var m = Regex.Match(txt, @"(\d+)\s*R");   // 「2R (10:39)」「3R 締切」等の先頭数字
                if (!m.Success || int.Parse(m.Groups[1].Value) != raceNo) continue;
                // 対象レースのボタン発見。締切(テキストに「締切」含む)または無効化(disabled)ならクリックしない=投票中止。
                bool closed = txt.Contains("締切") || !e.Enabled;
                try { if (!closed) { var da = e.GetAttribute("disabled"); var ac = e.GetAttribute("aria-disabled"); if (!string.IsNullOrEmpty(da) || string.Equals(ac, "true", StringComparison.OrdinalIgnoreCase)) closed = true; } } catch { }
                if (closed) return RaceSelect.Closed;
                e.Click(); return RaceSelect.Clicked;
            }
        }
        catch { }
        return RaceSelect.NotFound;
    }
    public bool PageContains(string regex) { try { return Driver != null && new Regex(regex).IsMatch(Driver.PageSource); } catch { return false; } }

    public void Dispose() { try { Driver?.Quit(); } catch { } }
}
