// 役割: リアルタイムオッズ表示用のOxyPlot部品を生成するサービスです。
// フォームからグラフ構築ロジックを分離し、軸や系列の作成方法をここに集約します。
using System;
using System.Collections.Generic;
using System.Linq;
using LiveChartsCore;
using LiveChartsCore.SkiaSharpView;
using 中央競馬.共通.Models;

namespace RealTimeOddsChart
{
    public static class ChartService
    {
        public static ISeries[] CreateOddsSeries(List<リアルタイムオッズモデル> oddsList, out List<string> xLabels)
        {
            var labels = oddsList
                .Select(o => o.日時)
                .Distinct()
                .OrderBy(d => d)
                .ToList();

            xLabels = labels.Select(d => d.ToString("HH:mm")).ToList();

            var seriesDict = oddsList
                .GroupBy(o => $"{o.馬番:D2}{o.馬名}")
                .ToDictionary(g => g.Key, g => g.OrderBy(x => x.日時).ToList());

            var labelMap = seriesDict.ToDictionary(kvp => kvp.Key, kvp => kvp.Value.ToDictionary(v => v.日時, v => v.単勝オッズ));

            var seriesList = new List<ISeries>();

            foreach (var kvp in seriesDict)
            {
                var label = kvp.Key;
                var values = kvp.Value;
                var odds = labels.Select(time =>
                    labelMap[label].TryGetValue(time, out var o) ? o : double.NaN
                ).ToList();

                var lineSeries = new LineSeries<double>
                {
                    Name = label,
                    Values = odds,
                    Fill = null
                };

                seriesList.Add(lineSeries);
            }

            return seriesList.ToArray();
        }

        public static Axis[] CreateXAxis(List<string> xLabels)
        {
            return new Axis[]
            {
                new Axis
                {
                    Name = "時刻",
                    Labels = xLabels
                }
            };
        }

        public static Axis[] CreateYAxis()
        {
            return new Axis[]
            {
                new Axis
                {
                    Name = "単勝オッズ",
                    MinLimit = 0
                }
            };
        }
    }

}

