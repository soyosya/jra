// 役割: 当日メニューテーブルのEFモデルです。
// レース番号、発走時刻、出馬表URL、成績URLを保持し、レース情報・競走結果・払戻金取得をつなぎます。
using System; // 基本的なシステム機能を提供する名前空間
using Microsoft.EntityFrameworkCore; // Entity Framework Coreのデータベース操作をサポートする名前空間
using System.ComponentModel.DataAnnotations; // データ注釈の属性を使用する名前空間
using System.ComponentModel.DataAnnotations.Schema; // スキーマ属性を使用する名前空間

namespace 中央競馬.共通.Models
{
    /// <summary>
    /// 当日メニューデータを表すエンティティクラス。
    /// データベースの当日メニューテーブルと対応します。
    /// </summary>
    public class 当日メニューモデル
    {
        [Key] // プライマリキーを示す
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)] // 自動採番を有効にする
        public int Id { get; set; }  // 自動採番用の主キー
        [MaxLength(4)]

        public string 開催場所 { get; set; } = string.Empty; // 開催場所
        public DateOnly 開催日 { get; set; } = new DateOnly(1900,1,1); // 開催日
        public int レース番号 { get; set; } = 0;// レース番号
        public DateTime 発走時刻 { get; set; } = new DateTime(1900,1,1,0,0,0); // 発走時刻
        [MaxLength(16)]
        public string 変更 { get; set; } = string.Empty; // 変更
        [MaxLength(64)]
        public string 競走種類 { get; set; } = string.Empty; // 競走種類
        [MaxLength(64)]
        public string 競走名 { get; set; } = string.Empty; // 競走名
        [MaxLength(1)]
        public string 周回方向 { get; set; } = string.Empty; // 周回方向
        public int 距離 { get; set; } = 0; // 距離
        [MaxLength(2)]
        public string 天候 { get; set; } = string.Empty; // 天候
        [MaxLength(3)]
        public string 馬場 { get; set; } = string.Empty; // 馬場
        public int 頭数 { get; set; } = 0;// 頭数
        [MaxLength(512)]
        public string 出馬表URL { get; set; } = string.Empty; // 出馬表URL
        [MaxLength(512)]
        public string 成績URL { get; set; } = string.Empty; // 成績URL

        public static void Configure(ModelBuilder modelBuilder)
        {
            var entity = modelBuilder.Entity<当日メニューモデル>();

            // プライマリキーの設定
            entity.HasKey(h => h.Id);

            // 複合インデックスの設定
            entity.HasIndex(h => new { h.開催日, h.開催場所, h.レース番号 })
                  .HasDatabaseName("IX_開催日_開催場所_レース番号"); // インデックス名を指定
        }
    }
}
