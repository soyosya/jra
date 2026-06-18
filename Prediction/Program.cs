// 役割: 保存済みデータを使った予測・評価処理の入口です。
// レース情報、競走結果、払戻金を読み込み、検証対象レースの抽出や評価処理を行います。
// 本番取得ではなく、取得済みDBを分析する用途のプロジェクトです。
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using OpenQA.Selenium;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using 中央競馬.共通.Data; // DB を使用する名前空間
using 中央競馬.共通.Libraly; // ログ機能を提供するカスタムクラスの名前空間
using 中央競馬.共通.Models; // データベースモデルを使用する名前空間

namespace 中央競馬.Prediction
{
    internal class Program
    {
        /// <summary>
        /// アプリケーションのエントリーポイント。
        /// </summary>
        /// <param name="args">コマンドライン引数</param>
        static void Main(string[] args)
        {
            Logger.Log($"args.{args} Environment.CommandLine.{Environment.CommandLine}");
            if (Environment.CommandLine.Contains("ef.dll"))
            {
                Debug.WriteLine("EF Core design-time execution detected.");
                return; // 通常のアプリケーション実行をスキップ
            }
            else
            {
                Debug.WriteLine($"Environment.CommandLine.{Environment.CommandLine}");
            }
            //string baseUrl = "https://www.keiba.go.jp/KeibaWeb/MonthlyConveneInfo/MonthlyConveneInfoTop";
            //IWebDriver driver = WebDriverHelper.InitializeDriverAndNavigate(baseUrl);
            try
            {
                // Configurationを使用して接続文字列を取得
                var configuration = new ConfigurationBuilder()
                    .SetBasePath(AppContext.BaseDirectory)
                    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
                    .Build();
                // DbContextOptionsを構築
                var options = new DbContextOptionsBuilder<DBContext>()
                    .UseSqlServer(configuration.GetConnectionString("DefaultConnection"))
                    .Options;

                DateOnly 開催日 = new DateOnly(DateTime.Today.Year,DateTime.Today.Month,DateTime.Today.Day);
                string 開催場所 = "園田";
                int レース番号 = 1;
                // DBContextをインスタンス化
                using var context = new DBContext(options);

                // 投票レースを抽出する
                var 当日メニュー一覧 = context.当日メニュー
                    .Join(context.レース情報,
                        todaysrace => new { todaysrace.開催日, todaysrace.開催場所, todaysrace.レース番号 },
                        raceinfo => new { raceinfo.開催日, raceinfo.開催場所, raceinfo.レース番号 },
                        (todaysrace, raceinfo) => new
                        {
                            todaysrace.開催日,
                            todaysrace.開催場所,
                            todaysrace.レース番号,
                            todaysrace.距離,
                            raceinfo.一着賞金 // 必要なプロパティを指定
                        })
                    .Where(d => d.開催日 <= 開催日 &&
                                d.開催日 >= new DateOnly(2024, 12, 01) &&
                                d.開催場所 == 開催場所 &&
                                d.距離 == 1400 &&
                                (d.一着賞金 == 500000 || d.一着賞金 == 700000))
                     .AsEnumerable() // ここでクライアント評価に切り替える
                    .GroupBy(d => new { d.開催日, d.開催場所, d.レース番号 }) // 複数項目でグループ化
                    .OrderByDescending(d => d.Key.開催日).ThenBy(d => d.Key.レース番号)
                    .ToList();

                List<(DateOnly, string, int)> TargetRaces = [];
                foreach (var 当日メニュー in 当日メニュー一覧)
                {
                    Logger.Log($"IN 開催日:{当日メニュー.Key.開催日} 開催場所:{当日メニュー.Key.開催場所} レース番号:{当日メニュー.Key.レース番号}");

                    // 出走馬を一括取得
                    var 出走馬一覧 = context.レース情報
                        .Where(d => d.開催日 == 当日メニュー.Key.開催日 &&
                                    d.開催場所 == 当日メニュー.Key.開催場所 &&
                                    d.レース番号 == 当日メニュー.Key.レース番号)
                        .ToList();

                    // 対象レースかどうか判定
                    // 対象レースかどうか判定
                    bool isTargetRace = true; // 初期値は true
                    int falseCount = 0; // return false のカウント
                    foreach (var 出走馬 in 出走馬一覧)
                    {
                        // 競走結果から条件を確認
                        var 前走回数 = context.競走結果
                            .Count(d => d.開催日 < 出走馬.開催日 &&
                                        d.馬名 == 出走馬.馬名 &&
                                        d.開催場所 == 出走馬.開催場所);

                        if (前走回数 < 3)
                        {
                            falseCount++;

                            if (falseCount >= 4)
                            {
                                isTargetRace = false;
//                                Logger.Log($"判定中断: return false が {falseCount} 回に達しました。");
//                                Logger.Log($"対象外: 馬名:{出走馬.馬名} 開催日:{出走馬.開催日} レース番号:{出走馬.レース番号}");
                                break; // 処理を途中で終了
                            }
                        }
                        else
                        {
//                            Logger.Log($"対象: 馬名:{出走馬.馬名} 開催日:{出走馬.開催日} レース番号:{出走馬.レース番号}");
                        }
                    }

                    //bool isTargetRace = 出走馬一覧.All(出走馬 =>
                    //{
                    //    // 競走結果から条件を確認
                    //    var 前走回数 = context.競走結果
                    //        .Count(d => d.開催日 < 出走馬.開催日 &&
                    //                    d.馬名 == 出走馬.馬名 &&
                    //                    d.開催場所 == 出走馬.開催場所);

                    //    if (前走回数 < 4)
                    //    {
                    //        Logger.Log($"対象外: 馬名:{出走馬.馬名} 開催日:{出走馬.開催日}");
                    //        return false;
                    //    }

                    //    Logger.Log($"対象: 馬名:{出走馬.馬名} 開催日:{出走馬.開催日}");
                    //    return true;
                    //});

                    if (!isTargetRace)
                    {
//                        Logger.Log($"OUT 対象外レース 開催日:{当日メニュー.Key.開催日} 開催場所:{当日メニュー.Key.開催場所} レース番号:{当日メニュー.Key.レース番号}");
                    }
                    else
                    {
                        TargetRaces.Add((当日メニュー.Key.開催日,当日メニュー.Key.開催場所,当日メニュー.Key.レース番号));
//                        Logger.Log($"OUT 対象レース 開催日:{当日メニュー.Key.開催日} 開催場所:{当日メニュー.Key.開催場所} レース番号:{当日メニュー.Key.レース番号}");
                    }

                }

                foreach (var 出走馬 in context.レース情報.Where(d => d.開催日 == 開催日 && d.開催場所 == 開催場所 && d.レース番号 == レース番号).OrderBy(d => d.馬番))
                {
                    Logger.Log($"IN 開催日:{開催日} 開催場所:{開催場所} レース番号:{レース番号}");
                    VidualEvaliation(options, 出走馬.開催日, 出走馬.開催場所, 出走馬.レース番号, 出走馬.馬名);
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("エラーが発生しました。", ex);
            }
            finally
            {
            }
        }


        /// <summary>
        /// 個体評価を行う
        /// </summary>
        private static void VidualEvaliation(DbContextOptions<DBContext> options, DateOnly 開催日, string 開催場所, int レース番号, string 馬名)
        {
            Logger.Log($"IN 開催日:{開催日} 開催場所:{開催場所} レース番号:{レース番号} 馬名:{馬名}");
            try
            {
                using (var newContext = new DBContext(options))
                {
                    var RaceHistory = newContext.競走結果
                        .AsNoTracking()
                        .Where(d => d.開催日 < 開催日 && d.馬名 == 馬名)
                        .OrderByDescending(d => d.開催日)
                        .Take(4)
                        .ToList();

                    foreach (var Result in RaceHistory)
                    {
                        Logger.Log($"開催日: {Result.開催日}, 馬名: {Result.馬名}");
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("エラーが発生しました。", ex);
            }
        }
    }
}
