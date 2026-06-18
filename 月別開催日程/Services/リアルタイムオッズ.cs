// 役割: 当日のレースについて、リアルタイムオッズを定期取得して保存します。
// 当日メニューの発走時刻とレース番号をもとに対象レースを決め、オッズ推移のチャート表示へつなげます。
using Microsoft.EntityFrameworkCore; // Entity Framework Core を使ったデータベース操作を行う
using OpenQA.Selenium; // Selenium WebDriver を使ったブラウザ操作を行う
using System; // 日付・時間・例外処理などの基本機能
using System.Linq; // LINQ を使ったデータ操作
using System.Text.RegularExpressions; // 正規表現による文字列解析
using System.Web; // URLクエリパラメータ操作用
using System.Threading; // CancellationToken 用
using System.Threading.Tasks; // 非同期処理(Task) 用
using 中央競馬.共通.Data; // データベースコンテキスト(DBContext)
using 中央競馬.共通.Libraly; // Logger・WebDriverHelper などの共通ライブラリ
using 中央競馬.共通.Models; // リアルタイムオッズモデル定義

namespace 中央競馬.Services
{
    /// <summary>
    /// リアルタイムオッズ取得サービスクラス
    /// </summary>
    public class リアルタイムオッズ
    {
        /// <summary>
        /// オッズ取得メイン処理（非同期）
        /// </summary>
        /// <param name="notify">取得状況を呼び出し元へ通知するコールバック。不要な場合はnull。</param>
        /// <param name="token">処理停止要求を受け取るキャンセルトークン。</param>
        /// <param name="isHeadless">Chromeをヘッドレスモードで起動する場合はtrue。</param>
        /// <returns>このメソッド内で開始した非同期処理の完了を表すTask。</returns>
        public static async Task 取得Async(Action<string>? notify, CancellationToken token, bool isHeadless)
        {
            Logger.Log("リアルタイムオッズ処理を開始しました。");
            try
            {
                using var driver = WebDriverHelper.InitializeDriverAndNavigate(string.Empty, isHeadless);
                if (driver == null) return;

                DateOnly RaceDate = DateOnly.FromDateTime(DateTime.Today);
                using var context = new DBContext();
                var races = await context.当日メニュー
                    .Where(h => h.開催日 == RaceDate && h.レース番号 > 0)
                    .OrderBy(h => h.発走時刻)
                    .ToListAsync(token);

                if (!races.Any())
                {
                    Logger.Log("取得対象のレースがありません。");
                    notify?.Invoke("取得対象のレースがありません。");
                    return;
                }

                DateTime lastRaceTime = races.Max(h => h.発走時刻);
                DateTime monitorEndTime = lastRaceTime.AddMinutes(10);
                var upcomingRace = races.FirstOrDefault(h => h.発走時刻 > DateTime.Now);

                if (DateTime.Now >= monitorEndTime)
                {
                    await Task.Run(() => FetchDueRaceResultsAndPayouts(driver, RaceDate, token, notify), token);
                    return;
                }

                while (DateTime.Now < monitorEndTime)
                {
                    if (token.IsCancellationRequested)
                    {
                        notify?.Invoke("オッズ取得処理がキャンセルされました。");
                        break;
                    }

                    await Task.Run(() => FetchDueRaceResultsAndPayouts(driver, RaceDate, token, notify), token);

                    if (upcomingRace != null)
                    {
                        TimeSpan remaining = upcomingRace.発走時刻 - DateTime.Now;
                        if (remaining.TotalMinutes < -3)
                        {
                            upcomingRace = races.FirstOrDefault(h => h.発走時刻 > upcomingRace.発走時刻 && h.発走時刻 > DateTime.Now.AddMinutes(-3));
                        }

                        if (upcomingRace != null)
                        {
                            remaining = upcomingRace.発走時刻 - DateTime.Now;
                            notify?.Invoke($"次のレース締切: {remaining.TotalMinutes:F0}分後 {upcomingRace.開催場所} {upcomingRace.レース番号}R {upcomingRace.発走時刻:HH:mm} 発走");

                            string url = CreateURL(upcomingRace.開催日, upcomingRace.開催場所, upcomingRace.レース番号);
                            await Task.Run(() => FetchAndStoreData(driver, url), token);
                        }
                    }

                    await Task.Delay(TimeSpan.FromSeconds(10), token);
                }

                await Task.Run(() => FetchDueRaceResultsAndPayouts(driver, RaceDate, token, notify), token);
            }
            catch (OperationCanceledException)
            {
                notify?.Invoke("オッズ取得処理がキャンセルされました。");
                Logger.Log("リアルタイムオッズ処理がキャンセルされました。");
            }
            catch (Exception ex)
            {
                Logger.LogError("リアルタイムオッズ処理中にエラーが発生しました。", ex);
            }
            finally
            {
                Logger.Log("リアルタイムオッズ処理を終了しました。");
            }
        }

        /// <summary>
        /// サービス単体実行時の入口として、既定条件で取得処理を呼び出します。
        /// </summary>
        /// <param name="notify">取得状況を呼び出し元へ通知するコールバック。不要な場合はnull。</param>
        /// <param name="token">処理停止要求を受け取るキャンセルトークン。</param>
        /// <param name="isHeadless">Chromeをヘッドレスモードで起動する場合はtrue。</param>
        public static void 取得(Action<string>? notify, CancellationToken token, bool isHeadless)
        {
            取得Async(notify, token, isHeadless).GetAwaiter().GetResult();
        }

        /// <summary>
        /// 発走時刻から10分以上経過したレースについて、競走結果と払戻金の未取得データを成績URLから補完します。
        /// 競走結果は同一レースに着順付きデータが存在しない場合、払戻金は同一レースの払戻金レコードが存在しない場合に取得します。
        /// </summary>
        /// <param name="driver">成績ページを開いて解析するためのSelenium WebDriver。</param>
        /// <param name="raceDate">補完対象にする開催日。</param>
        /// <param name="token">処理停止要求を受け取るキャンセルトークン。</param>
        /// <param name="notify">補完状況を呼び出し元へ通知するコールバック。不要な場合はnull。</param>
        private static void FetchDueRaceResultsAndPayouts(IWebDriver driver, DateOnly raceDate, CancellationToken token, Action<string>? notify)
        {
            DateTime resultReadyTime = DateTime.Now.AddMinutes(-10);

            using var context = new DBContext();
            var targets = context.当日メニュー
                .AsNoTracking()
                .Where(menu => menu.開催日 == raceDate)
                .Where(menu => menu.レース番号 > 0)
                .Where(menu => menu.発走時刻 <= resultReadyTime)
                .Where(menu => menu.成績URL != string.Empty)
                .Select(menu => new
                {
                    Race = menu,
                    HasRaceResult = context.競走結果.Any(result =>
                        result.開催日 == menu.開催日 &&
                        result.開催場所 == menu.開催場所 &&
                        result.レース番号 == menu.レース番号 &&
                        result.着順 > 0),
                    HasPayout = context.払戻金.Any(payout =>
                        payout.開催日 == menu.開催日 &&
                        payout.開催場所 == menu.開催場所 &&
                        payout.レース番号 == menu.レース番号)
                })
                .Where(target => !target.HasRaceResult || !target.HasPayout)
                .OrderBy(target => target.Race.発走時刻)
                .ThenBy(target => target.Race.開催場所)
                .ThenBy(target => target.Race.レース番号)
                .ToList();

            foreach (var target in targets)
            {
                token.ThrowIfCancellationRequested();

                if (!target.HasRaceResult)
                {
                    string message = $"競走結果未取得のため取得します: {target.Race.開催場所} {target.Race.レース番号}R {target.Race.発走時刻:HH:mm}";
                    Logger.Log(message);
                    notify?.Invoke(message);
                    競走結果.FetchAndStoreData(driver, target.Race.成績URL);
                }

                if (!target.HasPayout)
                {
                    string message = $"払戻金未取得のため取得します: {target.Race.開催場所} {target.Race.レース番号}R {target.Race.発走時刻:HH:mm}";
                    Logger.Log(message);
                    notify?.Invoke(message);
                    払戻金.FetchAndStoreData(driver, target.Race.成績URL);
                }
            }
        }

        /// <summary>
        /// 当日(または指定日)の全レースのオッズを1回だけ巡回取得して保存する一括スナップショット。
        /// 監視ループ(取得Async)と違い即時に終了するため、タスクスケジューラで日中に数回回す前向き収集に向く。
        /// 過去オッズは復元不可のため、人気乖離分析用のデータはこの収集の積み上げで作る。
        /// </summary>
        /// <param name="args">args[1]に任意で対象日(yyyy-MM-dd)。省略時は当日。</param>
        public static void 当日オッズ取得(string[] args)
        {
            Logger.Log("当日オッズ取得(スナップショット) IN");
            IWebDriver? driver = null;
            try
            {
                DateOnly date = DateOnly.FromDateTime(DateTime.Today);
                if (args != null && args.Length > 1 && DateOnly.TryParse(args[1], out var d)) date = d;

                List<(string 開催場所, int レース番号)> races;
                using (var context = new DBContext())
                {
                    races = context.当日メニュー.AsNoTracking()
                        .Where(m => m.開催日 == date && m.レース番号 > 0)
                        .OrderBy(m => m.発走時刻).ThenBy(m => m.開催場所).ThenBy(m => m.レース番号)
                        .Select(m => new { m.開催場所, m.レース番号 })
                        .ToList()
                        .Select(x => (x.開催場所, x.レース番号))
                        .ToList();
                }
                if (races.Count == 0)
                {
                    Logger.Log($"当日メニューに対象レースがありません(先に当日メニュー取得が必要): {date}");
                    return;
                }

                driver = WebDriverHelper.InitializeDriverAndNavigate(string.Empty, true);
                if (driver == null) { Logger.Log("WebDriver初期化に失敗。"); return; }

                int n = 0;
                foreach (var race in races)
                {
                    try { FetchAndStoreData(driver, CreateURL(date, race.開催場所, race.レース番号)); n++; }
                    catch (Exception ex) { Logger.LogError($"オッズ取得スキップ {race.開催場所}{race.レース番号}R", ex); }
                    Thread.Sleep(400); // keiba.go.jpへの連続アクセス緩和
                }
                Logger.Log($"当日オッズ取得 完了: {n}/{races.Count}レース巡回 ({date})");
            }
            catch (Exception ex) { Logger.LogError("当日オッズ取得エラー", ex); }
            finally { try { driver?.Quit(); } catch { } Logger.Log("当日オッズ取得(スナップショット) OUT"); }
        }

        /// <summary>
        /// 開催日、開催場所、レース番号からkeiba.go.jpのリアルタイムオッズURLを生成します。
        /// </summary>
        /// <param name="RaceDate">URLへ設定する開催日。</param>
        /// <param name="Racecourse">URLへ設定する開催場所。場名マスタで競馬場コードへ変換します。</param>
        /// <param name="raceNumber">URLまたは解析結果へ設定するレース番号。</param>
        /// <returns>指定レースのリアルタイムオッズページURL。</returns>
        public static string CreateURL(DateOnly RaceDate, string Racecourse, int raceNumber)
        {
            string babaCode = 場名マスタ.GetByPlace(Racecourse.Trim());
            return $"https://www.keiba.go.jp/KeibaWeb/TodayRaceInfo/OddsTanFuku?k_raceDate={Uri.EscapeDataString(RaceDate.ToString())}&k_raceNo={raceNumber}&k_babaCode={babaCode}";
        }

        /// <summary>
        /// 指定された取得元からデータを読み取り、DBへ保存します。
        /// </summary>
        /// <param name="driver">取得対象ページを操作するSelenium WebDriver。nullを許可するメソッドでは内部で生成します。</param>
        /// <param name="url">取得または解析の対象となるkeiba.go.jpのページURL。</param>
        public static void FetchAndStoreData(IWebDriver driver, string url)
        {
            Logger.Log($"IN FetchAndStoreData URL: {url}");
            try
            {
                if (string.IsNullOrWhiteSpace(url))
                {
                    Logger.Log("リアルタイムオッズURLが空のため処理をスキップします。");
                    return;
                }

                driver.Navigate().GoToUrl(url);

                if (!ServiceErrorHandling.TryReadRaceQuery(url, out var RaceDate, out var Racecourse, out var raceNumber, out var queryError))
                {
                    Logger.Log($"リアルタイムオッズURLのクエリが不正なため処理をスキップします: {queryError}");
                    return;
                }

                var oddsDateElement = ServiceErrorHandling.FirstElement(driver, By.XPath("//h4[@class='odd_title']"));
                if (oddsDateElement == null)
                {
                    Logger.Log($"オッズ時刻が取得できないため処理をスキップします: {url}");
                    return;
                }

                var match = Regex.Match(oddsDateElement.Text, @"(\d{1,2}):(\d{2})");
                DateTime oddsTime = match.Success ?
                    new DateTime(DateTime.Today.Year, DateTime.Today.Month, DateTime.Today.Day, ServiceErrorHandling.ParseInt(match.Groups[1].Value), ServiceErrorHandling.ParseInt(match.Groups[2].Value), 0) :
                    DateTime.Now;

                using var context = new DBContext();
                var latest = context.リアルタイムオッズ
                    .Where(h => h.開催日 == RaceDate && h.開催場所 == Racecourse && h.レース番号 == raceNumber)
                    .Max(h => (DateTime?)h.日時);

                if (latest.HasValue && latest.Value >= oddsTime) return;

                var webElements = driver.FindElements(By.XPath("//table[@class='odd_popular_table_02']/tbody/tr"));
                if (webElements.Count == 0)
                {
                    Logger.Log($"オッズテーブルが見つからないため処理をスキップします: {url}");
                    return;
                }

                var oddsList = webElements.Select(row =>
                {
                    var cells = row.FindElements(By.XPath("td"));
                    if (cells.Count < 6) return null;

                    int 馬番 = int.TryParse(cells[1].Text, out var num) ? num : 0;
                    string 複勝オッズRaw = cells[4].Text + cells[5].Text;
                    var 複勝オッズArray = 複勝オッズRaw.Split('-');
                    double 複勝オッズ_MIN = double.TryParse(複勝オッズArray.ElementAtOrDefault(0), out var min) ? min : 0.0;
                    double 複勝オッズ_MAX = double.TryParse(複勝オッズArray.ElementAtOrDefault(1), out var max) ? max : 0.0;
                    double 単勝オッズ = double.TryParse(cells[3].Text, out var tan) ? tan : 0.0;

                    return new リアルタイムオッズモデル
                    {
                        開催日 = RaceDate,
                        開催場所 = Racecourse,
                        レース番号 = raceNumber,
                        馬番 = 馬番,
                        馬名 = cells[2].Text.Trim(),
                        単勝オッズ = 単勝オッズ,
                        複勝オッズ = 複勝オッズRaw,
                        複勝オッズ_MIN = 複勝オッズ_MIN,
                        複勝オッズ_MAX = 複勝オッズ_MAX,
                        人気 = 0,
                        日時 = oddsTime
                    };
                }).Where(x => x != null).Cast<リアルタイムオッズモデル>().ToList();

                if (oddsList.Count == 0)
                {
                    Logger.Log($"保存対象のリアルタイムオッズがありません: {url}");
                    return;
                }

                int rank = 1;
                foreach (var odds in oddsList.OrderBy(o => o.単勝オッズ).ThenBy(o => o.馬番))
                {
                    odds.人気 = (odds.馬番 > 0 && odds.単勝オッズ > 0) ? rank++ : oddsList.Count;
                }

                context.リアルタイムオッズ.AddRange(oddsList);
                context.SaveChanges();
            }
            catch (Exception ex)
            {
                Logger.LogError($"リアルタイムオッズ エラー発生 URL: {url}", ex);
            }
            finally
            {
                Logger.Log($"OUT FetchAndStoreData URL: {url}");
            }
        }
    }
}
