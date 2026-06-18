// 役割: 1レース分の投票内容(軸1頭・相手N頭の3連単マルチ)を表すモデルと、
//       買い目CSVの読み込み、3連単マルチの点数生成を担います。
using System.Globalization;
using CommonLogger = 中央競馬.共通.Libraly.Logger;

namespace 中央競馬.RakutenVote
{
    /// <summary>1レース分の買い目(危険ローテ除外つき軸 + 相手N頭)。</summary>
    public sealed class BetTicket
    {
        public string Date { get; init; } = "";       // yyyy-MM-dd
        public string Venue { get; init; } = "";       // 開催場 例:高知
        public int Race { get; init; }                 // レース番号
        public int AxisUma { get; init; }              // 軸の馬番
        public string AxisName { get; init; } = "";
        public List<int> Partners { get; init; } = new(); // 相手の馬番(rating上位)

        /// <summary>3連単マルチ(軸1頭・相手N頭)の順序付き組合せ。軸は1〜3着いずれか、残り2着を相手から。</summary>
        public List<(int a, int b, int c)> ExpandMultiTrifecta()
        {
            var combos = new List<(int, int, int)>();
            var p = Partners;
            for (int i = 0; i < p.Count; i++)
            {
                for (int j = 0; j < p.Count; j++)
                {
                    if (i == j) continue;
                    // 軸が1着 / 2着 / 3着 の3通り、残り2枠を相手の順列(i,j)で埋める
                    combos.Add((AxisUma, p[i], p[j])); // 軸=1着
                    combos.Add((p[i], AxisUma, p[j])); // 軸=2着
                    combos.Add((p[i], p[j], AxisUma)); // 軸=3着
                }
            }
            return combos;
        }

        /// <summary>三連単マルチ(軸1頭・相手N)の点数 = 3 * N * (N-1)。</summary>
        public int PointCount => 3 * Partners.Count * (Partners.Count - 1);

        /// <summary>三連複 軸1頭流し(相手N)の点数 = C(N,2) = N*(N-1)/2。</summary>
        public int PointCountFuku => Partners.Count >= 2 ? Partners.Count * (Partners.Count - 1) / 2 : 0;

        public override string ToString() =>
            $"{Date} {Venue}{Race}R 軸{AxisUma}({AxisName}) 相手[{string.Join(",", Partners)}] {PointCount}点";
    }

    /// <summary>買い目CSV(today-picks.ps1 -ExportBets が出力)を読み込みます。</summary>
    public static class BetsLoader
    {
        // ヘッダ: date,venue,race,axis_uma,axis_name,p1,p2,p3,p4,...
        public static List<BetTicket> Load(string csvPath, int partnerCount)
        {
            var list = new List<BetTicket>();
            if (!File.Exists(csvPath))
            {
                CommonLogger.Log($"買い目CSVが見つかりません: {csvPath}", 1);
                return list;
            }

            var lines = File.ReadAllLines(csvPath);
            if (lines.Length <= 1) return list;

            // CSVフィールドのクォート/空白/BOMを除去するヘルパ
            static string Clean(string s) => s.Trim().Trim('"').Trim().TrimStart('﻿');

            var header = lines[0].Split(',').Select(Clean).ToList();
            int Idx(string name) => header.FindIndex(h => string.Equals(h, name, StringComparison.OrdinalIgnoreCase));
            int iDate = Idx("date"), iVenue = Idx("venue"), iRace = Idx("race"), iAxis = Idx("axis_uma"), iName = Idx("axis_name");

            for (int r = 1; r < lines.Length; r++)
            {
                var cols = lines[r].Split(',').Select(Clean).ToArray();
                if (cols.Length < header.Count) continue;
                try
                {
                    var partners = new List<int>();
                    for (int k = 1; k <= partnerCount; k++)
                    {
                        int pIdx = Idx($"p{k}");
                        if (pIdx >= 0 && pIdx < cols.Length && int.TryParse(cols[pIdx], out var pu) && pu > 0)
                            partners.Add(pu);
                    }
                    var t = new BetTicket
                    {
                        Date = cols[iDate],
                        Venue = cols[iVenue],
                        Race = int.Parse(cols[iRace], CultureInfo.InvariantCulture),
                        AxisUma = int.Parse(cols[iAxis], CultureInfo.InvariantCulture),
                        AxisName = iName >= 0 ? cols[iName] : "",
                        Partners = partners
                    };
                    if (t.AxisUma > 0 && t.Partners.Count >= 2) list.Add(t);
                }
                catch (Exception ex)
                {
                    CommonLogger.LogError($"買い目CSVの行解析に失敗(行{r + 1})", ex);
                }
            }
            return list;
        }
    }
}
