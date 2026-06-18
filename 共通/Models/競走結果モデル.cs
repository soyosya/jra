// 役割: 成績ページから取得した競走結果を保存するEFモデルです。
// 着順、馬番、走破時計、上り3F、コーナー通過順を保持し、分析や予測処理で参照します。
using System; // 基本的なシステム機能を提供する名前空間
using Microsoft.EntityFrameworkCore; // Entity Framework Coreのデータベース操作をサポートする名前空間
using System.ComponentModel.DataAnnotations; // データ注釈の属性を使用する名前空間
using System.ComponentModel.DataAnnotations.Schema; // スキーマ属性を使用する名前空間

namespace 中央競馬.共通.Models
{
    /// <summary>
    /// 競走結果を表すエンティティクラス。
    /// データベースの競走結果テーブルと対応します。
    /// </summary>
    public class 競走結果モデル
    {
        [Key] // プライマリキーを示す
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)] // 自動採番を有効にする
        public int Id { get; set; }  // 自動採番用の主キー
        [MaxLength(4)]
        public string 開催場所 { get; set; } = string.Empty; // 開催場所
        public DateOnly 開催日 { get; set; } = new DateOnly(1900,1,1); // 開催日
        public int レース番号 { get; set; } = 0; // レース番号
        public int 着順 { get; set; } = 0; // 着順
        public int 枠番 { get; set; } = 0; // 枠番
        public int 馬番 { get; set; } = 0; // 馬番
        [MaxLength(9)]
        public string 馬名 { get; set; } = string.Empty; // 馬名
        [Column(TypeName = "decimal(4,1)")]
        public decimal 一着馬着差タイム { get; set; } = 0.0m;// 一着馬との着差タイム
        [Column(TypeName = "decimal(4,1)")]
        public decimal 先着馬着差タイム { get; set; } = 0.0m; // 先着馬との着差タイム
        [Column(TypeName = "decimal(4,1)")]
        public decimal 後着馬着差タイム { get; set; } = 0.0m; // 後着馬との着差タイム
        [Column(TypeName = "decimal(4,1)")]
        public decimal 上り3F { get; set; } = 0.0m; // 上り3F
        [Column(TypeName = "decimal(4,1)")]
        public decimal 走破時計 { get; set; } = 0.0m; // 走破時計
        [MaxLength(16)]
        public string 着差 { get; set; } = string.Empty; // 着差
        public int 一コーナー { get; set; }=0; // 一コーナー通過順
        public int 二コーナー { get; set; } = 0; // 二コーナー通過順
        public int 三コーナー { get; set; } = 0; // 三コーナー通過順
        public int 四コーナー { get; set; } = 0; // 四コーナー通過順
        /*
        public int 払戻金Id { get; set; } = 0;// 払戻金モデルへの外部キー
        public 払戻金モデル 払戻金 { get; set; } = null!; // ナビゲーションプロパティ
        public int レース情報Id { get; set; } // レース情報モデルへの外部キー
        public レース情報モデル レース情報 { get; set; } = null!; // ナビゲーションプロパティ
        */
        public static void Configure(ModelBuilder modelBuilder)
        {
            var entity = modelBuilder.Entity<競走結果モデル>();

            // プライマリキーの設定
            entity.HasKey(h => h.Id);
/*
            // 外部キーの設定
            entity.HasOne(h => h.払戻金)
                  .WithMany(p => p.競走結果)
                  .HasForeignKey(h => h.払戻金Id);

            entity.HasOne(h => h.レース情報)
                  .WithMany(r => r.競走結果)
                  .HasForeignKey(h => h.レース情報Id);
*/
        }
    }
}
