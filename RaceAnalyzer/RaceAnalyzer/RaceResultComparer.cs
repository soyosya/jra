// 役割: 2頭の過去対戦や間接対戦をもとに、対戦評価を計算するロジックです。
// 直接対戦、共通相手、ページランク風の重み付けを使い、UIの対戦評価ボタンから呼び出されます。
using Accessibility;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore; // Entity Framework Core のデータベース操作をサポートする名前空間
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using Microsoft.Extensions.Configuration;
using System; // 基本的なシステム機能を提供する名前空間
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq; // LINQ 機能を提供する名前空間
using System.Text.RegularExpressions;
using System.Web; // URL クエリ パラメータの操作を提供する名前空間
using 中央競馬.Services;
using 中央競馬.共通.Data; // DB を使用する名前空間
using 中央競馬.共通.Libraly; // ログ機能を提供するカスタムクラスの名前空間
using 中央競馬.共通.Models; // データベースモデルを使用する名前空間
using System;
using System.Collections.Generic;
using System.Linq;

namespace 中央競馬.RaceAnalyzer
{
    public class RaceResultComparer
    {
        /// <summary>
        /// 直接対決結果を表すクラス
        /// </summary>
        public class directResult
        {
            public DateOnly RaceDate { get; set; }           // 開催日
            public string Racecourse { get; set; } = string.Empty; // 開催場所
            public int RaceNumber { get; set; }        // レース番号
            public string HorseA { get; set; } = string.Empty; // 出走馬A
            public string HorseB { get; set; } = string.Empty; // 出走馬B
            public decimal 着差 { get; set; }            // 着差
            public decimal HorseA_一着馬着差 { get; set; } // A馬の一着馬との着差
            public decimal HorseB_一着馬着差 { get; set; } // B馬の一着馬との着差
            /// <summary>
            /// directResult クラスの内容を文字列として返します。
            /// </summary>
            /// <returns>プロパティ情報を含む文字列表現</returns>
            public override string ToString()
            {
                try
                {
                    // トレースログ
                    Debug.WriteLine($"ToString() IN Date={RaceDate}, Racecourse={Racecourse}, RaceNumber={RaceNumber}, HorseA={HorseA}, HorseB={HorseB}, 着差: {着差}, {HorseA}の一着馬着差: {HorseA_一着馬着差}, {HorseB}の一着馬着差: {HorseB_一着馬着差}");

                    return
                        $"開催日: {RaceDate:yyyy-MM-dd}, 開催場所: {Racecourse}, レース番号: {RaceNumber}R\n" +
                        $"HorseA: {HorseA} HorseB: {HorseB}, 着差: {着差}, " +
                        $"{HorseA}の一着馬着差: {HorseA_一着馬着差}, {HorseB}の一着馬着差: {HorseB_一着馬着差}";
                }
                catch (Exception ex)
                {
                    // エラーログ
                    Debug.WriteLine($"ToString() ERROR: {ex.ToString()} - {ex.StackTrace}");
                    return base.ToString() ?? string.Empty;
                }
            }

        }
        /// <summary>
        /// 間接対戦情報を保持するクラス
        /// </summary>
        public class HeadToHeadResults
        {
            public string HorseA { get; set; } = string.Empty; // 出走馬A
            public string BridgeHorse { get; set; } = string.Empty; // 間接対戦馬（橋渡し）
            public string HorseB { get; set; } = string.Empty; // 出走馬B
            public List<directResult> DirectResults { get; set; } = new (); // 直接対決の結果リスト
            public (DateOnly Date, string Racecourse, int Number, List<string> Horses) FirstRace { get; set; } // AとCのレース
            public (DateOnly Date, string Racecourse, int Number, List<string> Horses) SecondRace { get; set; } // BとCのレース
            public Dictionary<(string horseA, string horseB), decimal> DirectVSPoints { get; set; } 
                                = new Dictionary<(string horseA, string horseB), decimal>();// 直接対決の結果
            public Dictionary<(string horseA, string bridgeHorse), decimal> HorseBridgePoints { get; set; } 
                                = new Dictionary<(string horseA, string bridgeHorse), decimal>();// 間接対決の結果
            /// <summary>
            /// HeadToHeadResults クラスの内容を文字列として返します。
            /// </summary>
            /// <returns>プロパティ情報を含む文字列表現</returns>
            public override string ToString()
            {
                try
                {
                    // トレースログ出力
                    Debug.WriteLine($"ToString() IN HorseA={HorseA}, BridgeHorse={BridgeHorse}, HorseB={HorseB}");

                    // 各レースの出走馬リストを文字列化
                    string firstRaceHorses = string.Join(",", FirstRace.Horses);
                    string secondRaceHorses = string.Join(",", SecondRace.Horses);

                    // 直接対決結果リストを整形
                    string directResultsStr = string.Join("\n", DirectResults.Select(r => r.ToString()));

                    // Dictionary を整形
                    string directPoints = string.Join(", ", DirectVSPoints.Select(kvp => $"({kvp.Key.horseA}-{kvp.Key.horseB}:{kvp.Value})"));
                    string bridgePoints = string.Join(", ", HorseBridgePoints.Select(kvp => $"({kvp.Key.horseA}-{kvp.Key.bridgeHorse}:{kvp.Value})"));

                    return
                        $"■対戦構成\n" +
                        $"HorseA: {HorseA}, BridgeHorse: {BridgeHorse}, HorseB: {HorseB}\n\n" +

                        $"■直接対決詳細\n{directResultsStr}\n\n" +

                        $"■FirstRace（{HorseA} vs {BridgeHorse}）\n" +
                        $"開催日: {FirstRace.Date:yyyy-MM-dd}, 開催場所: {FirstRace.Racecourse}, レース番号: {FirstRace.Number}R, 出走馬: [{firstRaceHorses}]\n\n" +

                        $"■SecondRace（{HorseB} vs {BridgeHorse}）\n" +
                        $"開催日: {SecondRace.Date:yyyy-MM-dd}, 開催場所: {SecondRace.Racecourse}, レース番号: {SecondRace.Number}R, 出走馬: [{secondRaceHorses}]\n\n" +

                        $"■DirectVSPoints（直接対決スコア）\n[{directPoints}]\n\n" +

                        $"■HorseBridgePoints（間接対決スコア）\n[{bridgePoints}]";
                }
                catch (Exception ex)
                {
                    // エラーログ
                    Debug.WriteLine($"ToString() ERROR: {ex.ToString()} - {ex.StackTrace}");
                    return base.ToString() ?? string.Empty;
                }
            }

        }

        /// <summary>
        /// 馬同志の力量を評価する。指定開催日から直近nレースとnヶ月以内の競走成績から直接対決の結果を評価する。
        /// </summary>
        /// <param name="HorseA">基準馬名</param>
        /// <param name="HorseB">対戦相手馬名</param>
        /// <param name="RaceDate">基準となる開催日。この日付より前の競走結果で力量を評価する</param>
        /// <param name="RaceHistoryMonths">競走成績を評価対象とする基準日を開催日のn月前で指定する。初期値12ヶ月</param>
        /// <param name="RaceHistoryCount">競走成績を評価するレース数を指定する。初期値3レース</param>
        /// <returns></returns>
        static public HeadToHeadResults AvsB(string HorseA, string HorseB, DateOnly RaceDate, int RaceHistoryMonths = 12, int RaceHistoryCount = 3)
        {
            Logger.Log($"IN HorseA:{HorseA},HorseB:{HorseB},RaceDate:{RaceDate},RaceHistoryMonths:{RaceHistoryMonths},RaceHistoryCount:{RaceHistoryCount}");
            var result = new HeadToHeadResults();
            try
            {
                using var context = new DBContext();

                // 直近 RaceHistoryMonths ヶ月分のレース対象期間を算出
                var fromDate = RaceDate.AddMonths(RaceHistoryMonths * -1);

                // HorseA の出走履歴を取得
                var horseAResults = context.競走結果
                    .Where(r => r.馬名 == HorseA
                             && r.開催日 < RaceDate
                             && r.開催日 >= fromDate)
                    .ToList();

                // HorseB の出走履歴を取得
                var horseBResults = context.競走結果
                    .Where(r => r.馬名 == HorseB
                             && r.開催日 < RaceDate
                             && r.開催日 >= fromDate)
                    .ToList();

                // 両者が同一レースに出走している履歴を比較付きで取得
                var HeadToHeadRaces = horseAResults
                    .Join(horseBResults,
                        a => new { a.開催日, a.開催場所, a.レース番号 },
                        b => new { b.開催日, b.開催場所, b.レース番号 },
                        (a, b) => new
                        {
                            a.開催日,
                            a.開催場所,
                            a.レース番号,
                            HorseA = a.馬名,
                            HorseB = b.馬名,
                            着差 = a.走破時計 - b.走破時計, // decimal
                            HorseA_一着馬着差 = a.一着馬着差タイム,
                            HorseB_一着馬着差 = b.一着馬着差タイム
                        })
                    .OrderByDescending(r => r.開催日)
                    .Take(RaceHistoryCount)
                    .ToList();

                // 対戦成績評価
                foreach (var race in HeadToHeadRaces)
                {
                    var directResult = new directResult
                    {
                        RaceDate = race.開催日,
                        Racecourse = race.開催場所,
                        RaceNumber = race.レース番号,
                        HorseA = race.HorseA,
                        HorseB = race.HorseB,
                        着差 = race.着差,
                        HorseA_一着馬着差 = race.HorseA_一着馬着差,
                        HorseB_一着馬着差 = race.HorseB_一着馬着差
                    };

                    result.DirectResults.Add(directResult);
                }
                return result;
            }
            catch (Exception ex)
            {
                // エラーログを記録
                Logger.LogError("過去の直接対決レースの取得中にエラーが発生しました。", ex);
                return new HeadToHeadResults();
            }
            finally
            {
                Logger.Log($"OUT {result}");
            }
        }
        public static bool CompareRaceResults(DateOnly 開催日, string 開催場所, int レース番号)
        {
            //int HistoryCount = 5;
            bool _result = false;
            List<directResult> directResults = new List<directResult>();
            HeadToHeadResults headToHeadResults = new HeadToHeadResults();
            Logger.Log($"IN 開催日:{開催日},開催場所:{開催場所},レース番号:{レース番号}");
            try
            {
                using (var context = new DBContext())
                {
                    //間接対戦の評価
                    Debug.WriteLine($"間接対戦の評価");
                    HeadToHeadResults indirectMatchRaces = GetIndirectMatchRaces(開催日, 開催場所, レース番号);
                    foreach (var bridgehorse in indirectMatchRaces.HorseBridgePoints
                                                        .Keys
                                                        .Select(r => r.bridgeHorse)
                                                        .Distinct()
                                                        .ToList())
                    {
                        var r = indirectMatchRaces.HorseBridgePoints
                                                        .Where(r => r.Key.bridgeHorse == bridgehorse)
                                                        .OrderBy(Keys => Keys.Value)
                                                        .ToList();
                    }



                    var Races = context.レース情報
                                        .Where(r => r.開催日 == 開催日 && r.開催場所 == 開催場所 && r.レース番号 == レース番号)
                                        .Select(r => new
                                        {
                                            r.馬番,
                                            r.馬名
                                        })
                                        .ToList();
                    Debug.WriteLine($"直接対戦の評価");
                    Dictionary<(string HorseA, string HorseB), double> Raitings = new Dictionary<(string HorseA, string HorseB), double>();
                    foreach (var HorseA in Races.OrderBy(r => r.馬番))
                    {
                        // 対戦相手を選定
                        foreach (var HorseB in Races.Where(r => r.馬名 != HorseA.馬名))
                        {
                            Raitings.Add((HorseA.馬名, HorseB.馬名), 999.0); // 初期化
                        }
                    }

                    List<string> HorsesB = new();
                    foreach (var HorseA in Races.OrderBy(r=>r.馬番))
                    {
                        // 対戦相手を選定
                        foreach (var HorseB in Races.Where(r => r.馬名 != HorseA.馬名 && !HorsesB.Contains(r.馬名)))
                        {
                            //直接対決
                            headToHeadResults=AvsB(HorseA.馬名,HorseB.馬名,開催日);
                            //直接対決が複数回あった際の評価
                            double WeightIndex = 0;
                            DateOnly CurrentRaceDate = DateOnly.MaxValue;
                            DateOnly PreviousRaceDate = DateOnly.MaxValue;
                            var key = (HorseA.馬名, HorseB.馬名);
                            double ratngvalue = 0.0;
                            foreach (var directResult in headToHeadResults.DirectResults)
                            {
                                if (CurrentRaceDate == DateOnly.MaxValue)
                                {
                                    WeightIndex=WeightIndexByRaceDateInterval(開催日, directResult.RaceDate);
                                    CurrentRaceDate= directResult.RaceDate;
                                }
                                else
                                {
                                    PreviousRaceDate = directResult.RaceDate;
                                    WeightIndex = WeightIndexByRaceDateInterval(CurrentRaceDate, PreviousRaceDate);
                                    CurrentRaceDate = PreviousRaceDate;
                                }
                                ratngvalue += (double)directResult.着差 * WeightIndex;
                            }
                            if (headToHeadResults.DirectResults.Count > 0)
                            {
                                Raitings[key] = ratngvalue / headToHeadResults.DirectResults.Count; // 平均値を計算
                            }
                        }
                    }
                    /*
                     * 順位付け
                     */
                    var scores = CalculatePageRank(Raitings);
                    Debug.WriteLine($"var scores = CalculatePageRank(Raitings);");
                    foreach (var kvp in scores.OrderByDescending(k => k.Value))
                    {
                        Debug.WriteLine($"{kvp.Key}: {kvp.Value:F4}");
                    }
                    // PageRankスコアを持つ辞書（既に計算済み）
                    Dictionary<string, double> pageRankScores = CalculatePageRank(Raitings);

                    // スコア昇順でソート
                    var sorted = pageRankScores.OrderBy(kv => kv.Value).ToList();

                    // 中央インデックス
                    int mid = sorted.Count / 2;

                    // 前後3頭のインデックス範囲を計算（境界処理付き）
                    int start = Math.Max(0, mid - 3);
                    int count = Math.Min(7, sorted.Count - start);

                    // 前後3頭（中央含む）の馬を抽出
                    var middle7 = sorted.GetRange(start, count);
                    Debug.WriteLine($"前後3頭（中央含む）var scores = CalculatePageRank(Raitings);");

                    // 表示
                    foreach (var (horse, score) in middle7)
                    {
                        Debug.WriteLine($"{horse}: {score:F4}");
                    }


                    var pagerankEdges = Raitings
                        .Where(kv => kv.Value != 999 && kv.Value != 0)
                        .GroupBy(kv => kv.Value < 0
                            ? (kv.Key.Item2, kv.Key.Item1) // 勝ち馬 → 負け馬
                            : (kv.Key.Item1, kv.Key.Item2))
                        .ToDictionary(
                            g => g.Key,
                            g => g.Max(kv => Math.Abs(kv.Value)) // 最も大きな着差を使用
                        );
                    Dictionary<string, double> pageRankScores2 = CalculatePageRank(pagerankEdges);
                    Debug.WriteLine($"pageRankScores2 = CalculatePageRank(pagerankEdges);");
                    foreach (var kvp in pageRankScores2.OrderByDescending(k => k.Value))
                    {
                        Debug.WriteLine($"{kvp.Key}: {kvp.Value:F4}");
                    }
                    // PageRankスコアを持つ辞書（既に計算済み）
                    pageRankScores2 = CalculatePageRank(pagerankEdges);

                    // スコア昇順でソート
                    sorted = pageRankScores2.OrderBy(kv => kv.Value).ToList();

                    // 中央インデックス
                    mid = sorted.Count / 2;

                    // 前後3頭のインデックス範囲を計算（境界処理付き）
                    start = Math.Max(0, mid - 3);
                    count = Math.Min(7, sorted.Count - start);

                    // 前後3頭（中央含む）の馬を抽出
                    middle7 = sorted.GetRange(start, count);

                    Debug.WriteLine($"前後3頭（中央含む）のscores = CalculatePageRank(pageRankScores2);");
                    // 表示
                    foreach (var (horse, score) in middle7)
                    {
                        Debug.WriteLine($"{horse}: {score:F4}");
                    }

                    var commonHorses = GetCommonCenterHorses(pageRankScores2, pageRankScores);
                    foreach (var name in commonHorses)
                    {
                        Debug.WriteLine($"共通中心馬: {name}");
                    }
                    List<string> GetCommonCenterHorses(
                            Dictionary<string, double> dictA,
                            Dictionary<string, double> dictB)
                    {
                        var sortedA = dictA.OrderBy(kv => kv.Value).ToList();
                        var sortedB = dictB.OrderBy(kv => kv.Value).ToList();

                        int midA = sortedA.Count / 2;
                        int midB = sortedB.Count / 2;

                        var centerA = sortedA.GetRange(Math.Max(0, midA - 3), Math.Min(7, sortedA.Count - Math.Max(0, midA - 3)));
                        var centerB = sortedB.GetRange(Math.Max(0, midB - 3), Math.Min(7, sortedB.Count - Math.Max(0, midB - 3)));

                        var namesA = centerA.Select(kv => kv.Key).ToHashSet();
                        var namesB = centerB.Select(kv => kv.Key).ToHashSet();

                        var common = namesA.Intersect(namesB).Take(3).ToList(); // 最大3頭

                        return common;
                    }

                    //間接対戦の評価
                    //Debug.WriteLine($"間接対戦の評価");
                    //HeadToHeadResults indirectMatchRaces = GetIndirectMatchRaces(開催日, 開催場所, レース番号);
                    //foreach (var bridgehorse in indirectMatchRaces.HorseBridgePoints
                    //                                    .Keys
                    //                                    .Select(r => r.bridgeHorse)
                    //                                    .Distinct()
                    //                                    .ToList())
                    //{
                    //    var r = indirectMatchRaces.HorseBridgePoints
                    //                                    .Where(r => r.Key.bridgeHorse == bridgehorse)
                    //                                    .OrderBy(Keys => Keys.Value)
                    //                                    .ToList();
                    //}


                    /*                        HeadToHeadResults directRaces = GetPastHeadToHeadRaces(開催日, 開催場所, レース番号);
                                            // 馬ごとのスコア一覧を記録（複数対戦する馬のためにリスト）
                                            var scoreMap = new Dictionary<string, List<decimal>>();

                                            foreach (var ((horseA, _), score) in directRaces.DirectVSPoints)
                                            {
                                                if (!scoreMap.ContainsKey(horseA))
                                                    scoreMap[horseA] = new List<decimal>();
                                                scoreMap[horseA].Add(score);
                                            }

                                            // 平均スコアで昇順ソート（小さいほど強い）
                                            var ranked = scoreMap
                                                .Select(pair => new
                                                {
                                                    Horse = pair.Key,
                                                    Average = pair.Value.Average(),
                                                    Count = pair.Value.Count
                                                })
                                                .OrderBy(x => x.Average)
                                                .ToList();

                                            // 出力
                                            Debug.WriteLine("🏇 強い順ランキング（平均スコアが小さいほど強い）");
                                            int rank = 1;
                                            foreach (var entry in ranked)
                                            {
                                                Debug.WriteLine($"{rank++}位: {entry.Horse}（平均: {entry.Average:F2}, 対戦数: {entry.Count}）");
                                            }


                                            // 馬ごとの評価スコアを集計
                                            var scoreDict = new Dictionary<string, List<decimal>>();

                                            foreach (var record in directRaces.DirectVSPoints)
                                            {
                                                var horseA = record.Key.ToTuple().Item1;
                                                var horseB = record.Key.ToTuple().Item2;
                                                var point = record.Value; // 着差や評価値。小さいほど強い

                                                if (!scoreDict.ContainsKey(horseA))
                                                    scoreDict[horseA] = new List<decimal>();

                                                scoreDict[horseA].Add(point);
                                            }

                                            // 馬ごとに平均スコアで強い順に並び替え（小さいほど強い）
                                            var ranked1 = scoreDict
                                                .Select(pair => new
                                                {
                                                    Horse = pair.Key,
                                                    Score = pair.Value.Average(), // 合計で評価
                                                    Count = pair.Value.Count
                                                })
                                                .OrderBy(x => x.Score) // 小さいほど強い
                                                .ToList();

                                            foreach (var entry in ranked1)
                                            {
                                                Debug.WriteLine($"{entry.Horse}：合計スコア = {entry.Score:F2}（対戦数: {entry.Count}）");
                                            }
                                            HeadToHeadResults indirectMatchRaces = GetIndirectMatchRaces(開催日, 開催場所, レース番号);
                                            //間接対戦の評価
                                            foreach(var bridgehorse in indirectMatchRaces.HorseBridgePoints
                                                                                .Keys
                                                                                .Select(r=>r.bridgeHorse)
                                                                                .Distinct()
                                                                                .ToList())
                                            {
                                                var r=indirectMatchRaces.HorseBridgePoints
                                                                                .Where(r => r.Key.bridgeHorse == bridgehorse)
                                                                                .OrderBy(Keys => Keys.Value)
                                                                                .ToList();
                                            }
                                            //Bridgeの評価
                                            // 各 horseA ごとに加重スコアを集計
                                            // 強さ順に重み付け：Br02 > Br01 > Br03
                                            var bridgeHorseWeight = new Dictionary<string, int>
                                            {
                                                { "Br02", 3 },
                                                { "Br01", 2 },
                                                { "Br03", 1 }
                                            };

                                            var horseScores = indirectMatchRaces.HorseBridgePoints
                                                .GroupBy(kvp => kvp.Key.horseA)
                                                .Select(group =>
                                                {
                                                    var horseA = group.Key;
                                                    decimal totalScore = 0;

                                                    foreach (var entry in group)
                                                    {
                                                        var bridgeHorse = entry.Key.bridgeHorse;
                                                        var diff = entry.Value;

                                                        if (bridgeHorseWeight.TryGetValue(bridgeHorse, out var weight))
                                                        {
                                                            totalScore += diff * weight;
                                                        }
                                                    }

                                                    return new { Horse = horseA, Score = totalScore };
                                                })
                                                .OrderBy(result => result.Score) // 着差が小さいほど強い
                                                .ToList();

                                        }
                    */
                }
                _result = true; // 処理が成功した場合は true を設定
                return _result;
            }
            catch (Exception ex)
            {
                Logger.LogError("処理中にエラーが発生しました。", ex);
                _result = false;
                return _result;
            }
            finally
            {
                Logger.Log($"OUT {_result}");
            }
        }
        /// <summary>
        /// PageRankスコアを計算する
        /// </summary>
        /// <param name="edges">勝敗関係の重み付きエッジ（勝者, 敗者, 着差）</param>
        /// <param name="damping">減衰係数（通常は 0.85）</param>
        /// <param name="maxIterations">最大反復回数</param>
        /// <param name="tolerance">収束判定の許容誤差</param>
        /// <returns>各馬のPageRankスコア</returns>
        public static Dictionary<string, double> CalculatePageRank(
            Dictionary<(string Winner, string Loser), double> edges,
            double damping = 0.85,
            int maxIterations = 100,
            double tolerance = 1e-6)
        {
            // ノード一覧の抽出
            var nodes = edges.Keys.Select(e => e.Winner)
                                  .Union(edges.Keys.Select(e => e.Loser))
                                  .Distinct()
                                  .ToList();

            int N = nodes.Count;
            var nodeIndex = nodes.Select((name, index) => (name, index))
                                 .ToDictionary(t => t.name, t => t.index);

            // 初期スコア
            double[] ranks = Enumerable.Repeat(1.0 / N, N).ToArray();
            double[] newRanks = new double[N];

            // 出リンクの重み合計
            var outWeights = new double[N];
            foreach (var ((from, to), weight) in edges)
            {
                outWeights[nodeIndex[from]] += weight;
            }

            for (int iteration = 0; iteration < maxIterations; iteration++)
            {
                Array.Fill(newRanks, (1.0 - damping) / N);

                foreach (var ((from, to), weight) in edges)
                {
                    int i = nodeIndex[from];
                    int j = nodeIndex[to];

                    if (outWeights[i] > 0)
                    {
                        newRanks[j] += damping * ranks[i] * (weight / outWeights[i]);
                    }
                }

                // 収束判定
                double diff = ranks.Zip(newRanks, (r, nr) => Math.Abs(r - nr)).Sum();
                if (diff < tolerance) break;

                Array.Copy(newRanks, ranks, N);
            }

            // 結果を辞書化
            return nodes.Select((name, i) => (name, score: ranks[i]))
                        .ToDictionary(t => t.name, t => t.score);
        }



        /// <summary>
        /// 指定された開催日・開催場所・レース番号の出走馬同士が、過去に同じレースに一緒に出走したレースを抽出します。
        /// </summary>
        /// <param name="RaceDate">対象レースの開催日</param>
        /// <param name="Racecourse">対象レースの開催場所</param>
        /// <param name="RaceNumber">対象レースのレース番号</param>
        /// <returns>出走馬が2頭以上同時に出走していた過去のレース情報（開催日、場所、レース番号、出走馬一覧）</returns>
        static public HeadToHeadResults GetPastHeadToHeadRaces(DateOnly RaceDate, string Racecourse, int RaceNumber)
        {
            var oneYearAgo = RaceDate.AddMonths(-12);
            var result = new HeadToHeadResults();

            try
            {
                using var context = new DBContext();

                // 対象レースの出走馬名一覧を取得
                var currentRaceHorseNames = context.レース情報
                    .Where(r => r.開催日 == RaceDate &&
                                r.開催場所 == Racecourse &&
                                r.レース番号 == RaceNumber)
                    .Select(r => r.馬名)
                    .Distinct()
                    .ToList();

                // 出走馬のうち2頭以上が一緒に出走していた過去1年以内のレースを抽出
                var headToHeadRaces = context.競走結果
                    .Where(r => r.開催日 < RaceDate && r.開催日 >= oneYearAgo && currentRaceHorseNames.Contains(r.馬名))
                    .GroupBy(r => new { r.開催日, r.開催場所, r.レース番号 })
                    .Where(g => g.Select(x => x.馬名).Distinct().Count() >= 2) // 2頭以上が共演
                    .Select(g => new
                    {
                        g.Key.開催日,
                        g.Key.開催場所,
                        g.Key.レース番号,
                        Horses = g.Select(x => new { x.馬名, x.走破時計 })
                        .Distinct()
                        .ToList()
                    })
                    .ToList();
                
                // 対戦成績評価
                foreach (var vs in headToHeadRaces)
                {
                    var key = (vs.Horses[0].馬名, vs.Horses[1].馬名);
                    if (result.DirectVSPoints.ContainsKey(key))
                    {
                        result.DirectVSPoints[key] += (vs.Horses[0].走破時計 - vs.Horses[1].走破時計);
                    }
                    else
                    {
                        result.DirectVSPoints.Add(key, vs.Horses[0].走破時計 - vs.Horses[1].走破時計);
                    }
                }
                return result;
            }
            catch (Exception ex)
            {
                // エラーログを記録
                Logger.LogError("過去の直接対決レースの取得中にエラーが発生しました。", ex);
                return new HeadToHeadResults();
            }
        }
        /// <summary>
        /// 開催日から過去n月以内に、出走馬同士が bridgeHorse を介して間接対戦していたレースを抽出します。
        /// bridgeHorse は horseA より上位の着順で、最も良い着順のレース1件のみを使用します。
        /// </summary>
        static public HeadToHeadResults GetIndirectMatchRaces(DateOnly RaceDate, string Racecourse, int RaceNumber)
        {
            try
            {
                using var context = new DBContext();
                var oneYearAgo = RaceDate.AddMonths(-12);
                // 対象レースの出走馬一覧を取得
                var TargetRaceStarters = context.レース情報
                    .Where(r => r.開催日 == RaceDate &&
                                r.開催場所 == Racecourse &&
                                r.レース番号 == RaceNumber)
                    .Select(r => r.馬名)
                    .Distinct()
                    .ToList();

                var result = new HeadToHeadResults();

                // Dictionary<軸馬, Dictionary<{開催日, 開催場所, レース番号}, List<bridgeHorses>>>
                var PivotHorseBridgeMap = new Dictionary<string, Dictionary<RaceKey, List<(string 馬名, decimal 走破時計, decimal 一着馬着差タイム)>>>();
                // 軸馬毎のブリッジ馬リストを保持するための辞書を作成
                foreach (var Starter in TargetRaceStarters)
                {
                    // 出走馬の過去レース一覧を取得
                    var StarterPastRaces = context.競走結果
                        .Where(r => r.馬名 == Starter &&
                                    r.開催日 < RaceDate &&
                                    r.開催日 >= oneYearAgo)
                        .Select(r => new { r.開催日, r.開催場所, r.レース番号,r.走破時計,r.一着馬着差タイム })
                        .Distinct()
                        .ToList();

                    // 出走馬と共に出走した bridgeHorseを抽出
                    var bridgeHorseCandidates = new HashSet<string>();

                    foreach (var race in StarterPastRaces.OrderByDescending(r => r.開催日))
                    {
                        var bridgeHorses = context.競走結果
                            .Where(r => r.開催日 == race.開催日 &&
                                        r.開催場所 == race.開催場所 &&
                                        r.レース番号 == race.レース番号 &&
                                        r.着順 > 0 &&
                                        r.馬名 != Starter &&
                                        !TargetRaceStarters.Contains(r.馬名))
                            .Select(r => new { r.馬名, r.走破時計, r.一着馬着差タイム })
                            .ToList();

                        var raceKey = new RaceKey
                        {
                            開催日 = race.開催日,
                            開催場所 = race.開催場所,
                            レース番号 = race.レース番号,
                            走破時計 = race.走破時計,
                            一着馬着差タイム = race.一着馬着差タイム
                        };
                        // bridgeHorses を 名前付きTuple にマッピング
                        var bridgeHorseList = bridgeHorses
                            .Select(bh => (
                                 bh.馬名,
                                 bh.走破時計,
                                bh.一着馬着差タイム
                            ))
                            .ToList();

                        // Dictionary に格納
                        if (!PivotHorseBridgeMap.ContainsKey(Starter))
                        {
                            PivotHorseBridgeMap[Starter] = new Dictionary<RaceKey, List<(string 馬名, decimal 走破タイム, decimal 着差タイム)>>();
                        }

                        if (!PivotHorseBridgeMap[Starter].ContainsKey(raceKey))
                        {
                            PivotHorseBridgeMap[Starter][raceKey] = bridgeHorseList;
                        }
                    }
                    //PivotHorseBridgeMapからP:Bの力量判断を行う

                    //ブリッジ馬と対戦している対戦馬を探す
                    //string currentHorsesCsv = string.Join(",", currentHorses.Select(h => $"'{h}'"));
                    //string bridgeHorsesCsv = string.Join(",", bridgeHorses.Select(h => $"'{h}'"));

                    //string sql = $@"
                    //                SELECT DISTINCT b.開催日, b.開催場所, b.レース番号, b.馬名
                    //                FROM レース情報 AS a
                    //                INNER JOIN レース情報 AS b
                    //                    ON a.開催日 = b.開催日
                    //                    AND a.開催場所 = b.開催場所
                    //                    AND a.レース番号 = b.レース番号
                    //                WHERE a.馬名 IN ({currentHorsesCsv})
                    //                    AND b.馬名 IN ({bridgeHorsesCsv})
                    //                    AND a.開催日 < @開催日";

                    //var sqlresult = context.レース情報.FromSqlRaw(sql, new SqlParameter("@開催日", race.開催日)).ToList();


                    //foreach (var name in bridgeHorses.Values)
                    //{
                    //    bridgeHorseCandidates.Add(name);
                    //}

                    // bridgeHorse 候補ごとに処理
                    foreach (var bridgeHorse in bridgeHorseCandidates)
                    {
                        var AhorceAVSbridge = context.競走結果
                            .Where(r => (r.馬名 == Starter || r.馬名 == bridgeHorse) &&
                                        r.開催日 < RaceDate && r.開催日 >= oneYearAgo)
                            .GroupBy(r => new { r.開催日, r.開催場所, r.レース番号 })
                            .Where(g => g.Select(x => x.馬名).Distinct().Count() == 2)
                            .Select(g => new
                            {
                                g.Key.開催日,
                                g.Key.開催場所,
                                g.Key.レース番号,
                                Horses = g.Select(x => new { x.馬名, x.走破時計 })
                                          .OrderBy(x => x.馬名 == Starter ? 0 : 1) // horseA を先頭に
                                          .ToList()
                            })
                            .OrderByDescending(r => r.開催日)
                            .Take(3)
                            .ToList();
                        // horseAとbridgeHorseの対戦成績評価
                        foreach (var vs in AhorceAVSbridge)
                        {
                            var key = (vs.Horses[0].馬名, vs.Horses[1].馬名);
                            if (result.HorseBridgePoints.ContainsKey(key))
                            {
                                result.HorseBridgePoints[key] += (vs.Horses[0].走破時計 - vs.Horses[1].走破時計);
                            }
                            else
                            {
                                result.HorseBridgePoints.Add(key, vs.Horses[0].走破時計 - vs.Horses[1].走破時計);
                            }
                        }
                    }
                }
                return result;
            }
            catch (Exception ex)
            {
                Logger.LogError("間接対戦レース取得中にエラーが発生しました。", ex);
                return new HeadToHeadResults();
            }
        }
        /// <summary>
        /// レース間隔に応じた重み付け指数を計算する
        /// </summary>
        /// <param name="CurrentRaceDate">今走の開催日</param>
        /// <param name="PreviousRaceDate">前走の開催日</param>
        /// <returns>重み指数</returns>
        static public double WeightIndexByRaceDateInterval(DateOnly CurrentRaceDate, DateOnly PreviousRaceDate)
        {
            double ret=0.0;
            int yearDiff = CurrentRaceDate.Year - PreviousRaceDate.Year;
            int monthDiff = CurrentRaceDate.Month - PreviousRaceDate.Month;

            int MonthDifference=yearDiff * 12 + monthDiff;
            if (MonthDifference <= 2)
            {
                ret = 1;
            }
            else if (MonthDifference <= 4)
            {
                ret = 0.9;
            }
            else if (MonthDifference <= 6)
            {
                ret = 0.8;
            }
            else if (MonthDifference <= 9)
            {
                ret = 0.7;
            }
            else
            {
                ret = 0.6;
            }
            return ret;
        }
    }
    public class RaceKey : IEquatable<RaceKey>
    {
        public DateOnly 開催日 { get; set; }
        public string 開催場所 { get; set; } = string.Empty;
        public int レース番号 { get; set; }
        public decimal 走破時計 { get; set; }
        public decimal 一着馬着差タイム { get; set; }

        public override bool Equals(object? obj) => Equals(obj as RaceKey);

        public bool Equals(RaceKey? other)
        {
            return other != null &&
                   開催日.Equals(other.開催日) &&
                   開催場所 == other.開催場所 &&
                   レース番号 == other.レース番号 &&
                   走破時計 == other.走破時計 &&
                   一着馬着差タイム == other.一着馬着差タイム;
        }

        public override int GetHashCode()
        {
            return HashCode.Combine(開催日, 開催場所, レース番号, 走破時計, 一着馬着差タイム);
        }
    }

}