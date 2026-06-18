// 役割: keiba.go.jp の競馬場コードとDBで使う開催場所名を相互変換するマスタです。
// URLクエリのk_babaCodeを開催場所名へ変換し、URL生成時には開催場所名からコードを取得します。
using System; // 基本的なシステム機能を提供する名前空間
using System.Collections.Generic; // ジェネリックコレクションをサポートする名前空間
using System.ComponentModel.DataAnnotations;
using Microsoft.Extensions.Configuration; // appsettings.json の読み取りをサポートする名前空間

namespace 中央競馬.共通.Models
{
    /// <summary>
    /// 場名マスタを表すクラス。
    /// </summary>
    public class 場名マスタ
    {
        /// <summary>
        /// 場名
        /// </summary>
        [MaxLength(4)]

        public string 場名 { get; set; } = string.Empty;

        /// <summary>
        /// 場名コード
        /// </summary>
        [MaxLength(2)]

        public string 場名コード { get; set; } = string.Empty;

        /// <summary>
        /// 場名マスタデータリスト
        /// </summary>
        public static readonly List<場名マスタ> MasterData = new List<場名マスタ>
        {
            new 場名マスタ { 場名 = "北見ば", 場名コード = "1" },
            new 場名マスタ { 場名 = "岩見ば", 場名コード = "2" },
            new 場名マスタ { 場名 = "帯広ば", 場名コード = "3" },
            new 場名マスタ { 場名 = "旭川ば", 場名コード = "4" },
            new 場名マスタ { 場名 = "旭川", 場名コード = "7" },
            new 場名マスタ { 場名 = "門別", 場名コード = "36" },
            new 場名マスタ { 場名 = "札幌", 場名コード = "8" },
            new 場名マスタ { 場名 = "盛岡", 場名コード = "10" },
            new 場名マスタ { 場名 = "水沢", 場名コード = "11" },
            new 場名マスタ { 場名 = "上山", 場名コード = "12" },
            new 場名マスタ { 場名 = "新潟", 場名コード = "13" },
            new 場名マスタ { 場名 = "三条", 場名コード = "14" },
            new 場名マスタ { 場名 = "足利", 場名コード = "15" },
            new 場名マスタ { 場名 = "宇都宮", 場名コード = "16" },
            new 場名マスタ { 場名 = "高崎", 場名コード = "17" },
            new 場名マスタ { 場名 = "浦和", 場名コード = "18" },
            new 場名マスタ { 場名 = "船橋", 場名コード = "19" },
            new 場名マスタ { 場名 = "大井", 場名コード = "20" },
            new 場名マスタ { 場名 = "川崎", 場名コード = "21" },
            new 場名マスタ { 場名 = "金沢", 場名コード = "22" },
            new 場名マスタ { 場名 = "笠松", 場名コード = "23" },
            new 場名マスタ { 場名 = "名古屋", 場名コード = "24" },
            new 場名マスタ { 場名 = "中京", 場名コード = "25" },
            new 場名マスタ { 場名 = "園田", 場名コード = "27" },
            new 場名マスタ { 場名 = "姫路", 場名コード = "28" },
            new 場名マスタ { 場名 = "益田", 場名コード = "29" },
            new 場名マスタ { 場名 = "福山", 場名コード = "30" },
            new 場名マスタ { 場名 = "高知", 場名コード = "31" },
            new 場名マスタ { 場名 = "佐賀", 場名コード = "32" },
            new 場名マスタ { 場名 = "荒尾", 場名コード = "33" },
            new 場名マスタ { 場名 = "中津", 場名コード = "34" }
        };

        /// <summary>
        /// 場名コードから場名を取得します。
        /// </summary>
        /// <param name="場名コード">場名コード</param>
        /// <returns>場名（見つからない場合は例外）</returns>
        public static string GetByCode(string 場名コード)
        {
            var result = MasterData.FirstOrDefault(d => d.場名コード == 場名コード);
            if (result == null)
            {
                throw new InvalidOperationException($"場名コードが見つかりません: {場名コード}");
            }
            return result.場名;
        }
        /// <summary>
        /// 場名から場名コードを取得します。
        /// </summary>
        /// <param name="場名">場名コード</param>
        /// <returns>場名（見つからない場合は例外）</returns>
        public static string GetByPlace(string 場名)
        {
            var result = MasterData.FirstOrDefault(d => d.場名 == 場名);
            if (result == null)
            {
                throw new InvalidOperationException($"場名が見つかりません: {場名}");
            }
            return result.場名コード;
        }
    }
}
