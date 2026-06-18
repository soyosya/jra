// 役割: 成績ページの払戻金情報を保存するEFモデルです。
// 開催日・開催場所・レース番号・馬券・組番を自然キーとして重複登録を防ぎます。
using System.Collections.Generic; // ジェネリックコレクションをサポートする名前空間
using System.ComponentModel.DataAnnotations.Schema;
using System.ComponentModel.DataAnnotations;
using Microsoft.EntityFrameworkCore; // Entity Framework Coreのデータベース操作をサポートする名前空間

namespace 中央競馬.共通.Models
{
    /// <summary>
    /// 払戻金モデル。
    /// 競走結果モデルの外部キーを含む。
    /// </summary>
    public class 払戻金モデル
    {
        [Key] // プライマリキーを示す
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)] // 自動採番を有効にする
        public int Id { get; set; } // 自動採番用の主キー
        [MaxLength(4)]
        public string 開催場所 { get; set; } = string.Empty; // 開催場所
        public DateOnly 開催日 { get; set; } = new DateOnly(1900, 1, 1); // 開催日
        public int レース番号 { get; set; } = 0;// レース番号
        [MaxLength(3)]
        public string 馬券 { get; set; } = string.Empty; // 馬券の種類
        [MaxLength(8)]
        public string 組番 { get; set; } = string.Empty; // 組番
        [Column(TypeName = "decimal(10, 0)")]
        public decimal 金額 { get; set; } = 0; // 金額

        public static void Configure(ModelBuilder modelBuilder)
        {
            var entity = modelBuilder.Entity<払戻金モデル>();

            // プライマリキー設定
            entity.HasKey(h => h.Id);

            // 同一レース・馬券・組番の重複登録を防ぐ
            entity.HasIndex(h => new { h.開催日, h.開催場所, h.レース番号, h.馬券, h.組番 })
                  .HasDatabaseName("IX_払戻金_開催日_開催場所_レース番号_馬券_組番")
                  .IsUnique();
        }
    }
}
