using Microsoft.EntityFrameworkCore;
using OpenQA.Selenium;
using System;
using 中央競馬.Services; // 開催日程取得クラスを使用する名前空間
using 中央競馬.共通.Libraly; // ログ機能を提供するカスタムクラスの名前空間
using 中央競馬.共通.Data; // DB を使用する名前空間
using 中央競馬.共通.Models; // データベースモデルを使用する名前空間
using Microsoft.Extensions.Configuration;
using System.Diagnostics;

namespace 中央競馬.レース情報取得バッチ
{
    /// <summary>
    /// 現在はConsoleApp側へ統合済みの旧バッチ入口です。
    /// レース情報取得プロジェクトはライブラリとして使われるため、現行の実行入口ではありません。
    /// </summary>
    internal class ___Program
    {
        /// <summary>
        /// アプリケーションのエントリーポイント。
        /// 開催日程取得バッチ処理を開始します。
        /// </summary>
        /// <param name="args">コマンドライン引数</param>
        static void ___Main(string[] args)
        {
            Logger.Log($"args.{args} Environment.CommandLine.{Environment.CommandLine}");
            if (Environment.CommandLine.Contains("ef.dll"))
            {
                Debug.WriteLine("EF Core design-time execution detected.");
                return ; // 通常のアプリケーション実行をスキップ
            }
            else
            {
                Debug.WriteLine($"Environment.CommandLine.{Environment.CommandLine}");

            }
            string baseUrl = "https://www.keiba.go.jp/KeibaWeb/MonthlyConveneInfo/MonthlyConveneInfoTop";
            IWebDriver? driver = WebDriverHelper.InitializeDriverAndNavigate(baseUrl);
            if (driver == null)
            {
                return;
            }

            try
            {
                //リアルタイムオッズ.取得(args); // リアルタイムオッズの取得を実行

                // Configurationを使用して接続文字列を取得
                var configuration = new ConfigurationBuilder()
                    .SetBasePath(AppContext.BaseDirectory)
                    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
                    .Build();
                // DbContextOptionsを構築
                var options = new DbContextOptionsBuilder<DBContext>()
                    .UseSqlServer(configuration.GetConnectionString("DefaultConnection"))
                    .Options;

                // DBContextをインスタンス化
                using var context = new DBContext(options);                //                // 開催日程クラスの Main メソッドを呼び出す
                開催日程.FetchAndStoreData(driver, DateTime.Today.Year,DateTime.Today.Month);
                driver.Navigate().GoToUrl(baseUrl);
                ////                レース情報クラスの Main メソッドを呼び出す
                ///
//                var 開催日 = context.当日メニュー.Max(d => d.開催日);
                var 開催日 = DateOnly.Parse(DateTime.Today.AddDays(-1).ToString("yyyy/MM/dd"));
                foreach (var url in context.開催情報.Where(d => d.開催日>=開催日).Select(d => d.当日メニューURL))
                {
                    当日メニュー.FetchAndStoreData(driver, url);
                }
                foreach (var url in context.当日メニュー.Where(d => d.開催日 >= 開催日).OrderBy(d => d.開催日).ThenBy(d => d.開催場所).ThenBy(d => d.レース番号).Select(d => d.出馬表URL))
                {
                    レース情報.FetchAndStoreData(driver, url);
                }
                ////                当日メニュークラスの Main メソッドを呼び出す
                ////                競走結果クラスの Main メソッドを呼び出す
                ////                foreach (var url in context.当日メニュー.OrderBy(d => d.開催日).ThenBy(d => d.開催場所).ThenBy(d => d.レース番号).Select(d => d.成績URL))
                foreach (var url in context.当日メニュー.Where(d => d.開催日 >= 開催日).Select(d => d.成績URL))
                {
                    競走結果.FetchAndStoreData(driver, url);
                    払戻金.FetchAndStoreData(driver, url);
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("エラーが発生しました。", ex);
            }
            finally
            {
                driver.Quit();
            }
        }
    }
}
