// 役割: 楽天銀行からの入金。当日買い目の必要額(投票合計−残高)を自動計算し、入金画面で
//       楽天銀行・金額を入力→「確認する」→確認画面で停止(ConfirmStop)。「入金する」は人が押す。
//       Auto(無人で入金確定)は安全のため実装しない=お金が動く最終クリックは必ず人の手に残す。
// 実DOM(2026-06提供)に基づく: select#select / #transactionAmountInput(100円単位) /
//   form.transactionInput__main の「確認する」 / form.transactionConfirm の「入金する」/ .information-balance。
using System.Text.RegularExpressions;
using OpenQA.Selenium;
using CommonLogger = 中央競馬.共通.Libraly.Logger;

namespace 中央競馬.RakutenVote
{
    public enum DepositResult { NotNeeded, Planned, StoppedForConfirm, Aborted, Failed }

    public sealed class DepositPage
    {
        private readonly RakutenOptions _opt;
        private readonly RakutenSession _sess;
        private IWebDriver D => _sess.Driver!;
        public DepositPage(RakutenOptions opt, RakutenSession sess) { _opt = opt; _sess = sess; }

        /// <summary>買い目から実際に投票される合計額(予算ガード・最大レース適用後)を算出。</summary>
        public static int ComputePlannedTotal(List<BetTicket> bets, RakutenOptions opt)
        {
            int total = 0, races = 0;
            foreach (var b in bets)
            {
                if (opt.MaxRaces > 0 && races >= opt.MaxRaces) break;
                int per = (opt.IsSanrenpuku ? b.PointCountFuku : b.PointCount) * opt.StakePerPointYen;
                if (total + per > opt.DailyBudgetYen) continue; // 予算超過レースはスキップ(投票側と同じ挙動)
                total += per; races++;
            }
            return total;
        }

        /// <summary>入金を実行(モード依存)。amountOverride>0 なら買い目計算でなく固定額を入金。amount に入金指示額(円)を返す。</summary>
        public DepositResult Run(List<BetTicket> bets, int amountOverride, out int amount)
        {
            amount = 0;
            var d = _opt.Deposit; var s = d.Selectors;
            int planned = ComputePlannedTotal(bets, _opt);
            bool fixedMode = amountOverride > 0;
            if (fixedMode) Console.WriteLine($"  入金指定額 = {amountOverride:N0}円(--amount 指定。買い目計算は無視)");
            else { CommonLogger.Log($"[入金] 投票合計={planned:N0}円", 1); Console.WriteLine($"  当日買い目の投票合計 = {planned:N0}円(予算上限{_opt.DailyBudgetYen:N0}円、余裕{d.BufferYen:N0}円)"); }

            if (_opt.ResolvedMode == BetMode.DryRun)
            {
                Console.WriteLine(fixedMode
                    ? $"  [DryRun] 指定額 {amountOverride:N0}円 を入金します(実行は ConfirmStop)。"
                    : "  [DryRun] 必要額 = 投票合計 − 現在残高。残高はConfirmStop時に入金画面から取得して算出します。");
                return DepositResult.Planned;
            }
            if (_sess.Driver == null) return DepositResult.Failed;

            try
            {
                D.Navigate().GoToUrl(d.Url);
                if (!_sess.WaitForExists(s.AmountInput, TimeSpan.FromSeconds(15)))
                { CommonLogger.Log("  入金画面の金額入力欄が出ません(ログイン/セレクタ要確認)。", 1); return DepositResult.Failed; }
                DismissPopup(s);   // 「入金について」説明ポップアップ(オーバーレイ)を閉じる

                int need;
                if (fixedMode)
                {
                    need = amountOverride;
                    int bal = ReadBalance(s.BalanceText);
                    Console.WriteLine($"  現在残高 = {bal:N0}円 / 指定額 = {need:N0}円");
                }
                else
                {
                    int balance = ReadBalance(s.BalanceText);
                    need = planned + d.BufferYen - balance;
                    Console.WriteLine($"  現在残高 = {balance:N0}円 / 必要額 = {planned:N0}+{d.BufferYen}−{balance:N0} = {need:N0}円");
                    if (need <= 0) { Console.WriteLine("  → 残高で足ります。入金不要。"); return DepositResult.NotNeeded; }
                }

                if (need <= 0) { Console.WriteLine("  → 入金額が0以下。中止。"); return DepositResult.NotNeeded; }
                need = (int)Math.Ceiling(need / 100.0) * 100;     // 100円単位に切り上げ
                if (need > d.MaxDepositYen)
                { Console.WriteLine($"  [中止] 入金額{need:N0}円が上限{d.MaxDepositYen:N0}円超。安全弁により中止(rakuten.jsonのMaxDepositYen)。"); return DepositResult.Aborted; }
                Console.WriteLine($"  → 入金指示額 = {need:N0}円(100円単位)");
                amount = need;

                // 入金方法=楽天銀行(既定だが明示)
                SetSelect(s.MethodSelect, d.MethodValue);
                // 金額(100円単位 → need/100 を入力)
                SetReactInput(s.AmountInput, (need / 100).ToString());
                Thread.Sleep(300);

                if (!ClickWait(s.ConfirmButton, s.ExecuteButton, "確認する", 15))
                { CommonLogger.Log("  確認画面に遷移できません(金額エラー/ボタン無効?)。", 1); return DepositResult.Failed; }

                CommonLogger.Log($"  [確認停止] 入金指示確認画面で停止({need:N0}円)。暗証番号(必要なら)を入力し「入金する」を人が押してください。", 1);
                return DepositResult.StoppedForConfirm;
            }
            catch (Exception ex) { CommonLogger.LogError("入金操作に失敗", ex); return DepositResult.Failed; }
        }

        // 入金画面の説明ポップアップ(前面オーバーレイ)を閉じる。出ていなければ何もしない。
        private void DismissPopup(DepositSelectors s)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(s.PopupCloseButton)) return;
                if (!_sess.WaitForExists(s.PopupCloseButton, TimeSpan.FromSeconds(5))) return; // 出ていなければスキップ
                var chk = D.FindElements(By.CssSelector(s.PopupDontShowCheckbox)).FirstOrDefault();
                if (chk != null && !chk.Selected) { try { chk.Click(); } catch { ((IJavaScriptExecutor)D).ExecuteScript("arguments[0].click();", chk); } }
                var close = D.FindElements(By.CssSelector(s.PopupCloseButton)).FirstOrDefault(x => x.Displayed);
                if (close != null) { try { close.Click(); } catch { ((IJavaScriptExecutor)D).ExecuteScript("arguments[0].click();", close); } }
                Thread.Sleep(500);
                CommonLogger.Log("  入金説明ポップアップを閉じました。", 1);
            }
            catch (Exception ex) { CommonLogger.LogError("ポップアップ処理で例外(無視して継続)", ex); }
        }

        private int ReadBalance(string css)
        {
            try
            {
                var e = D.FindElements(By.CssSelector(css)).FirstOrDefault();
                if (e == null) return 0;
                var t = Regex.Replace(e.Text ?? "", "[^0-9]", "");
                return int.TryParse(t, out var v) ? v : 0;
            }
            catch { return 0; }
        }
        private void SetSelect(string css, string val)
        {
            try
            {
                var sel = D.FindElements(By.CssSelector(css)).FirstOrDefault(); if (sel == null) return;
                ((IJavaScriptExecutor)D).ExecuteScript("var s=arguments[0];s.value=arguments[1];s.dispatchEvent(new Event('change',{bubbles:true}));", sel, val);
            }
            catch (Exception ex) { CommonLogger.LogError($"方法選択失敗 css={css}", ex); }
        }
        // Vue/Reactの数値入力は input イベントを発火させないと反映されないため、ネイティブsetter経由で値設定。
        private void SetReactInput(string css, string val)
        {
            try
            {
                var e = D.FindElements(By.CssSelector(css)).FirstOrDefault(x => x.Displayed) ?? D.FindElements(By.CssSelector(css)).FirstOrDefault();
                if (e == null) { CommonLogger.Log($"  金額欄なし css={css}", 1); return; }
                ((IJavaScriptExecutor)D).ExecuteScript(
                    "var i=arguments[0],v=arguments[1];" +
                    "var set=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;set.call(i,v);" +
                    "i.dispatchEvent(new Event('input',{bubbles:true}));i.dispatchEvent(new Event('change',{bubbles:true}));", e, val);
            }
            catch (Exception ex) { CommonLogger.LogError($"金額入力失敗 css={css}", ex); }
        }
        private bool ClickWait(string css, string waitFor, string label, int sec)
        {
            try
            {
                var e = D.FindElements(By.CssSelector(css)).FirstOrDefault(x => x.Displayed) ?? D.FindElements(By.CssSelector(css)).FirstOrDefault();
                if (e == null) { CommonLogger.Log($"  要素なし({label}) css={css}", 1); return false; }
                try { e.Click(); } catch { ((IJavaScriptExecutor)D).ExecuteScript("arguments[0].click();", e); }
                return _sess.WaitForExists(waitFor, TimeSpan.FromSeconds(sec));
            }
            catch (Exception ex) { CommonLogger.LogError($"クリック失敗({label}) css={css}", ex); return false; }
        }
    }
}
