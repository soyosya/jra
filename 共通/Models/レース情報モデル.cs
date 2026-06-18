// 役割: 出馬表から取得した出走馬ごとのレース情報を保存するEFモデルです。
// 馬情報URL、騎手情報URL、調教師情報URLを保持し、馬プロフィールや履歴補完の入口にもなります。
using System; // 基本的なシステム機能を提供する名前空間
using Microsoft.EntityFrameworkCore; // Entity Framework Coreのデータベース操作をサポートする名前空間
using System.ComponentModel.DataAnnotations; // データ注釈の属性を使用する名前空間
using System.ComponentModel.DataAnnotations.Schema; // スキーマ属性を使用する名前空間

namespace 中央競馬.共通.Models
{
    /// <summary>
    /// レース情報を表すエンティティクラス。
    /// データベースのレース情報テーブルと対応します。
    /// </summary>
    public class レース情報モデル
    {
        [Key] // プライマリキーを示す
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)] // 自動採番を有効にする
        public int Id { get; set; }  // 自動採番用の主キー
        [MaxLength(4)]
        public string 開催場所 { get; set; } = string.Empty; // 開催場所
        public DateOnly 開催日 { get; set; } = new DateOnly(1900,1,1); // 開催日
        public int レース番号 { get; set; } = 0; // レース番号
        public DateTime 発走時刻 { get; set; } = new DateTime(1900,1,1,0,0,0); // 発走時刻
        [MaxLength(1)]
        public string コース種別 { get; set; } = string.Empty; // 芝・ダート
        [MaxLength(1)]
        public string 周回方向 { get; set; } = string.Empty; // 右・左
        public int 距離 { get; set; } = 0; // 距離
        [MaxLength(2)]
        public string 天候 { get; set; } = string.Empty; // 天候
        [MaxLength(3)]
        public string 馬場 { get; set; } = string.Empty; // 馬場
        [MaxLength(128)]
        public string 条件 { get; set; } = string.Empty; // 条件
        [MaxLength(128)]
        public string 競走名 { get; set; } = string.Empty; // 競走名
        [Column(TypeName = "decimal(10, 0)")]
        public decimal 一着賞金 { get; set; } = 0; // 1着賞金
        [Column(TypeName = "decimal(10, 0)")]
        public decimal 二着賞金 { get; set; } = 0; // 2着賞金
        [Column(TypeName = "decimal(10, 0)")]
        public decimal 三着賞金 { get; set; } = 0; // 3着賞金
        [Column(TypeName = "decimal(10, 0)")]
        public decimal 四着賞金 { get; set; } = 0; // 4着賞金
        [Column(TypeName = "decimal(10, 0)")]
        public decimal 五着賞金 { get; set; } = 0; // 5着賞金
        public int 着順 { get; set; } = 0; // 着順
        public int 枠番 { get; set; } = 0; // 枠番
        public int 馬番 { get; set; } = 0; // 馬番
        [MaxLength(9)]
        public string 馬名 { get; set; } = string.Empty; // 馬名
        public int 馬齢 { get; set; } = 0; // 馬齢
        [MaxLength(2)]
        public string 性別 { get; set; } = string.Empty; // 性別
        [MaxLength(4)]
        public string 毛色 { get; set; } = string.Empty; // 毛色
        [MaxLength(10)]
        public string 騎手 { get; set; } = string.Empty; // 騎手
        [MaxLength(4)]
        public string 騎手所属 { get; set; } = string.Empty; // 騎手所属
        public float 斤量 { get; set; } = 0; // 斤量
        public float 斤量増減 { get; set; } = 0; // 斤量増減
        [MaxLength(1)]
        public string 減量記号 { get; set; } = string.Empty; // 減量記号
        public int 馬体重 { get; set; } = 0; // 馬体重
        public int 馬体重増減 { get; set; } = 0; // 馬体重増減
        [MaxLength(10)]
        public string 調教師 { get; set; } = string.Empty; // 調教師
        [MaxLength(4)]
        public string 調教師所属 { get; set; } = string.Empty; // 調教師所属
        [MaxLength(32)]
        public string 馬主 { get; set; } = string.Empty; // 馬主
        [MaxLength(64)]
        public string 変更情報 { get; set; } = string.Empty; // 変更情報
        [MaxLength(512)]
        public string 馬情報URL { get; set; } = string.Empty; // 馬情報URL
        [MaxLength(512)]
        public string 騎手情報URL { get; set; } = string.Empty; // 騎手情報URL
        [MaxLength(512)]
        public string 調教師情報URL { get; set; } = string.Empty; // 調教師情報URL

        public static void Configure(ModelBuilder modelBuilder)
        {
            var entity = modelBuilder.Entity<レース情報モデル>();

            // プライマリキーの設定
            entity.HasKey(h => h.Id);

            // 複合インデックスの設定
            entity.HasIndex(h => new { h.開催日, h.開催場所, h.レース番号, h.馬名 })
                  .HasDatabaseName("IX_開催日_開催場所_レース番号_馬名"); // インデックス名を指定

        }
    }
}
