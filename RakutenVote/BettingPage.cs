// 役割: 投票Lite(bet_lite)で 3連単マルチ(軸1頭・相手N頭=1着流し+マルチ)を組み立て、
//       モードに応じて確認画面で停止/「投票する」まで実行します。DryRunでは一切クリックしません。
// 実DOM(2026-06提供, プレーンHTMLフォーム)に基づく:
//   レース選択(競馬場/レース/式別=三連単/方式=流し)→ 軸me1[]・相手me2[]・isMulti・金額buyUnitCount
//   → 投票内容を確認する → 確認画面 cashConfirm に合計額 → 投票する(inputBet)。
using OpenQA.Selenium;
using CommonLogger = 中央競馬.共通.Libraly.Logger;

namespace 中央競馬.RakutenVote
{
    public enum BetResult { Planned, StoppedForConfirm, Purchased, Failed, SkippedBudget, Closed }

    public sealed class BettingPage
    {
        private readonly RakutenOptions _opt;
        private readonly RakutenSession _sess;
        private IWebDriver D => _sess.Driver!;
        public BettingPage(RakutenOptions opt, RakutenSession sess) { _opt = opt; _sess = sess; }

        /// <summary>1レース分を投票します。spent に実際/予定の投票額(円)を返します。</summary>
        public BetResult PlaceBet(BetTicket t, out int spent)
        {
            bool isFuku = _opt.IsSanrenpuku;
            int points = isFuku ? t.PointCountFuku : t.ExpandMultiTrifecta().Count;
            spent = points * _opt.StakePerPointYen;
            var s = _opt.Selectors;
            string betName = isFuku ? "三連複 軸1頭流し" : "三連単 1着流しマルチ";
            string betTypeValue = isFuku ? _opt.SanrenpukuBetTypeValue : _opt.BetTypeValue;  // 三連複=8 / 三連単=9

            CommonLogger.Log($"[計画] {t.Date} {t.Venue}{t.Race}R 軸{t.AxisUma} 相手[{string.Join(",", t.Partners)}] → {betName} {points}点 × {_opt.StakePerPointYen}円 = {spent:N0}円", 1);
            if (_opt.ResolvedMode == BetMode.DryRun) return BetResult.Planned;
            if (_sess.Driver == null) return BetResult.Failed;
            if (points <= 0) { CommonLogger.Log("  点数0(相手不足)でスキップ", 1); return BetResult.Failed; }

            try
            {
                // 1) 投票Liteレース選択: 競馬場(名前で選択)/レース/式別/方式=流し(=32, 三連複は軸1頭流しに既定で割当)
                _sess.GoToBetLite();
                if (PageClosed()) { CommonLogger.Log($"  [締切] {t.Venue}{t.Race}R は発売締切。投票を中断します。", 1); return BetResult.Closed; }
                if (!SelectByText(s.SelRacecourse, t.Venue))
                {
                    if (PageClosed()) { CommonLogger.Log($"  [締切] {t.Venue}{t.Race}R は発売締切。投票を中断します。", 1); return BetResult.Closed; }
                    CommonLogger.Log($"  競馬場 '{t.Venue}' を選択できません(非開催/締切?)", 1); return BetResult.Failed;
                }
                SelectByValue(s.SelRaceNumber, t.Race.ToString());
                SelectByValue(s.SelBetType, betTypeValue);
                SelectByValue(s.SelBetMode, _opt.BetModeValue);   // 流し=32
                if (PageClosed()) { CommonLogger.Log($"  [締切] {t.Venue}{t.Race}R は発売締切。投票を中断します。", 1); return BetResult.Closed; }
                if (!ClickWait(s.SubmitSelect, s.AxisRadioTemplate.Replace("{UMA}", t.AxisUma.ToString()), "買い目を選択する", 15))
                {
                    if (PageClosed()) { CommonLogger.Log($"  [締切] {t.Venue}{t.Race}R は発売締切。投票を中断します。", 1); return BetResult.Closed; }
                    CommonLogger.Log("  買い目選択画面に遷移できません(締切/未発売?)", 1); return BetResult.Failed;
                }

                // 2) 軸(me1ラジオ) / 相手(me2チェック) / [三連単のみ]マルチ / 金額
                if (!Click(s.AxisRadioTemplate.Replace("{UMA}", t.AxisUma.ToString()), $"軸{t.AxisUma}"))
                { CommonLogger.Log("  軸の選択に失敗", 1); return BetResult.Failed; }
                foreach (var p in t.Partners)
                    Click(s.PartnerCheckTemplate.Replace("{UMA}", p.ToString()), $"相手{p}");
                if (!isFuku) CheckOn(s.MultiCheckbox, "マルチ");   // 三連複はマルチ無し

                int units = Math.Max(1, _opt.StakePerPointYen / 100);
                SetValue(s.AmountInput, units.ToString(), "金額(各 N 00円)");

                // 3) 投票内容を確認する → 確認画面
                if (!ClickWait(s.SubmitConfirm, s.VerifyInput, "投票内容を確認する", 15))
                { CommonLogger.Log("  確認画面に遷移できません(買い目/金額エラー?)", 1); return BetResult.Failed; }

                // 4) 確認画面: 投票金額(合計)を入力
                SetValue(s.VerifyInput, spent.ToString(), "投票金額(合計)");

                if (_opt.ResolvedMode == BetMode.ConfirmStop)
                {
                    CommonLogger.Log($"  [確認停止] 確認画面で停止({spent:N0}円)。内容を確認し手動で「投票する」を押してください。", 1);
                    return BetResult.StoppedForConfirm;
                }

                // 5) Auto: 「投票する」(実課金)
                Click(s.VoteSubmit, "投票する");
                Thread.Sleep(2000);
                var markers = _opt.CompletedText.Split('|', StringSplitOptions.RemoveEmptyEntries);
                var src = D.PageSource ?? "";
                if (markers.Any(m => src.Contains(m)))
                { CommonLogger.Log($"  [購入完了] {t.Venue}{t.Race}R {spent:N0}円", 1); return BetResult.Purchased; }
                CommonLogger.Log("  購入完了文言を確認できませんでした。実際は完了の可能性あり。履歴で要確認。", 1);
                return BetResult.Failed;
            }
            catch (Exception ex)
            {
                CommonLogger.LogError($"投票操作に失敗 {t.Venue}{t.Race}R", ex);
                return BetResult.Failed;
            }
        }

        /// <summary>レース選択画面に発売締切メッセージが出ているか。</summary>
        private bool PageClosed()
        {
            try { return !string.IsNullOrEmpty(_opt.ClosedText) && (D.PageSource ?? "").Contains(_opt.ClosedText); }
            catch { return false; }
        }

        // --- 操作ヘルパ ---
        /// <summary>select を可視テキスト一致で選択(競馬場名など)。</summary>
        private bool SelectByText(string css, string text)
        {
            try
            {
                var sel = D.FindElements(By.CssSelector(css)).FirstOrDefault();
                if (sel == null) return false;
                var ok = ((IJavaScriptExecutor)D).ExecuteScript(
                    "var s=arguments[0],t=arguments[1];for(var i=0;i<s.options.length;i++){if(s.options[i].text.trim()===t){s.selectedIndex=i;s.dispatchEvent(new Event('change'));return true;}}return false;",
                    sel, text);
                return ok is bool b && b;
            }
            catch (Exception ex) { CommonLogger.LogError($"select(text)失敗 css={css} text={text}", ex); return false; }
        }
        private void SelectByValue(string css, string val)
        {
            try
            {
                var sel = D.FindElements(By.CssSelector(css)).FirstOrDefault();
                if (sel == null) { CommonLogger.Log($"  select無し css={css}", 1); return; }
                ((IJavaScriptExecutor)D).ExecuteScript(
                    "var s=arguments[0];s.value=arguments[1];s.dispatchEvent(new Event('change'));", sel, val);
            }
            catch (Exception ex) { CommonLogger.LogError($"select(value)失敗 css={css} val={val}", ex); }
        }
        private bool Click(string css, string label)
        {
            try
            {
                var e = D.FindElements(By.CssSelector(css)).FirstOrDefault(x => x.Displayed) ??
                        D.FindElements(By.CssSelector(css)).FirstOrDefault();
                if (e == null) { CommonLogger.Log($"  要素なし({label}) css={css}", 1); return false; }
                try { e.Click(); } catch { ((IJavaScriptExecutor)D).ExecuteScript("arguments[0].click();", e); }
                return true;
            }
            catch (Exception ex) { CommonLogger.LogError($"クリック失敗({label}) css={css}", ex); return false; }
        }
        private bool ClickWait(string css, string waitFor, string label, int sec)
        {
            if (!Click(css, label)) return false;
            return _sess.WaitForExists(waitFor, TimeSpan.FromSeconds(sec));
        }
        private void CheckOn(string css, string label)
        {
            try
            {
                var e = D.FindElements(By.CssSelector(css)).FirstOrDefault();
                if (e == null) { CommonLogger.Log($"  要素なし({label}) css={css}", 1); return; }
                if (!e.Selected) { try { e.Click(); } catch { ((IJavaScriptExecutor)D).ExecuteScript("arguments[0].click();", e); } }
            }
            catch (Exception ex) { CommonLogger.LogError($"チェック失敗({label}) css={css}", ex); }
        }
        private void SetValue(string css, string val, string label)
        {
            try
            {
                var e = D.FindElements(By.CssSelector(css)).FirstOrDefault(x => x.Displayed) ??
                        D.FindElements(By.CssSelector(css)).FirstOrDefault();
                if (e == null) { CommonLogger.Log($"  要素なし({label}) css={css}", 1); return; }
                e.Clear(); e.SendKeys(val);
            }
            catch (Exception ex) { CommonLogger.LogError($"入力失敗({label}) css={css}", ex); }
        }
    }
}
