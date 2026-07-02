// 役割: タスクスケジューラなどから起動するバッチ処理の入口です。
// 第1引数のモードに応じて、リアルタイム取得、翌日分補完、開催情報取得などを切り替えます。
// UIを使わない運用では、このファイルの各Runメソッドが処理フローの出発点になります。
using NLog;
using NLog.Config;
using Microsoft.EntityFrameworkCore;
using OpenQA.Selenium;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using 中央競馬.Services;
using 中央競馬.共通.Data;
using 中央競馬.共通.Libraly;
using 中央競馬.共通.Models;
using CommonLogger = 中央競馬.共通.Libraly.Logger;

namespace 中央競馬バッチ
{
    /// <summary>
    /// コマンドライン引数で指定されたバッチ処理を実行する入口クラス。
    /// 各処理は中央競馬サイトから取得した情報を、開催情報を起点にしてDBへ保存します。
    /// </summary>
    internal class Program
    {
        private const string MonthlyConveneInfoTopUrl = "https://www.keiba.go.jp/KeibaWeb/MonthlyConveneInfo/MonthlyConveneInfoTop";

        /// <summary>
        /// アプリケーションのエントリーポイント。
        /// 第1引数に指定されたモード名で、リアルタイム取得や翌日分補完などの処理を切り替えます。
        /// </summary>
        /// <param name="args">第1引数に処理モードを指定します。</param>
        private static void Main(string[] args)
        {
            ConfigureLogging();

            var mode = args.Length > 0 ? args[0].ToLowerInvariant() : string.Empty;
            CommonLogger.Log($"Start:Args='{mode}'", 1);

            try
            {
                switch (mode)
                {
                    case "realtimeodds":
                        RunRealtimeOdds();
                        break;
                    case "realtimeraceinfo":
                        RunRealtimeRaceInfo();
                        break;
                    case "nextraceinfo":
                        RunNextRaceInfo();
                        break;
                    case "create-db":
                        RunCreateDatabase();
                        break;
                    case "fetch-jra-range":
                        RunFetchJraRange(args);
                        break;
                    case "fetch-jra-race":
                        RunFetchJraRace(args);
                        break;
                    case "fetch-jra-official":
                        RunFetchJraOfficial(args);
                        break;
                    case "fetch-danwa":
                        競馬ブック取得.取得(args);
                        break;
                    case "fetch-cyokyo":
                        競馬ブック取得.調教取得(args);
                        break;
                    case "fetch-uma":
                        競馬ブック取得.完全データ取得(args);
                        break;
                    case "fetch-danwa-range":
                        競馬ブック取得.取得範囲(args);
                        break;
                    case "fetch-cyokyo-range":
                        競馬ブック取得.調教取得範囲(args);
                        break;
                    case "fetch-schedule":
                        開催日程.取得(args);
                        break;
                    case "fetch-today-menu":
                        当日メニュー.取得(args);
                        break;
                    case "fetch-payout":
                        払戻金.取得(args);
                        break;
                    case "backfill-corner-positions":
                        RunBackfillCornerPositions(args);
                        break;
                    case "fetch-range":
                        RunFetchRange(args);
                        break;
                    case "fetch-compi":
                        コンピ指数取得.取得(args);
                        break;
                    case "fetch-odds":
                        リアルタイムオッズ.当日オッズ取得(args);
                        break;
                    case "fetch-compi-range":
                        コンピ指数取得.取得範囲(args);
                        break;
                    default:
                        CommonLogger.Log("処理対象が不明です。引数を指定してください。");
                        Debug.WriteLine("処理対象が不明です。引数を指定してください。");
                        break;
                }
            }
            catch (Exception ex)
            {
                CommonLogger.LogError("Main処理でエラーが発生しました。", ex);
            }
            finally
            {
                CommonLogger.Log("バッチ処理を終了しました。", 1);
                Debug.WriteLine("バッチ処理を終了しました。");
            }
        }

        /// <summary>
        /// fetch-jra-range処理。netkeibaから指定日付範囲のJRA全レース(結果・レース情報・払戻・確定オッズ)を
        /// 未取得分だけ取得して保存します。スモークテストは開始日=終了日(1日)で実行します。
        /// </summary>
        /// <param name="args">第2引数に開始日、第3引数に終了日(yyyy-MM-dd)、第4引数に任意の待機ミリ秒を指定します。</param>
        private static void RunFetchJraRange(string[] args)
        {
            if (!DateOnly.TryParse(args.ElementAtOrDefault(1), out var from) ||
                !DateOnly.TryParse(args.ElementAtOrDefault(2), out var to))
            {
                CommonLogger.Log("引数が不正です。fetch-jra-range <開始日> <終了日> [待機ミリ秒] (yyyy-MM-dd) の形式で指定してください。");
                return;
            }

            // force: 既取得レースも再取得し、レース情報(枠番/性別/馬齢/調教師/馬主)を最新netkeibaで上書き(欠落補完用)。
            bool force = args.Any(a => string.Equals(a, "force", StringComparison.OrdinalIgnoreCase));
            if (int.TryParse(args.ElementAtOrDefault(3), out var delayMs) && delayMs >= 0)
            {
                JRA取込.FetchRange(from, to, delayMs, force);
            }
            else
            {
                JRA取込.FetchRange(from, to, force: force);
            }
        }

        /// <summary>
        /// fetch-jra-official処理。JRA公式サイト(www.jra.go.jp)から指定日付範囲の競走結果・払戻金を取得して保存します。
        /// netkeiba(db.netkeiba)が当日結果を翌日まで反映しないラグを解消するため、当日/直近の即時取得に使います。
        /// 公式は約2ヶ月のみ保持のため、過去数年の一括backfillは fetch-jra-range(netkeiba)を使用してください。
        /// </summary>
        /// <param name="args">第2引数に開始日、第3引数に終了日(yyyy-MM-dd)、第4引数に任意の待機ミリ秒を指定します。</param>
        private static void RunFetchJraOfficial(string[] args)
        {
            if (!DateOnly.TryParse(args.ElementAtOrDefault(1), out var from) ||
                !DateOnly.TryParse(args.ElementAtOrDefault(2), out var to))
            {
                CommonLogger.Log("引数が不正です。fetch-jra-official <開始日> <終了日> [待機ミリ秒] (yyyy-MM-dd) の形式で指定してください。");
                return;
            }

            if (int.TryParse(args.ElementAtOrDefault(3), out var delayMs) && delayMs >= 0)
            {
                JRA取込.FetchOfficialRange(from, to, delayMs);
            }
            else
            {
                JRA取込.FetchOfficialRange(from, to);
            }
        }

        /// <summary>
        /// fetch-jra-race処理。単一のnetkeiba race_idを取得・保存します(解析確認・デバッグ用)。
        /// </summary>
        /// <param name="args">第2引数にrace_id(12桁)、第3引数に開催日(yyyy-MM-dd)を指定します。</param>
        private static void RunFetchJraRace(string[] args)
        {
            var raceId = args.ElementAtOrDefault(1) ?? string.Empty;
            if (string.IsNullOrWhiteSpace(raceId) || !DateOnly.TryParse(args.ElementAtOrDefault(2), out var raceDate))
            {
                CommonLogger.Log("引数が不正です。fetch-jra-race <race_id> <開催日(yyyy-MM-dd)> の形式で指定してください。");
                return;
            }

            JRA取込.FetchAndStoreRace(raceId, raceDate);
        }

        /// <summary>
        /// 中央競馬DBが未作成の場合に、現在のEFモデルから全テーブルを生成します。
        /// このプロジェクトはEFマイグレーションを運用しておらず(地方競馬DBも__EFMigrationsHistory無し=EnsureCreatedで生成)、
        /// スキーマはモデル定義を正とするため、新規DBはEnsureCreatedで作成します。
        /// 既にDBが存在する場合は何もしません(既存テーブルの差分追加は行いません)。
        /// </summary>
        private static void RunCreateDatabase()
        {
            using var context = new DBContext();
            var created = context.Database.EnsureCreated();
            CommonLogger.Log(created
                ? "中央競馬DBを新規作成し、全テーブルを生成しました。"
                : "中央競馬DBは既に存在するため、EnsureCreatedは何も行いませんでした。");
        }

        /// <summary>
        /// 実行フォルダに配置されたNLog設定を読み込みます。
        /// 設定ファイルがない場合でも、NLog既定動作に任せて処理を継続します。
        /// </summary>
        private static void ConfigureLogging()
        {
            var configPath = Path.Combine(AppContext.BaseDirectory, "NLog.config");
            if (File.Exists(configPath))
            {
                LogManager.Configuration = new XmlLoggingConfiguration(configPath);
            }
        }

        /// <summary>
        /// 当日の最初のレース1時間前まで待機してから、リアルタイムオッズ取得を開始します。
        /// </summary>
        private static void RunRealtimeOdds()
        {
            var raceDate = DateOnly.FromDateTime(DateTime.Today);
            using var context = new DBContext();

            SleepUntilFirstRacePreparationTime(context, raceDate, "リアルタイムオッズ取得開始時間");
            リアルタイムオッズ.取得(_ => { }, new CancellationTokenSource().Token, true);

            CommonLogger.Log("リアルタイムオッズの取得を終了しました。");
        }

        /// <summary>
        /// 当日のレース情報、競走結果、払戻金を順次取得します。
        /// 最終レースの払戻金がDBに保存された時点で当日分の処理完了と判断します。
        /// </summary>
        private static void RunRealtimeRaceInfo()
        {
            var raceDate = DateOnly.FromDateTime(DateTime.Today);
            using var context = new DBContext();

            SleepUntilFirstRacePreparationTime(context, raceDate, "リアルタイムレース情報取得開始時間");

            var driver = WebDriverHelper.InitializeDriverAndNavigate(MonthlyConveneInfoTopUrl, true);
            if (driver == null)
            {
                return;
            }

            try
            {
                開催日程.FetchAndStoreData(driver, DateTime.Today.Year, DateTime.Today.Month);
                driver.Navigate().GoToUrl(MonthlyConveneInfoTopUrl);

                MonitorTodayRaceInfo(ref driver, raceDate);
            }
            catch (Exception ex)
            {
                CommonLogger.LogError("リアルタイムレース情報取得中にエラーが発生しました。", ex);
            }
            finally
            {
                CommonLogger.Log("リアルタイムレース情報取得を終了しました。");
                Debug.WriteLine("リアルタイムレース情報取得を終了しました。");
                driver?.Quit();
            }
        }

        /// <summary>
        /// nextraceinfo処理。
        /// 翌日の開催情報、当日メニュー、出馬表、競走結果、払戻金、馬別競走履歴を補完します。
        /// </summary>
        private static void RunNextRaceInfo()
        {
            CommonLogger.Log("IN");
            var driver = WebDriverHelper.InitializeDriverAndNavigate(MonthlyConveneInfoTopUrl, true);
            if (driver == null)
            {
                return;
            }

            var raceDateFrom = DateOnly.FromDateTime(DateTime.Today.AddDays(1));
            var raceDateTo = raceDateFrom;
            try
            {
                foreach (var eventYearMonth in EnumerateMonthStarts(raceDateFrom, raceDateTo))
                {
                    開催日程.FetchAndStoreData(driver, eventYearMonth.Year, eventYearMonth.Month);
                    driver.Navigate().GoToUrl(MonthlyConveneInfoTopUrl);
                }

                FetchRaceDataForDateRange(driver, raceDateFrom, raceDateTo);
                FetchHorseHistoriesForDateRange(driver, raceDateFrom, raceDateTo);
            }
            catch (Exception ex)
            {
                CommonLogger.LogError("nextraceinfo処理でエラーが発生しました。", ex);
            }
            finally
            {
                driver.Quit();
                CommonLogger.Log("OUT");
            }
        }

        /// <summary>
        /// fetch-range処理。
        /// 指定日付範囲の当日メニューを起点に、レース情報、競走結果、払戻金の未取得分だけを補完します。
        /// 取得済みレースはスキップするため、中断後に同じ引数で再実行すると続きから処理できます。
        /// 第4引数以降に full を指定すると、各日の当日メニュー(=変更情報も同時に)を取り直してから補完します。
        /// 第4引数以降に compi を指定すると、keiba.go.jpの補完後に極ウマのコンピ指数も同じ期間ぶん補完します
        /// (極ウマは別サイト・要ログインのため、初回のみブラウザで手動ログインが必要。専用Chromeプロファイルで以降は自動)。
        /// </summary>
        /// <param name="args">第1引数にモード名、第2引数に開始日、第3引数に終了日(yyyy-MM-dd)、第4引数以降に任意で full / compi を指定します。</param>
        private static void RunFetchRange(string[] args)
        {
            if (!DateOnly.TryParse(args.ElementAtOrDefault(1), out var dateFrom) ||
                !DateOnly.TryParse(args.ElementAtOrDefault(2), out var dateTo) ||
                dateFrom > dateTo)
            {
                CommonLogger.Log("fetch-rangeの引数が不正です。fetch-range <開始日> <終了日> [full] [compi] の形式で指定してください。");
                return;
            }

            // full指定時は、当日メニューと変更情報も取り直して欠落を補う(成績URLの最新化も兼ねる)。
            var full = args.Skip(3).Any(a => string.Equals(a, "full", StringComparison.OrdinalIgnoreCase));
            // compi指定時は、keiba.go.jpの補完後にコンピ指数(極ウマ)も同期間ぶん補完する。
            var alsoCompi = args.Skip(3).Any(a => string.Equals(a, "compi", StringComparison.OrdinalIgnoreCase));

            CommonLogger.Log($"fetch-range開始: {dateFrom:yyyy-MM-dd} ～ {dateTo:yyyy-MM-dd}{(full ? " (full)" : string.Empty)}");

            IWebDriver? driver = null;
            var raceInfoFetchCount = 0;
            try
            {
                for (var raceDate = dateFrom; raceDate <= dateTo; raceDate = raceDate.AddDays(1))
                {
                    if (full)
                    {
                        // 当日メニューを開催情報の当日メニューURLから取り直す。
                        // これにより当日メニュー・変更情報が最新化され、成績URLも埋まる。
                        var menuUrls = GetEventMenuUrls(raceDate);
                        if (menuUrls.Count > 0)
                        {
                            driver ??= WebDriverHelper.InitializeDriverAndNavigate(string.Empty, true);
                            if (driver == null)
                            {
                                CommonLogger.Log("WebDriverの初期化に失敗したためfetch-rangeを中断します。");
                                return;
                            }

                            foreach (var menuUrl in menuUrls)
                            {
                                当日メニュー.FetchAndStoreData(driver, menuUrl);
                            }
                        }
                    }

                    foreach (var target in GetMissingRaceTargets(raceDate))
                    {
                        if (target.NeedRaceInfo)
                        {
                            // 出馬表の解析はSeleniumが必要なため、共有ドライバを使用します。
                            // 長時間実行でChromeのメモリが肥大化するため、一定件数ごとに再起動します。
                            if (driver != null && raceInfoFetchCount > 0 && raceInfoFetchCount % DriverRestartInterval == 0)
                            {
                                driver.Quit();
                                driver = null;
                            }

                            // 出馬表ページへはFetchAndStoreData内で遷移するため、空で生成する。
                            driver ??= WebDriverHelper.InitializeDriverAndNavigate(string.Empty, true);
                            if (driver == null)
                            {
                                CommonLogger.Log("WebDriverの初期化に失敗したためfetch-rangeを中断します。");
                                return;
                            }

                            レース情報.FetchAndStoreData(driver, target.Menu.出馬表URL);
                            raceInfoFetchCount++;

                            // 大量取得時にkeiba.go.jp側の負荷とレート制限(HTTP 429)を避けるため、
                            // 出馬表取得の間に短い待機を入れます。
                            Thread.Sleep(FetchIntervalMilliseconds);
                        }

                        if (target.NeedResult || target.NeedPayout)
                        {
                            if (target.NeedResult)
                            {
                                競走結果.FetchAndStoreData(null, target.ResultUrl, allowSeleniumFallback: false);
                            }

                            if (target.NeedPayout)
                            {
                                払戻金.FetchAndStoreData(null, target.ResultUrl, allowSeleniumFallback: false);
                            }

                            // 競走結果・払戻金はHTTP取得のため、連続アクセスでkeiba.go.jp側に
                            // スロットリングされてタイムアウトするのを避けるため、レース間に待機を入れる。
                            Thread.Sleep(FetchIntervalMilliseconds);
                        }
                    }

                    CommonLogger.Log($"fetch-range進捗: {raceDate:yyyy-MM-dd} まで処理済み(出馬表取得 {raceInfoFetchCount}件)");
                }
            }
            finally
            {
                driver?.Quit();
                CommonLogger.Log($"fetch-range終了: 出馬表取得 {raceInfoFetchCount}件");
            }

            // コンピ指数(極ウマ)の補完。keiba.go.jpのChromeを閉じた後、専用プロファイルのChromeで実行する。
            if (alsoCompi)
            {
                CommonLogger.Log("fetch-range: コンピ指数(極ウマ)の補完を実行します。初回はブラウザでの手動ログインが必要です(以降はプロファイルで自動)。");
                コンピ指数取得.取得範囲(dateFrom, dateTo);
            }
        }

        /// <summary>
        /// 出馬表取得で共有するChromeを再起動する間隔(取得レース数)。
        /// </summary>
        private const int DriverRestartInterval = 500;

        /// <summary>
        /// fetch-rangeで出馬表を連続取得する際の待機時間(ミリ秒)。
        /// </summary>
        private const int FetchIntervalMilliseconds = 700;

        /// <summary>
        /// 指定開催日の開催情報から、当日メニューURL一覧を取得します。
        /// fullモードで当日メニュー・変更情報を取り直す際の入口として使用します。
        /// </summary>
        /// <param name="raceDate">処理対象の開催日。</param>
        /// <returns>当日メニューURL一覧。開催情報が無い日は空リスト。</returns>
        private static List<string> GetEventMenuUrls(DateOnly raceDate)
        {
            using var context = new DBContext();
            return context.開催情報
                .AsNoTracking()
                .Where(d => d.開催日 == raceDate && d.当日メニューURL != "")
                .Select(d => d.当日メニューURL)
                .Distinct()
                .ToList();
        }

        /// <summary>
        /// 当日メニューの成績URLが空の場合に、出馬表URLから成績URLを生成します。
        /// 成績ページ(RaceMarkTable)と出馬表ページ(DebaTable)はクエリが共通で、パスだけが異なります。
        /// 過去日付ではメニューページに成績リンクが載らず成績URLが空のまま保存されるため、この補完が必要です。
        /// </summary>
        /// <param name="menu">対象の当日メニュー。</param>
        /// <returns>成績URL。生成できない場合は空文字列。</returns>
        private static string ResolveResultUrl(当日メニューモデル menu)
        {
            if (!string.IsNullOrWhiteSpace(menu.成績URL))
            {
                return menu.成績URL;
            }

            if (!string.IsNullOrWhiteSpace(menu.出馬表URL) && menu.出馬表URL.Contains("DebaTable"))
            {
                return menu.出馬表URL.Replace("DebaTable", "RaceMarkTable");
            }

            return string.Empty;
        }

        /// <summary>
        /// 指定開催日の当日メニューから、レース情報・競走結果・払戻金のいずれかが未取得のレースを抽出します。
        /// 取得状況の判定は各テーブルの既存キーをメモリへ読み込んで行うため、レースごとのDB問い合わせは発生しません。
        /// </summary>
        /// <param name="raceDate">処理対象の開催日。</param>
        /// <returns>未取得データの種別フラグと、競走結果・払戻金の取得先URLを付けた一覧。</returns>
        private static List<(当日メニューモデル Menu, bool NeedRaceInfo, bool NeedResult, bool NeedPayout, string ResultUrl)> GetMissingRaceTargets(DateOnly raceDate)
        {
            using var context = new DBContext();

            var menus = context.当日メニュー
                .AsNoTracking()
                .Where(m => m.開催日 == raceDate && m.レース番号 > 0)
                .OrderBy(m => m.開催場所)
                .ThenBy(m => m.レース番号)
                .ToList();

            if (menus.Count == 0)
            {
                return new List<(当日メニューモデル, bool, bool, bool, string)>();
            }

            var raceInfoKeys = context.レース情報
                .AsNoTracking()
                .Where(d => d.開催日 == raceDate)
                .Select(d => new { d.開催場所, d.レース番号 })
                .Distinct()
                .ToHashSet();

            // 速報段階では着順上位だけ・走破時計0で保存されることがある。
            // 走破時計が入った行が1つでもあるレースのみ「取得済み」とみなし、
            // 全行が走破時計0(速報)のレースは未完了として確定版を取り直す。
            var resultKeys = context.競走結果
                .AsNoTracking()
                .Where(d => d.開催日 == raceDate && d.走破時計 > 0)
                .Select(d => new { d.開催場所, d.レース番号 })
                .Distinct()
                .ToHashSet();

            var payoutKeys = context.払戻金
                .AsNoTracking()
                .Where(d => d.開催日 == raceDate)
                .Select(d => new { d.開催場所, d.レース番号 })
                .Distinct()
                .ToHashSet();

            return menus
                .Select(menu =>
                {
                    var resultUrl = ResolveResultUrl(menu);
                    return (
                        Menu: menu,
                        NeedRaceInfo: !string.IsNullOrWhiteSpace(menu.出馬表URL)
                            && !raceInfoKeys.Contains(new { menu.開催場所, menu.レース番号 }),
                        NeedResult: !string.IsNullOrWhiteSpace(resultUrl)
                            && !resultKeys.Contains(new { menu.開催場所, menu.レース番号 }),
                        NeedPayout: !string.IsNullOrWhiteSpace(resultUrl)
                            && !payoutKeys.Contains(new { menu.開催場所, menu.レース番号 }),
                        ResultUrl: resultUrl);
                })
                .Where(t => t.NeedRaceInfo || t.NeedResult || t.NeedPayout)
                .ToList();
        }

        /// <summary>
        /// 競走結果テーブルに着順はあるが三・四コーナー通過順が未登録の平地レースを、成績URLから再取得して補完します。
        /// ばんえい競馬は通常のコーナー通過順を持たないため、場名の末尾が「ば」のレースは対象外にします。
        /// 第2引数に数値を指定した場合は、その件数だけを処理するため、件数が多いDBでは分割実行できます。
        /// 第3引数に数値を指定した場合は、その並列数で補完します。
        /// </summary>
        /// <param name="args">第1引数にモード名、第2引数に任意の最大処理件数、第3引数に任意の並列数を指定します。</param>
        private static void RunBackfillCornerPositions(string[] args)
        {
            var limit = ParseOptionalPositiveInt(args.ElementAtOrDefault(1));
            var parallelism = ParseOptionalPositiveInt(args.ElementAtOrDefault(2)) ?? 1;
            var before = CountRaceResultsMissingCornerPositions();
            CommonLogger.Log($"コーナー通過順補完対象: {before.RaceCount}レース {before.RowCount}行");

            var targets = GetRaceResultUrlsMissingCornerPositions(limit);
            if (targets.Count == 0)
            {
                CommonLogger.Log("コーナー通過順を補完する対象レースはありません。");
                return;
            }

            if (parallelism <= 1)
            {
                for (var index = 0; index < targets.Count; index++)
                {
                    BackfillCornerPosition(targets[index], index + 1, targets.Count);
                }
            }
            else
            {
                CommonLogger.Log($"コーナー通過順補完を並列数{parallelism}で実行します。");
                var parallelOptions = new ParallelOptions { MaxDegreeOfParallelism = parallelism };
                Parallel.ForEach(
                    targets.Select((target, index) => new { Target = target, Sequence = index + 1 }),
                    parallelOptions,
                    item => BackfillCornerPosition(item.Target, item.Sequence, targets.Count));
            }

            var after = CountRaceResultsMissingCornerPositions();
            CommonLogger.Log($"コーナー通過順補完完了: 残り {after.RaceCount}レース {after.RowCount}行");
        }

        /// <summary>
        /// 1レース分の成績URLを再取得し、競走結果テーブルのコーナー通過順を更新します。
        /// </summary>
        /// <param name="target">補完対象レースの当日メニュー情報。</param>
        /// <param name="sequence">今回の補完処理内での処理番号。</param>
        /// <param name="total">今回の補完処理で扱う総レース数。</param>
        private static void BackfillCornerPosition(当日メニューモデル target, int sequence, int total)
        {
            CommonLogger.Log($"コーナー通過順補完 {sequence}/{total}: {target.開催日:yyyy-MM-dd} {target.開催場所} {target.レース番号}R");
            競走結果.FetchAndStoreData(null, target.成績URL, allowSeleniumFallback: false);
        }

        /// <summary>
        /// 正の整数として扱える任意引数を解析します。
        /// 解析できない場合は件数制限なしを表すnullを返します。
        /// </summary>
        /// <param name="value">コマンドラインから受け取った文字列。</param>
        /// <returns>正の整数ならその値、未指定または不正値ならnull。</returns>
        private static int? ParseOptionalPositiveInt(string? value)
        {
            if (int.TryParse(value, out var result) && result > 0)
            {
                return result;
            }

            return null;
        }

        /// <summary>
        /// 着順は保存済みだが三・四コーナー通過順が未登録の競走結果行数とレース数を数えます。
        /// </summary>
        /// <returns>未登録行数と未登録レース数。</returns>
        private static (int RowCount, int RaceCount) CountRaceResultsMissingCornerPositions()
        {
            using var context = new DBContext();
            var missingRows = GetMissingCornerPositionQuery(context);

            var rowCount = missingRows.Count();
            var raceCount = missingRows
                .Select(row => new { row.開催日, row.開催場所, row.レース番号 })
                .Distinct()
                .Count();

            return (rowCount, raceCount);
        }

        /// <summary>
        /// コーナー通過順が未登録の競走結果を持つレースの成績URL一覧を取得します。
        /// </summary>
        /// <param name="limit">最大取得件数。nullの場合は全件取得します。</param>
        /// <returns>補完対象レースの開催日、開催場所、レース番号、成績URL。</returns>
        private static List<当日メニューモデル> GetRaceResultUrlsMissingCornerPositions(int? limit)
        {
            using var context = new DBContext();
            var query = (
                from menu in context.当日メニュー.AsNoTracking()
                where menu.成績URL != ""
                where !menu.開催場所.EndsWith("ば")
                where context.競走結果.Any(result =>
                    result.開催日 == menu.開催日 &&
                    result.開催場所 == menu.開催場所 &&
                    result.レース番号 == menu.レース番号 &&
                    result.着順 > 0 &&
                    result.三コーナー == 0 &&
                    result.四コーナー == 0)
                orderby menu.開催日, menu.開催場所, menu.レース番号
                select menu
            ).Distinct();

            if (limit.HasValue)
            {
                query = query.Take(limit.Value);
            }

            return query.ToList();
        }

        /// <summary>
        /// 着順が保存されている一方で三・四コーナー通過順が0の競走結果行を抽出します。
        /// </summary>
        /// <param name="context">競走結果と当日メニューを参照するDBコンテキスト。</param>
        /// <returns>補完候補となる競走結果行の問い合わせ。</returns>
        private static IQueryable<競走結果モデル> GetMissingCornerPositionQuery(DBContext context)
        {
            return
                from result in context.競走結果.AsNoTracking()
                where result.着順 > 0
                where result.三コーナー == 0 && result.四コーナー == 0
                where !result.開催場所.EndsWith("ば")
                where context.当日メニュー.Any(menu =>
                    menu.開催日 == result.開催日 &&
                    menu.開催場所 == result.開催場所 &&
                    menu.レース番号 == result.レース番号 &&
                    menu.成績URL != "")
                select result;
        }

        /// <summary>
        /// 指定日付範囲に含まれる月の初日を列挙します。
        /// 月をまたぐ期間でも、必要な開催日程を漏れなく取得するために使用します。
        /// </summary>
        private static IEnumerable<DateOnly> EnumerateMonthStarts(DateOnly raceDateFrom, DateOnly raceDateTo)
        {
            var month = new DateOnly(raceDateFrom.Year, raceDateFrom.Month, 1);
            var lastMonth = new DateOnly(raceDateTo.Year, raceDateTo.Month, 1);

            while (month <= lastMonth)
            {
                yield return month;
                month = month.AddMonths(1);
            }
        }

        /// <summary>
        /// 当日の最初のレースの1時間前まで待機します。
        /// 当日メニューが未作成の場合は待機せず、そのまま後続処理へ進みます。
        /// </summary>
        private static void SleepUntilFirstRacePreparationTime(DBContext context, DateOnly raceDate, string logLabel)
        {
            var firstRace = context.当日メニュー
                .Where(h => h.開催日 == raceDate)
                .Where(h => h.レース番号 > 0)
                .OrderBy(h => h.発走時刻)
                .FirstOrDefault();

            if (firstRace == null)
            {
                return;
            }

            var fetchStartTime = firstRace.発走時刻.AddHours(-1);
            var sleepTime = (int)(fetchStartTime - DateTime.Now).TotalMilliseconds;
            if (sleepTime <= 0)
            {
                return;
            }

            var timeSpan = TimeSpan.FromMilliseconds(sleepTime);
            CommonLogger.Log($"これから{timeSpan.Hours:D2}時間{timeSpan.Minutes:D2}分停止する。{logLabel}: {fetchStartTime}");
            Thread.Sleep(sleepTime);
        }

        /// <summary>
        /// 未取得の払戻金が残っているレースを対象に、当日メニュー、出馬表、競走結果、払戻金を更新します。
        /// 最終レースの払戻金が登録されたら処理を終了します。
        /// </summary>
        private static void MonitorTodayRaceInfo(ref IWebDriver? driver, DateOnly raceDate)
        {
            var isRaceFinished = false;

            do
            {
                // ブラウザがクラッシュしていると以降の全コマンドがタイムアウトし続け、
                // 一晩中エラーで空転するため、各周回の冒頭で生存確認し、死んでいれば作り直します。
                driver = WebDriverHelper.EnsureAlive(driver, true);
                if (driver == null)
                {
                    CommonLogger.Log("WebDriverを再初期化できませんでした。30秒後に再試行します。");
                    Thread.Sleep(30000);
                    continue;
                }

                using var context = new DBContext();

                RefreshTodayMenusForUnpaidRaces(context, driver, raceDate);

                foreach (var race in GetFirstUnpaidRaceByCourse(context, raceDate))
                {
                    FetchRaceInfoResultAndPayout(driver, race);
                }

                isRaceFinished = IsLastRacePayoutStored(context, raceDate);
            } while (!isRaceFinished);
        }

        /// <summary>
        /// 払戻金が未登録のレースがある開催場所について、開催情報テーブルの当日メニューURLから一覧を更新します。
        /// 当日メニューを先に更新することで、成績URLの掲載状況も最新化します。
        /// </summary>
        private static void RefreshTodayMenusForUnpaidRaces(DBContext context, IWebDriver driver, DateOnly raceDate)
        {
            var todaysMenuUrls = (
                from menu in context.当日メニュー
                where menu.開催日 == raceDate
                where !context.払戻金.Any(p =>
                    p.開催日 == menu.開催日 &&
                    p.開催場所 == menu.開催場所 &&
                    p.レース番号 == menu.レース番号)
                join info in context.開催情報
                    on new { menu.開催日, menu.開催場所 } equals new { info.開催日, info.開催場所 }
                select info.当日メニューURL
            ).Distinct().ToList();

            if (todaysMenuUrls.Count == 0)
            {
                CommonLogger.Log($"全てのレースの競走結果は更新されています。開催日: {raceDate}");
                return;
            }

            foreach (var todaysMenuUrl in todaysMenuUrls)
            {
                当日メニュー.FetchAndStoreData(driver, todaysMenuUrl);
            }
        }

        /// <summary>
        /// 開催場所ごとに、払戻金が未登録の最小レース番号を取得します。
        /// リアルタイム処理では各場の直近未処理レースから順に進めるため、この抽出結果を使用します。
        /// </summary>
        private static List<当日メニューモデル> GetFirstUnpaidRaceByCourse(DBContext context, DateOnly raceDate)
        {
            var minRaceNumbers = context.当日メニュー
                .Where(d => d.開催日 == raceDate && d.成績URL != null)
                .Where(d => !context.払戻金.Any(p =>
                    p.開催日 == d.開催日 &&
                    p.開催場所 == d.開催場所 &&
                    p.レース番号 == d.レース番号))
                .GroupBy(d => d.開催場所)
                .Select(g => new
                {
                    開催場所 = g.Key,
                    最小レース番号 = g.Min(x => x.レース番号)
                });

            return (
                from menu in context.当日メニュー
                join minRace in minRaceNumbers
                    on new { menu.開催場所, menu.レース番号 }
                    equals new { minRace.開催場所, レース番号 = minRace.最小レース番号 }
                where menu.開催日 == raceDate
                      && menu.成績URL != null
                      && !context.払戻金.Any(p =>
                          p.開催日 == menu.開催日 &&
                          p.開催場所 == menu.開催場所 &&
                          p.レース番号 == menu.レース番号)
                orderby menu.発走時刻
                select menu
            ).ToList();
        }

        /// <summary>
        /// 出馬表URLと成績URLを使い、レース情報、競走結果、払戻金を順に取得します。
        /// </summary>
        private static void FetchRaceInfoResultAndPayout(IWebDriver driver, 当日メニューモデル race)
        {
            レース情報.FetchAndStoreData(driver, race.出馬表URL);
            競走結果.FetchAndStoreData(driver, race.成績URL);
            払戻金.FetchAndStoreData(driver, race.成績URL);
        }

        /// <summary>
        /// 当日の最終発走時刻を持つレースに払戻金が登録されているか確認します。
        /// 払戻金の存在をもって、その開催日のレース終了を判断します。
        /// </summary>
        private static bool IsLastRacePayoutStored(DBContext context, DateOnly raceDate)
        {
            var lastRaceStartTime = context.当日メニュー
                .Where(d => d.開催日 == raceDate)
                .Max(d => d.発走時刻);

            return context.当日メニュー
                .Where(m => m.開催日 == raceDate && m.発走時刻 == lastRaceStartTime)
                .Join(
                    context.払戻金,
                    menu => new { menu.開催日, menu.開催場所, menu.レース番号 },
                    payout => new { payout.開催日, payout.開催場所, payout.レース番号 },
                    (menu, payout) => menu)
                .Any();
        }

        /// <summary>
        /// 指定範囲の開催情報から当日メニューを取得し、各レースの出馬表、競走結果、払戻金を保存します。
        /// </summary>
        private static void FetchRaceDataForDateRange(IWebDriver driver, DateOnly raceDateFrom, DateOnly raceDateTo)
        {
            List<string> menuUrls;
            using (var context = new DBContext())
            {
                menuUrls = context.開催情報
                    .AsNoTracking()
                    .Where(d => d.開催日 >= raceDateFrom && d.開催日 <= raceDateTo)
                    .OrderBy(d => d.開催日)
                    .ThenBy(d => d.開催場所)
                    .Select(d => d.当日メニューURL)
                    .Where(url => url != "")
                    .Distinct()
                    .ToList();
            }

            foreach (var url in menuUrls)
            {
                当日メニュー.FetchAndStoreData(driver, url);
            }

            for (var raceDate = raceDateFrom; raceDate <= raceDateTo; raceDate = raceDate.AddDays(1))
            {
                using var context = new DBContext();
                var raceUrls = context.当日メニュー
                    .AsNoTracking()
                    .Where(d => d.開催日 == raceDate)
                    .OrderBy(d => d.開催場所)
                    .ThenBy(d => d.レース番号)
                    .Select(d => new { d.出馬表URL, d.成績URL })
                    .ToList();

                foreach (var url in raceUrls)
                {
                    if (!string.IsNullOrWhiteSpace(url.出馬表URL))
                    {
                        レース情報.FetchAndStoreData(driver, url.出馬表URL);
                    }

                    if (!string.IsNullOrWhiteSpace(url.成績URL))
                    {
                        競走結果.FetchAndStoreData(driver, url.成績URL);
                        払戻金.FetchAndStoreData(driver, url.成績URL);
                    }
                }
            }
        }

        /// <summary>
        /// 指定範囲に出走した馬について、馬情報ページから過去競走履歴を補完します。
        /// </summary>
        private static void FetchHorseHistoriesForDateRange(IWebDriver driver, DateOnly raceDateFrom, DateOnly raceDateTo)
        {
            for (var raceDate = raceDateFrom; raceDate <= raceDateTo; raceDate = raceDate.AddDays(1))
            {
                using var context = new DBContext();
                var races = context.レース情報
                    .AsNoTracking()
                    .Where(d => d.開催日 == raceDate)
                    .Where(d => d.馬情報URL != "")
                    .OrderBy(d => d.開催場所)
                    .ThenBy(d => d.レース番号)
                    .ThenBy(d => d.馬名)
                    .ToList();

                foreach (var race in races)
                {
                    RaceHistoryCompleter.FetchAndStoreData(driver, race.馬情報URL, race.馬名);
                }
            }
        }
    }
}
