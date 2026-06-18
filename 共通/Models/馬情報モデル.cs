// 役割: 競走馬プロフィールを保存するEFモデルです。
// 馬名の重複に備え、馬名と調教師を検索キーとして扱い、血統や賞金情報を保持します。
using System; // 基本的なシステム機能を提供する名前空間
using Microsoft.EntityFrameworkCore; // Entity Framework Coreのデータベース操作をサポートする名前空間
using System.ComponentModel.DataAnnotations; // データ注釈の属性を使用する名前空間
using System.ComponentModel.DataAnnotations.Schema; // スキーマ属性を使用する名前空間

namespace 中央競馬.共通.Models
{
    /// <summary>
    /// 馬情報データを表すエンティティクラス。
    /// </summary>
    public class 馬情報モデル
    {
        [Key] // プライマリキーを示す
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)] // 自動採番を有効にする
        public int Id { get; set; }  // 自動採番用の主キー
        [MaxLength(9)]

        public string 馬名 { get; set; } = string.Empty; // 馬名
        public DateOnly 生年月日 { get; set; } = new DateOnly(1900,1,1); // 生年月日
        [MaxLength(2)]
        public string 性別 { get; set; } = string.Empty; // 性別
        [MaxLength(4)]
        public string 毛色 { get; set; } = string.Empty; // 毛色
        [MaxLength(16)]
        public string 産地 { get; set; } = string.Empty; // 産地
        [MaxLength(10)]
        public string 調教師 { get; set; } = string.Empty; // 調教師
        [MaxLength(6)]
        public string 所属 { get; set; } = string.Empty; // 所属
        [MaxLength(32)]
        public string 馬主 { get; set; } = string.Empty; // 馬主
        [MaxLength(32)]
        public string 生産牧場 { get; set; } = string.Empty; // 生産牧場
        public int 地方収得賞金 { get; set; } = 0; // 地方収得賞金
        public int 中央収得賞金 { get; set; } = 0; // 中央収得賞金
        public int 中央付加賞金 { get; set; } = 0; // 中央付加賞金
        [MaxLength(18)]
        public string 父 { get; set; } = string.Empty; // 父
        [MaxLength(18)]
        public string 父父 { get; set; } = string.Empty; // 父父
        [MaxLength(18)]
        public string 父母 { get; set; } = string.Empty; // 父母
        [MaxLength(18)]
        public string 母 { get; set; } = string.Empty; // 母
        [MaxLength(18)]
        public string 母父 { get; set; } = string.Empty; // 母父
        [MaxLength(18)]
        public string 母母 { get; set; } = string.Empty; // 母母
        public DateOnly 更新日 { get; set; } = new DateOnly(); // 更新日

        public static void Configure(ModelBuilder modelBuilder)
        {
            var entity = modelBuilder.Entity<馬情報モデル>();

            // プライマリキーの設定
            entity.HasKey(h => h.Id);

            // インデックスの設定
            entity.HasIndex(h => new { h.馬名, h.調教師 })
                  .HasDatabaseName("IX_馬名_調教師");
            entity.HasIndex(h => new { h.馬主 })
                  .HasDatabaseName("IX_馬主");
            entity.HasIndex(h => new { h.調教師 })
                  .HasDatabaseName("IX_調教師");
            entity.HasIndex(h => new { h.馬名, h.更新日 })
                  .HasDatabaseName("IX_馬名_更新日");
            entity.HasIndex(h => new { h.馬名, h.生年月日, h.父 })
                  .HasDatabaseName("IX_馬名_生年月日_父").IsUnique();
        }
    }
}
