// 役割: 手動操作用フォームのイベント処理をまとめるメイン画面コードです。
// 開催情報、当日メニュー、レース情報、競走結果、払戻金、馬別履歴補完をボタン操作から呼び出します。
// DBの欠落補完やリアルタイム監視など、運用時に人が確認しながら動かす処理をここに集約しています。
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using OpenQA.Selenium;
using System;
using System.Diagnostics;
using System.Linq.Dynamic.Core.Tokenizer;
using System.Security.Policy;
using UglyToad.PdfPig.Tokens;
using 中央競馬.RaceAnalyzer;
using 中央競馬.Services; // 開催日程取得クラスを使用する名前空間
using 中央競馬.共通.Data; // DB を使用する名前空間
using 中央競馬.共通.Libraly; // ログ機能を提供するカスタムクラスの名前空間
using 中央競馬.共通.Models; // データベースモデルを使用する名前空間
using static 中央競馬.RaceAnalyzer.RaceResultComparer;
namespace AppController
{
    public partial class AppController : Form
    {
        private CancellationTokenSource _oddsCancellationTokenSource = new CancellationTokenSource(); // 初期化を追加
        private CancellationTokenSource _raceInfoCts = new CancellationTokenSource();
        private CancellationTokenSource _realtimeraceInfoCts = new CancellationTokenSource();
        private CancellationTokenSource _raceResultCts = new CancellationTokenSource();
        private readonly bool _getDayliyRace;
        private readonly bool _getRealtimeInfo;
        /// <summary>
        /// AppControllerフォームを初期化し、起動時に自動実行する処理フラグを保持します。
        /// </summary>
        /// <param name="getDayliyRace">フォーム起動直後に日次レース情報取得を自動実行する場合はtrue。</param>
        /// <param name="getRealtimeInfo">フォーム起動直後にリアルタイム情報取得を自動実行する場合はtrue。</param>
        public AppController(bool getDayliyRace, bool getRealtimeInfo)
        {
            InitializeComponent();
            _getDayliyRace = getDayliyRace;
            _getRealtimeInfo = getRealtimeInfo;
        }

        /// <summary>
        /// フォーム読み込み時に初期データを取得し、画面操作に必要な状態を準備します。
        /// </summary>
        /// <param name="sender">イベントを発生させた画面コントロール。</param>
        /// <param name="e">イベントに付随する引数。</param>
        private async void AppController_Load(object sender, EventArgs e)
        {
            Logger.Log($"IN _getDayliyRace={_getDayliyRace},_isGetRealtimeInfo={_getRealtimeInfo}");
            if (_getDayliyRace)
            {
                Logger.Log("スケジューラからの起動 - RaceHistoryCompleterを自動実行します。");
                string baseUrl = "https://www.keiba.go.jp/KeibaWeb/MonthlyConveneInfo/MonthlyConveneInfoTop";
                IWebDriver? driver = WebDriverHelper.InitializeDriverAndNavigate(baseUrl, true);
                if(driver == null)
                {
                    return;
                }
                try
                {
                    var configuration = new ConfigurationBuilder()
                        .SetBasePath(AppContext.BaseDirectory)
                        .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
                        .Build();

                    var options = new DbContextOptionsBuilder<DBContext>()
                        .UseSqlServer(configuration.GetConnectionString("DefaultConnection"))
                        .Options;

                    using var context = new DBContext(options);

                    // 月初：選択された月の1日を指定
                    var fromDateTime = DateTime.Today;
                    var RaceDate_From = new DateOnly(fromDateTime.Year, fromDateTime.Month, 1);

                    // 月末：選択された月の最終日を指定
                    var toDateTime = DateTime.Today;
                    var lastDay = DateTime.DaysInMonth(toDateTime.Year, toDateTime.Month);
                    var RaceDate_To = new DateOnly(toDateTime.Year, toDateTime.Month, lastDay);
                    for (DateOnly EventYearMonth = RaceDate_From; EventYearMonth <= RaceDate_To; EventYearMonth = EventYearMonth.AddMonths(1))
                    {
                        開催日程.FetchAndStoreData(driver, EventYearMonth.Year, EventYearMonth.Month);
                    }

                    RaceDate_From = DateOnly.Parse(toDateTime.ToString("yyyy/MM/dd"));
                    RaceDate_To = DateOnly.Parse(toDateTime.ToString("yyyy/MM/dd"));

                    foreach (var url in context.開催情報.Where(d => d.開催日 >= RaceDate_From && d.開催日 <= RaceDate_To).Select(d => d.当日メニューURL))
                    {
                        当日メニュー.FetchAndStoreData(driver, url);
                    }
                    for (DateOnly RaceDate = RaceDate_From; RaceDate <= RaceDate_To; RaceDate = RaceDate.AddDays(1))
                    {
                        foreach (var url in context.当日メニュー
                                     .Where(d => d.開催日 == RaceDate)
                                     .OrderBy(d => d.開催場所).ThenBy(d => d.レース番号)
                                     .Select(d => new { d.出馬表URL, d.成績URL }))
                        {
                            レース情報.FetchAndStoreData(driver, url.出馬表URL);
                        }
                        foreach (var race in context.レース情報
                                     .Where(d => d.開催日 == RaceDate)
                                     .OrderBy(d => d.開催場所).ThenBy(d => d.レース番号).ThenBy(d => d.馬名)
                                     .ToList())
                        {
                            RaceHistoryCompleter.FetchAndStoreData(driver, race.馬情報URL, race.馬名);
                        }
                    }

                    for (DateOnly RaceDate = RaceDate_From.AddDays(-1); RaceDate <= RaceDate_To; RaceDate = RaceDate.AddDays(1))
                    {
                        foreach (var url in context.当日メニュー
                                     .Where(d => d.開催日 == RaceDate)
                                     .OrderBy(d => d.開催場所).ThenBy(d => d.レース番号)
                                     .Select(d => new { d.出馬表URL, d.成績URL }))
                        {
                            競走結果.FetchAndStoreData(driver, url.成績URL);
                            払戻金.FetchAndStoreData(driver, url.成績URL);
                        }
                    }
                    if (_getRealtimeInfo)
                    {
                        var realtimeodds = Task.Run(() =>リアルタイムオッズ.取得( _ => { }, _oddsCancellationTokenSource.Token, true));
                        var realtimeraceinfo = Task.Run(() => getRealtimeRaceInfo(_oddsCancellationTokenSource.Token, true));

                        await Task.WhenAll(realtimeodds, realtimeraceinfo); // すべての非同期処理が完了するのを待つ
                    }
                }
                catch (Exception ex)
                {
                    Logger.LogError("エラーが発生しました。", ex);
                }
                if(driver != null) driver.Quit();
                Logger.Log("OUT");
                // 実行完了後にアプリを自動終了させる場合：
                Logger.Log("自動処理が完了したため、アプリケーションを終了します。");
    //                Application.Exit(); // スケジューラからの起動時はアプリケーションを終了
                this.Close(); // フォームを閉じる
                return;
            }

            // スケジューラ以外からの起動時（通常起動）
            Logger.Log("通常起動 - UIを初期化します。");

            timer_CurrentDateTime.Enabled = true;
            timer_CurrentDateTime.Interval = 1000;
            timer_CurrentDateTime.Tick += Timer_CurrentDateTime_Tick!;
            timer_CurrentDateTime.Start();

            InitializeForm(); // 通常のUI初期化
        }
        /// <summary>
        /// フォームの初期表示値とボタン状態を設定します。
        /// </summary>
        private void InitializeForm()
        {
            realtimeodds_groupBox.Enabled = true; // リアルタイムオッズのグループボックスを有効化
            realtimeodds_start_button.Enabled = true; // 開始ボタンを有効化
            realtimeodds_stop_button.Enabled = false;
            /*
             * 競争成績グループ初期化
             */
            this.raceInfo_start_button.Enabled = true;
            this.raceInfo_stop_button.Enabled = false;
            this.raceInfo_from_dateTimePicker.Enabled = true;
            this.raceInfo_to_dateTimePicker.Enabled = true;
            this.raceInfo_from_dateTimePicker.Format = System.Windows.Forms.DateTimePickerFormat.Short;
            this.raceInfo_to_dateTimePicker.Format = System.Windows.Forms.DateTimePickerFormat.Short;
            this.raceInfo_from_dateTimePicker.Value = DateTime.Today;
            this.raceInfo_to_dateTimePicker.Value = DateTime.Today.AddDays(7);

            realtimeraceinfo_groupBox.Enabled = true; // リアルタイムレース情報のグループボックスを有効化
            realtimeraceinfo_start_button.Enabled = true;
            realtimeraceinfo_stop_button.Enabled = false;

            RaceAnalyzer_groupBox.Enabled = true; // レースアナライザのグループボックス
            RaceAnalyzer_RaceDate.Format = System.Windows.Forms.DateTimePickerFormat.Short;
            RaceAnalyzer_RaceDate.Value = DateTime.Today;

        }
        /// <summary>
        /// スレッドからステータスメッセージを更新するメソッド。
        /// </summary>
        /// <param name="message">画面に表示する処理状況メッセージ。</param>
        public void UpdateStatusMessage(string message)
        {
            if (this.InvokeRequired)
            {
                this.Invoke(() => toolStripStatusLabel_notify.Text = message);
            }
            else
            {
                toolStripStatusLabel_notify.Text = message;
            }
        }
        /// <summary>
        /// タイマー発火時に現在日時の表示を更新します。
        /// </summary>
        /// <param name="sender">イベントを発生させた画面コントロール。</param>
        /// <param name="e">イベントに付随する引数。</param>
        private void Timer_CurrentDateTime_Tick(object sender, EventArgs e)
        {
            toolStripStatusLabel_CurrentDateTime.Text = DateTime.Now.ToString("yyyy/MM/dd HH:mm:ss");
        }
        /// <summary>
        /// 最初のレース開始前に、取得開始予定時刻までの待機状態を通知します。
        /// </summary>
        /// <param name="firstrace">当日で最も早い発走時刻。</param>
        /// <param name="oddsFetchStartTime">リアルタイムオッズ取得を開始する予定時刻。</param>
        /// <returns>このメソッド内で開始した非同期処理の完了を表すTask。</returns>
        private async Task CheckRaceTimeAndNotify(DateTime firstrace, DateTime oddsFetchStartTime)
        {

            // 発走時刻まで待機（秒単位で精度を合わせたい場合はここでループさせても良い）
            while (DateTime.Now < oddsFetchStartTime)
            {
                // 発走時刻までの残り時間を計算
                TimeSpan remaining = oddsFetchStartTime - DateTime.Now;
                toolStripStatusLabel_notify.Text = $"[通知] 第1競走発走時刻({firstrace.ToString("HH:mm")}) オッズ取得開始まで残り{remaining.Hours:D2}:{remaining.Minutes:D2}:{remaining.Seconds:D2}";
                await Task.Delay(1000); // 1秒おきに更新
            }
            toolStripStatusLabel_notify.Text = "レースが開始されました。";
        }

        /// <summary>
        /// 別スレッドを起こしてリアルタイムオッズを取得するボタンのクリックイベントハンドラ。
        /// </summary>
        /// <param name="sender">イベントを発生させた画面コントロール。</param>
        /// <param name="e">イベントに付随する引数。</param>
        private async void realtimeodds_strat_button_Click(object sender, EventArgs e)
        {
            // ボタンを無効化して連打を防止（任意）
            realtimeodds_start_button.Enabled = false;
            realtimeodds_stop_button.Enabled = true; // 停止ボタンを有効化
            using var context = new DBContext();
            DateOnly RaceDate = DateOnly.Parse(DateTime.Today.ToString("yyyy/MM/dd"));

            var firstrace = context.当日メニュー
                .Where(h => h.開催日 == RaceDate)
                .Where(h => h.レース番号 > 0)
                .OrderBy(h => h.発走時刻).FirstOrDefault();


            if (firstrace != null)
            {
                DateTime oddsFetchStartTime = firstrace.発走時刻.AddHours(-1); // 発走時刻の1時間前を設定
                if (DateTime.Now < oddsFetchStartTime)
                {
                    await CheckRaceTimeAndNotify(firstrace.発走時刻, oddsFetchStartTime);
                }
            }

            // 非同期でリアルタイムオッズを取得
            _oddsCancellationTokenSource = new CancellationTokenSource();
            var token = _oddsCancellationTokenSource.Token;
            var task=Task.Run(() =>
            {
                try
                {
                    string[] args = new string[0]; // 必要に応じて引数をセット
                    リアルタイムオッズ.取得( message =>
                    {
                        this.Invoke(() => UpdateStatusMessage(message));
                    }, token,false);
                }
                catch (Exception ex)
                {
                    // UIスレッドに戻ってエラー表示
                    this.Invoke(() =>
                    {
                        MessageBox.Show($"エラーが発生しました: {ex.Message}");
                    });
                }
                finally
                {
                    // UIスレッドでボタンを再有効化
                    this.Invoke(() => realtimeodds_start_button.Enabled = true);
                }
            });
        }
        /// <summary>
        /// リアルタイムオッズの取得を停止するボタンのクリックイベントハンドラ。
        /// </summary>
        /// <param name="sender">イベントを発生させた画面コントロール。</param>
        /// <param name="e">イベントに付随する引数。</param>
        private void realtimeodds_stop_button_Click(object sender, EventArgs e)
        {
            _oddsCancellationTokenSource?.Cancel();
        }
        /// <summary>
        /// レース情報の取得を開始するボタンのクリックイベントハンドラ。
        /// </summary>
        /// <param name="sender">イベントを発生させた画面コントロール。</param>
        /// <param name="e">イベントに付随する引数。</param>
        private void raceInfo_start_button_Click(object sender, EventArgs e)
        {
            Logger.Log("IN");
            try
            {
                // ボタンを無効化して連打を防止
                this.raceInfo_start_button.Enabled = false;
                this.raceInfo_stop_button.Enabled = true; // 停止ボタンを有効化
                this.raceInfo_from_dateTimePicker.Enabled = false;
                this.raceInfo_to_dateTimePicker.Enabled = false;
                _raceInfoCts = new CancellationTokenSource();
                Task.Run(() => getRaceInfo(_raceInfoCts.Token));
            }
            catch (Exception ex)
            {
                Logger.LogError("エラーが発生しました。", ex);
            }
            finally
            {
                Logger.Log("OUT");
            }
        }

        /// <summary>
        /// レース情報取得停止ボタンの押下処理です。
        /// </summary>
        /// <param name="sender">イベントを発生させた画面コントロール。</param>
        /// <param name="e">イベントに付随する引数。</param>
        private void raceInfo_stop_button_Click(object sender, EventArgs e)
        {
            this.raceInfo_start_button.Enabled = true;
            this.raceInfo_stop_button.Enabled = false;
            _raceInfoCts?.Cancel();
            Logger.Log("getRaceInfo のキャンセルをリクエストしました。");
        }
        /// <summary>
        /// 指定期間の開催情報、当日メニュー、レース情報、競走結果、払戻金、馬別履歴を取得します。
        /// </summary>
        /// <param name="token">処理停止要求を受け取るキャンセルトークン。</param>
        /// <param name="isHeadress">Chromeをヘッドレスモードで起動する場合はtrue。</param>
        private void getRaceInfo(CancellationToken token, bool isHeadress=false)
        {
            Logger.Log("IN");
            string baseUrl = "https://www.keiba.go.jp/KeibaWeb/MonthlyConveneInfo/MonthlyConveneInfoTop";
            IWebDriver? driver = WebDriverHelper.InitializeDriverAndNavigate(baseUrl, isHeadress);
            if (driver == null)
            {
                return;
            }

            var racedatefrom = this.raceInfo_from_dateTimePicker.Value;

            try
            {
                var configuration = new ConfigurationBuilder()
                    .SetBasePath(AppContext.BaseDirectory)
                    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
                    .Build();

                var options = new DbContextOptionsBuilder<DBContext>()
                    .UseSqlServer(configuration.GetConnectionString("DefaultConnection"))
                    .Options;

                if (token.IsCancellationRequested) return;
                using var context = new DBContext(options);

                // 月初：選択された月の1日を指定
                var fromDateTime = raceInfo_from_dateTimePicker.Value;
                var RaceDate_From = new DateOnly(fromDateTime.Year, fromDateTime.Month, 1);

                // 月末：選択された月の最終日を指定
                var toDateTime = raceInfo_to_dateTimePicker.Value;
                var lastDay = DateTime.DaysInMonth(toDateTime.Year, toDateTime.Month);
                var RaceDate_To = new DateOnly(toDateTime.Year, toDateTime.Month, lastDay);


                for (DateOnly EventYearMonth = RaceDate_From; EventYearMonth <= RaceDate_To; EventYearMonth = EventYearMonth.AddMonths(1))
                {
                    if (token.IsCancellationRequested) return;
                    開催日程.FetchAndStoreData(driver, EventYearMonth.Year, EventYearMonth.Month);
                }

                RaceDate_From = DateOnly.Parse(raceInfo_from_dateTimePicker.Value.ToString("yyyy/MM/dd"));
                RaceDate_To = DateOnly.Parse(raceInfo_to_dateTimePicker.Value.ToString("yyyy/MM/dd"));

                foreach (var url in context.開催情報.Where(d => d.開催日 >= RaceDate_From && d.開催日 <= RaceDate_To).Select(d => d.当日メニューURL))
                {
                    if (token.IsCancellationRequested) return;
                    当日メニュー.FetchAndStoreData(driver, url);
                }
                for (DateOnly RaceDate = RaceDate_From; RaceDate <= RaceDate_To; RaceDate = RaceDate.AddDays(1))
                {
                    foreach (var url in context.当日メニュー
                                 .Where(d => d.開催日 == RaceDate)
                                 .OrderBy(d => d.開催場所).ThenBy(d => d.レース番号)
                                 .Select(d => new { d.出馬表URL, d.成績URL }))
                    {
                        if (token.IsCancellationRequested) return;
                        レース情報.FetchAndStoreData(driver, url.出馬表URL);
                        if (token.IsCancellationRequested) return;
                        競走結果.FetchAndStoreData(driver, url.成績URL);
                        if (token.IsCancellationRequested) return;
                        払戻金.FetchAndStoreData(driver, url.成績URL);
                    }

                    foreach (var race in context.レース情報
                                 .Where(d => d.開催日 == RaceDate)
                                 .OrderBy(d => d.開催場所).ThenBy(d => d.レース番号).ThenBy(d => d.馬名)
                                 .ToList())
                    {
                        if (token.IsCancellationRequested) return;
                        RaceHistoryCompleter.FetchAndStoreData(driver, race.馬情報URL, race.馬名);
                    }

                }

            }
            catch (Exception ex)
            {
                Logger.LogError("エラーが発生しました。", ex);
            }
            finally
            {
                //this.raceInfo_start_button.Enabled = true;
                //this.raceInfo_stop_button.Enabled = false;
                //this.raceInfo_from_dateTimePicker.Enabled = true;
                //this.raceInfo_to_dateTimePicker.Enabled = true;
                //this.raceInfo_from_dateTimePicker.Value= racedatefrom ;
                driver.Quit();
                Logger.Log("OUT");
            }
        }

        /// <summary>
        /// リアルタイムレース情報取得開始ボタンの押下処理です。
        /// </summary>
        /// <param name="sender">イベントを発生させた画面コントロール。</param>
        /// <param name="e">イベントに付随する引数。</param>
        private void realtimeraceinfo_start_button_Click(object sender, EventArgs e)
        {
            Logger.Log("IN");
            try
            {
                // ボタンを無効化して連打を防止
                this.realtimeraceinfo_start_button.Enabled = false;
                this.realtimeraceinfo_stop_button.Enabled = true; // 停止ボタンを有効化
                _raceInfoCts = new CancellationTokenSource();
                Task.Run(() => getRealtimeRaceInfo(_raceInfoCts.Token,false));
            }
            catch (Exception ex)
            {
                Logger.LogError("エラーが発生しました。", ex);
            }
            finally
            {
                Logger.Log("OUT");
            }
            Logger.Log("IN");
        }
        /// <summary>
        /// 当日のレース情報を監視し、発走後の競走結果と払戻金を順次取得します。
        /// </summary>
        /// <param name="token">処理停止要求を受け取るキャンセルトークン。</param>
        /// <param name="isHeadress">Chromeをヘッドレスモードで起動する場合はtrue。</param>
        private void getRealtimeRaceInfo( CancellationToken token, bool isHeadress)
        {
            Logger.Log("IN");

            string baseUrl = "https://www.keiba.go.jp/KeibaWeb/MonthlyConveneInfo/MonthlyConveneInfoTop";
            IWebDriver? driver = WebDriverHelper.InitializeDriverAndNavigate(baseUrl, isHeadress);
            if (driver == null)
            {
                return;
            }

            try
            {
                var configuration = new ConfigurationBuilder()
                    .SetBasePath(AppContext.BaseDirectory)
                    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
                    .Build();

                var options = new DbContextOptionsBuilder<DBContext>()
                    .UseSqlServer(configuration.GetConnectionString("DefaultConnection"))
                    .Options;

                if (token.IsCancellationRequested) return;

                using var context = new DBContext(options);

                // 開催日程取得
                開催日程.FetchAndStoreData(driver, DateTime.Today.Year, DateTime.Today.Month);
                if (token.IsCancellationRequested) return;

                driver.Navigate().GoToUrl(baseUrl);

                var 開催日 = DateOnly.FromDateTime(DateTime.Today);

                bool isRaceFinished = false;
                // 当日メニュー取得
                var _開催情報一覧 = context.開催情報
                    .Where(d => d.開催日 == 開催日)
                    .ToList();

                do
                {
                    // ブラウザがクラッシュしていると以降の全コマンドがタイムアウトし続け、
                    // 一晩中エラーで空転するため、各周回の冒頭で生存確認し、死んでいれば作り直します。
                    driver = WebDriverHelper.EnsureAlive(driver, isHeadress);
                    if (driver == null)
                    {
                        Logger.Log("WebDriverを再初期化できませんでした。30秒後に再試行します。");
                        if (token.WaitHandle.WaitOne(TimeSpan.FromSeconds(30))) return;
                        continue;
                    }

                    FetchDuePayouts(driver, context, 開催日, token);
                    if (token.IsCancellationRequested) return;
                    var TodaysMenuURLs = (
                        from menu in context.当日メニュー
                        where menu.開催日 == 開催日
                        where !context.払戻金.Any(p =>
                            p.開催日 == menu.開催日 &&
                            p.開催場所 == menu.開催場所 &&
                            p.レース番号 == menu.レース番号)
                        join info in context.開催情報
                            on new { menu.開催日, menu.開催場所 } equals new { info.開催日, info.開催場所 }
                        select info.当日メニューURL
                    ).Distinct().ToList();

                    /* 
                     * 払戻金が存在しない当日メニューを更新
                     */
                    if (TodaysMenuURLs.Count == 0)
                    {
                        Logger.Log($"全てのレースの競走結果は更新されています。開催日: {開催日}");
                        return;
                    }
                    foreach (var TodaysMenuURL in TodaysMenuURLs)
                    {
                        if (token.IsCancellationRequested) return;
                        当日メニュー.FetchAndStoreData(driver, TodaysMenuURL);
                    }

                    context.ChangeTracker.Clear();

                    // レース情報更新対象
                    // 払戻金が未取得の直近レースだけ抽出（開催場所ごと）
                    var nextRaceStartTimes = context.当日メニュー
                        .Where(d => d.開催日 == 開催日 && d.成績URL != null)
                        .Where(d => !context.払戻金.Any(p =>
                            p.開催日 == d.開催日 &&
                            p.開催場所 == d.開催場所 &&
                            p.レース番号 == d.レース番号))
                        .GroupBy(d => d.開催場所)
                        .Select(g => new
                        {
                            開催場所 = g.Key,
                            発走時刻 = g.Min(x => x.発走時刻)
                        });

                    var pendingRaceList = (
                        from menu in context.当日メニュー
                        join nextRace in nextRaceStartTimes
                          on new { menu.開催場所, menu.発走時刻 }
                          equals new { nextRace.開催場所, nextRace.発走時刻 }
                        where menu.開催日 == 開催日
                              && menu.成績URL != null
                              && !context.払戻金.Any(p =>
                                  p.開催日 == menu.開催日 &&
                                  p.開催場所 == menu.開催場所 &&
                                  p.レース番号 == menu.レース番号)
                        orderby menu.発走時刻
                        select menu
                    ).AsNoTracking().ToList();

                    pendingRaceList = pendingRaceList
                        .Where(race => !HasPayout(context, race))
                        .ToList();

                    var now = DateTime.Now;
                    var raceList = pendingRaceList
                        .Where(race => IsPayoutFetchDue(race, now))
                        .ToList();

                    if (raceList.Count == 0)
                    {
                        WaitForNextPayoutFetch(pendingRaceList, now, token);
                        continue;
                    }

                    foreach (var race in raceList)
                    {
                        if (token.IsCancellationRequested) return;

                        if (HasPayout(context, race))
                        {
                            Logger.Log($"払戻金取得済みのためスキップ: 開催日={race.開催日}, 開催場所={race.開催場所}, レース番号={race.レース番号}");
                            continue;
                        }

                        if (!IsPayoutFetchDue(race, DateTime.Now))
                        {
                            Logger.Log($"発走30分経過前のためスキップ: 開催日={race.開催日}, 開催場所={race.開催場所}, レース番号={race.レース番号}, 発走時刻={race.発走時刻:HH:mm}");
                            continue;
                        }

                        レース情報.FetchAndStoreData(driver, race.出馬表URL);

                        if (token.IsCancellationRequested) return;

                        競走結果.FetchAndStoreData(driver, race.成績URL);

                        if (token.IsCancellationRequested) return;

                        if (HasPayout(context, race))
                        {
                            Logger.Log($"払戻金取得済みのため払戻金取得をスキップ: 開催日={race.開催日}, 開催場所={race.開催場所}, レース番号={race.レース番号}");
                            continue;
                        }

                        払戻金.FetchAndStoreData(driver, race.成績URL);
                    }

                    // 最終レース時刻の取得
                    var lastRaceStartTime = context.当日メニュー
                        .Where(d => d.開催日 == 開催日)
                        .Max(d => d.発走時刻);

                    // 払戻金が最終レースにあるかどうかをチェック
                    isRaceFinished = context.当日メニュー
                        .Where(m => m.開催日 == 開催日 && m.発走時刻 == lastRaceStartTime)
                        .Join(
                            context.払戻金,
                            menu => new { menu.開催日, menu.開催場所, menu.レース番号 },
                            payout => new { payout.開催日, payout.開催場所, payout.レース番号 },
                            (menu, payout) => menu
                        )
                        .Any();

                } while (!isRaceFinished);
            }
            catch (Exception ex)
            {
                Logger.LogError("エラーが発生しました。", ex);
            }
            finally
            {
                // ボタン状態修正（開始を有効化、停止を無効化）
                this.Invoke(() =>
                {
                    realtimeraceinfo_start_button.Enabled = true;
                    realtimeraceinfo_stop_button.Enabled = false;
                });

                driver?.Quit();
                Logger.Log("OUT");
            }
        }

        /// <summary>
        /// 指定された当日メニューのレースについて、払戻金テーブルに保存済みデータがあるか確認します。
        /// </summary>
        /// <param name="context">払戻金テーブルを検索するDBContext。</param>
        /// <param name="race">払戻金の存在確認対象となる当日メニューモデル。</param>
        /// <returns>指定レースの払戻金が1件以上保存されている場合はtrue、未保存の場合はfalse。</returns>
        private static bool HasPayout(DBContext context, 当日メニューモデル race)
        {
            return context.払戻金.AsNoTracking().Any(p =>
                p.開催日 == race.開催日 &&
                p.開催場所 == race.開催場所 &&
                p.レース番号 == race.レース番号);
        }

        /// <summary>
        /// 発走から一定時間が経過し、払戻金が未保存のレースを取得します。
        /// </summary>
        /// <param name="driver">取得対象ページを操作するSelenium WebDriver。nullを許可するメソッドでは内部で生成します。</param>
        /// <param name="context">データベース操作に使用するDBContext。</param>
        /// <param name="開催日">保存または解析結果へ設定する開催日。</param>
        /// <param name="token">処理停止要求を受け取るキャンセルトークン。</param>
        private static void FetchDuePayouts(IWebDriver driver, DBContext context, DateOnly 開催日, CancellationToken token)
        {
            var payoutReadyTime = DateTime.Now.AddMinutes(-30);
            var payoutTargets = context.当日メニュー
                .AsNoTracking()
                .Where(race => race.開催日 == 開催日)
                .Where(race => race.成績URL != null && race.成績URL != string.Empty)
                .Where(race => race.発走時刻 <= payoutReadyTime)
                .Where(race => !context.払戻金.Any(p =>
                    p.開催日 == race.開催日 &&
                    p.開催場所 == race.開催場所 &&
                    p.レース番号 == race.レース番号))
                .OrderBy(race => race.発走時刻)
                .ThenBy(race => race.開催場所)
                .ThenBy(race => race.レース番号)
                .ToList();

            foreach (var race in payoutTargets)
            {
                if (token.IsCancellationRequested) return;
                if (HasPayout(context, race)) continue;

                Logger.Log($"発走30分経過後の未取得払戻金を取得します: 開催日={race.開催日}, 開催場所={race.開催場所}, レース番号={race.レース番号}");
                払戻金.FetchAndStoreData(driver, race.成績URL);
                context.ChangeTracker.Clear();
            }
        }

        /// <summary>
        /// 指定レースの発走時刻から30分以上経過しており、払戻金取得を試行すべきか判定します。
        /// </summary>
        /// <param name="race">発走時刻を確認する当日メニューモデル。</param>
        /// <param name="now">判定基準として使用する現在時刻。</param>
        /// <returns>発走時刻から30分以上経過していればtrue、まだ取得時刻に達していなければfalse。</returns>
        private static bool IsPayoutFetchDue(当日メニューモデル race, DateTime now)
        {
            return now >= race.発走時刻.AddMinutes(30);
        }

        /// <summary>
        /// 次に払戻金取得対象となるレース時刻まで待機します。
        /// </summary>
        /// <param name="pendingRaceList">払戻金取得待ちの当日メニュー一覧。</param>
        /// <param name="now">待機時間や取得可否を判定する基準時刻。</param>
        /// <param name="token">処理停止要求を受け取るキャンセルトークン。</param>
        private static void WaitForNextPayoutFetch(List<当日メニューモデル> pendingRaceList, DateTime now, CancellationToken token)
        {
            var nextFetchTime = pendingRaceList
                .Select(race => race.発走時刻.AddMinutes(30))
                .Where(fetchTime => fetchTime > now)
                .DefaultIfEmpty(now.AddMinutes(1))
                .Min();

            var waitTime = nextFetchTime - now;
            if (waitTime > TimeSpan.FromMinutes(1))
            {
                waitTime = TimeSpan.FromMinutes(1);
            }
            if (waitTime < TimeSpan.FromSeconds(5))
            {
                waitTime = TimeSpan.FromSeconds(5);
            }

            Logger.Log($"発走30分経過待ちのため待機します。次回確認まで約{waitTime.TotalSeconds:F0}秒");
            token.WaitHandle.WaitOne(waitTime);
        }

        /// <summary>
        /// リアルタイムレース情報取得停止ボタンの押下処理です。
        /// </summary>
        /// <param name="sender">イベントを発生させた画面コントロール。</param>
        /// <param name="e">イベントに付随する引数。</param>
        private void realtimeraceinfo_stop_button_Click(object sender, EventArgs e)
        {
            realtimeraceinfo_start_button.Enabled = true;
            realtimeraceinfo_stop_button.Enabled = false;
        }

        /// <summary>
        /// 競走結果と払戻金の欠落補完開始ボタンの押下処理です。
        /// </summary>
        /// <param name="sender">イベントを発生させた画面コントロール。</param>
        /// <param name="e">イベントに付随する引数。</param>
        private void reaceresult_start_button_Click(object sender, EventArgs e)
        {
            reaceresult_start_button.Enabled = false;
            raceresult_stop_button.Enabled = true;
            Logger.Log("IN");

            try
            {
                _raceResultCts = new CancellationTokenSource();
                Task.Run(() => BackfillMissingRaceResultsAndPayouts(_raceResultCts.Token));
            }
            catch (Exception ex)
            {
                Logger.LogError("エラーが発生しました。", ex);
                reaceresult_start_button.Enabled = true;
                raceresult_stop_button.Enabled = false;
            }
        }

        /// <summary>
        /// 競走結果と払戻金の欠落補完停止ボタンの押下処理です。
        /// </summary>
        /// <param name="sender">イベントを発生させた画面コントロール。</param>
        /// <param name="e">イベントに付随する引数。</param>
        private void raceresult_stop_button_Click(object sender, EventArgs e)
        {
            _raceResultCts?.Cancel();
            reaceresult_start_button.Enabled = true;
            raceresult_stop_button.Enabled = false;
            Logger.Log("競走結果穴埋めのキャンセルをリクエストしました。");
        }

        /// <summary>
        /// DB上で不足している競走結果と払戻金を成績URLから補完します。
        /// </summary>
        /// <param name="token">処理停止要求を受け取るキャンセルトークン。</param>
        private void BackfillMissingRaceResultsAndPayouts(CancellationToken token)
        {
            Logger.Log("IN");
            try
            {
                var configuration = new ConfigurationBuilder()
                    .SetBasePath(AppContext.BaseDirectory)
                    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
                    .Build();

                var options = new DbContextOptionsBuilder<DBContext>()
                    .UseSqlServer(configuration.GetConnectionString("DefaultConnection"))
                    .Options;

                using var context = new DBContext(options);
                var targets = context.当日メニュー
                    .AsNoTracking()
                    .Where(menu => menu.成績URL != null && menu.成績URL != string.Empty)
                    .Select(menu => new MissingRaceResultTarget
                    {
                        開催日 = menu.開催日,
                        開催場所 = menu.開催場所,
                        レース番号 = menu.レース番号,
                        成績URL = menu.成績URL,
                        HasRaceResult = context.競走結果.Any(result =>
                            result.開催日 == menu.開催日 &&
                            result.開催場所 == menu.開催場所 &&
                            result.レース番号 == menu.レース番号),
                        HasPayout = context.払戻金.Any(payout =>
                            payout.開催日 == menu.開催日 &&
                            payout.開催場所 == menu.開催場所 &&
                            payout.レース番号 == menu.レース番号)
                    })
                    .Where(target => !target.HasRaceResult || !target.HasPayout)
                    .OrderBy(target => target.開催日)
                    .ThenBy(target => target.開催場所)
                    .ThenBy(target => target.レース番号)
                    .ToList();

                Logger.Log($"競走結果・払戻金の欠落補完を開始します。対象レース数={targets.Count}");
                for (int i = 0; i < targets.Count; i++)
                {
                    if (token.IsCancellationRequested)
                    {
                        Logger.Log("競走結果穴埋めがキャンセルされました。");
                        return;
                    }

                    var target = targets[i];
                    Logger.Log($"欠落補完 {i + 1}/{targets.Count}: 開催日={target.開催日}, 開催場所={target.開催場所}, レース番号={target.レース番号}, 競走結果取得={(!target.HasRaceResult)}, 払戻金取得={(!target.HasPayout)}");

                    if (!target.HasRaceResult)
                    {
                        競走結果.FetchAndStoreData(null, target.成績URL);
                    }

                    if (token.IsCancellationRequested)
                    {
                        Logger.Log("競走結果穴埋めがキャンセルされました。");
                        return;
                    }

                    if (!target.HasPayout)
                    {
                        払戻金.FetchAndStoreData(null, target.成績URL);
                    }
                }

                Logger.Log("競走結果・払戻金の欠落補完が完了しました。");
            }
            catch (Exception ex)
            {
                Logger.LogError("競走結果・払戻金の欠落補完中にエラーが発生しました。", ex);
            }
            finally
            {
                this.Invoke(() =>
                {
                    reaceresult_start_button.Enabled = true;
                    raceresult_stop_button.Enabled = false;
                });
                Logger.Log("OUT");
            }
        }

        private sealed class MissingRaceResultTarget
        {
            public DateOnly 開催日 { get; set; }
            public string 開催場所 { get; set; } = string.Empty;
            public int レース番号 { get; set; }
            public string 成績URL { get; set; } = string.Empty;
            public bool HasRaceResult { get; set; }
            public bool HasPayout { get; set; }
        }

        /// <summary>
        /// 馬別競走履歴の補完開始ボタンの押下処理です。
        /// </summary>
        /// <param name="sender">イベントを発生させた画面コントロール。</param>
        /// <param name="e">イベントに付随する引数。</param>
        private void reaceresultByhorce_start_button_Click(object sender, EventArgs e)
        {
            reaceresultByhorce_start_button.Enabled = false;
            reaceresultByhorce_stop_button.Enabled = true;
            Logger.Log("IN");

            string baseUrl = "https://www.keiba.go.jp/KeibaWeb/TodayRaceInfo/TodayRaceInfoTop";
            IWebDriver? driver = WebDriverHelper.InitializeDriverAndNavigate(baseUrl);
            if (driver == null)
            {
                return;
            }

            //            DateOnly 開催日 = DateOnly.FromDateTime(DateTime.Today);
            try
            {
                var configuration = new ConfigurationBuilder()
                    .SetBasePath(AppContext.BaseDirectory)
                    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
                    .Build();

                var options = new DbContextOptionsBuilder<DBContext>()
                    .UseSqlServer(configuration.GetConnectionString("DefaultConnection"))
                    .Options;

                using var context = new DBContext(options);
                string 開催場所 = "川崎";
                string 馬名 = "トミサンペガサス";
                RaceHistoryCompleter.FetchAndStoreData(driver, 開催場所, 馬名);

                //DateOnly 開催日 = DateOnly.Parse("2025/07/08");
                // 当日メニュー取得
                //foreach (var race in context.レース情報
                //    .Where(d => d.開催日 == 開催日)
                //    .OrderBy(d => d.開催日).ThenBy(d => d.開催場所).ThenBy(d => d.レース番号).ThenBy(d => d.馬番)
                //    .ToList())
                //{
                //    RaceHistoryCompleter.FetchAndStoreData(driver, race.開催場所, race.馬名);
                //}


            }
            catch (Exception ex)
            {
                Logger.LogError("エラーが発生しました。", ex);
            }
            finally
            {
                // ボタン状態修正（開始を有効化、停止を無効化）
                this.Invoke(() =>
                {
                    reaceresultByhorce_start_button.Enabled = true;
                    reaceresultByhorce_stop_button.Enabled = false;
                });

                driver.Quit();
                Logger.Log("OUT");
            }
        }

        /// <summary>
        /// 対戦評価の日付変更時に、選択可能な競馬場一覧を更新します。
        /// </summary>
        /// <param name="sender">イベントを発生させた画面コントロール。</param>
        /// <param name="e">イベントに付随する引数。</param>
        private void RaceAnalyzer_RaceDate_ValueChanged(object sender, EventArgs e)
        {
            try
            {
                RaceAnalyzer_Racecourse_comboBox.Items.Clear();
                RaceAnalyzer_RaceNo_comboBox.Items.Clear();

                using var context = new DBContext();
                var racecourses =
                    context.当日メニュー
                        .Where(d => d.開催日 == DateOnly.FromDateTime(RaceAnalyzer_RaceDate.Value))
                        .Select(d => d.開催場所)
                        .Distinct()
                        .ToArray();

                RaceAnalyzer_Racecourse_comboBox.Items.AddRange(racecourses);
                RaceAnalyzer_start_button.Enabled = racecourses.Length > 0;

                if (racecourses.Length > 0)
                {
                    RaceAnalyzer_Racecourse_comboBox.SelectedIndex = 0;
                }
            }
            catch (Exception ex)
            {
                HandleRaceAnalyzerDatabaseError(ex);
            }
            this.Refresh();
        }

        /// <summary>
        /// 対戦評価の競馬場選択値が変わったときの補助イベント処理です。
        /// </summary>
        /// <param name="sender">イベントを発生させた画面コントロール。</param>
        /// <param name="e">イベントに付随する引数。</param>
        private void RaceAnalyzer_Racecourse_comboBox_ValueMemberChanged(object sender, EventArgs e)
        {
        }

        /// <summary>
        /// 対戦評価の競馬場変更時に、対象レース一覧を更新します。
        /// </summary>
        /// <param name="sender">イベントを発生させた画面コントロール。</param>
        /// <param name="e">イベントに付随する引数。</param>
        private void RaceAnalyzer_Racecourse_comboBox_SelectedValueChanged(object sender, EventArgs e)
        {
            if (RaceAnalyzer_Racecourse_comboBox.SelectedItem == null) return;

            try
            {
                RaceAnalyzer_RaceNo_comboBox.Items.Clear();
                using var context = new DBContext();
                var raceNumbers =
                        context.レース情報
                            .Where(d => d.開催日 == DateOnly.FromDateTime(RaceAnalyzer_RaceDate.Value) &&
                                        d.開催場所 == RaceAnalyzer_Racecourse_comboBox.SelectedItem!.ToString())
                            .Select(d => d.レース番号)         // 数値のまま
                            .Distinct()
                            .OrderBy(n => n)                   // 数値順にソート
                            .Select(n => n.ToString())        // 最後に文字列化
                            .ToArray();

                RaceAnalyzer_RaceNo_comboBox.Items.AddRange(raceNumbers);
                RaceAnalyzer_start_button.Enabled = raceNumbers.Length > 0;

                if (raceNumbers.Length > 0)
                {
                    RaceAnalyzer_RaceNo_comboBox.SelectedIndex = 0;
                }
            }
            catch (Exception ex)
            {
                HandleRaceAnalyzerDatabaseError(ex);
            }
            this.Refresh();

        }

        /// <summary>
        /// 選択されたレースを対象に対戦評価を実行します。
        /// </summary>
        /// <param name="sender">イベントを発生させた画面コントロール。</param>
        /// <param name="e">イベントに付随する引数。</param>
        private void RaceAnalyzer_start_button_Click(object sender, EventArgs e)
        {
            if (RaceAnalyzer_Racecourse_comboBox.SelectedItem == null ||
                RaceAnalyzer_RaceNo_comboBox.SelectedItem == null)
            {
                MessageBox.Show("レースアナライザの対象レースを選択してください。");
                return;
            }

            RaceAnalyzer_start_button.Enabled = false;
            RaceAnalyzer_stop_button.Enabled = true;
            RaceAnalyzer_RaceDate.Enabled = false;
            RaceAnalyzer_Racecourse_comboBox.Enabled = false;
            RaceAnalyzer_RaceNo_comboBox.Enabled = false;
            RaceResultComparer.CompareRaceResults(DateOnly.Parse(RaceAnalyzer_RaceDate.Value.ToString("yyyy/MM/dd")),
                                                        RaceAnalyzer_Racecourse_comboBox.SelectedItem!.ToString()!,
                                                        int.Parse(RaceAnalyzer_RaceNo_comboBox.SelectedItem!.ToString()!));
        }

        /// <summary>
        /// 対戦評価で発生したデータベース関連エラーをログへ記録し、画面の操作状態を更新します。
        /// </summary>
        /// <param name="ex">対戦評価処理中に発生したデータベース関連例外。</param>
        private void HandleRaceAnalyzerDatabaseError(Exception ex)
        {
            Logger.LogError("レースアナライザのDB接続でエラーが発生しました。", ex);
            RaceAnalyzer_start_button.Enabled = false;
            RaceAnalyzer_stop_button.Enabled = false;
            RaceAnalyzer_Racecourse_comboBox.Items.Clear();
            RaceAnalyzer_RaceNo_comboBox.Items.Clear();
            toolStripStatusLabel_notify.Text = "DBに接続できないため、レースアナライザを無効化しました。接続設定を確認してください。";
        }

        /// <summary>
        /// 固定条件で対戦評価テストを実行します。
        /// </summary>
        /// <param name="sender">イベントを発生させた画面コントロール。</param>
        /// <param name="e">イベントに付随する引数。</param>
        private void button1_Click(object sender, EventArgs e)
        {
            HeadToHeadResults r= RaceResultComparer.AvsB(
                                                                HorseA: "ビュヴォン",
                                                                HorseB: "アミン",
                                                                RaceDate:DateOnly.Parse("2025/07/21"),
                                                                RaceHistoryMonths:12,
                                                                RaceHistoryCount:3);
        }
    }
}
