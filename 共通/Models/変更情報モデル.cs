// 役割: 当日メニューに掲載される出走取消や騎手変更などの変更情報を保存するEFモデルです。
// 開催日、開催場所、レース番号、馬番で対象を特定し、レース情報の補足として利用します。
using System; // 基本的なシステム機能を提供する名前空間
using Microsoft.EntityFrameworkCore; // Entity Framework Coreのデータベース操作をサポートする名前空間
using System.ComponentModel.DataAnnotations; // データ注釈の属性を使用する名前空間
using System.ComponentModel.DataAnnotations.Schema; // スキーマ属性を使用する名前空間

namespace 中央競馬.共通.Models
{
    /// <summary>
    /// 変更情報データを表すエンティティクラス。
    /// </summary>
    public class 変更情報モデル
    {
        [Key] // プライマリキーを示す
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)] // 自動採番を有効にする
        public int Id { get; set; }  // 自動採番用の主キー
        [MaxLength(4)]
        public string 開催場所 { get; set; } = string.Empty; // 開催場所
        public DateOnly 開催日 { get; set; } = new DateOnly(1900,1,1); // 開催日
        public int レース番号 { get; set; } = 0;// レース番号
        public int 馬番 { get; set; } = 0; // 馬番
        [MaxLength(9)]
        public string 馬名 { get; set; } = string.Empty; // 馬名
        [MaxLength(16)]
        public string 変更区分 { get; set; } = string.Empty; // 変更区分
        [MaxLength(64)]
        public string 変更理由 { get; set; } = string.Empty; // 変更理由
        [MaxLength(64)]
        public string 変更内容 { get; set; } = string.Empty; // 変更内容

        public static void Configure(ModelBuilder modelBuilder)
        {
            var entity = modelBuilder.Entity<変更情報モデル>();

            // プライマリキーの設定
            entity.HasKey(h => h.Id);
            // 複合インデックスの設定
            entity.HasIndex(h => new { h.開催日,h.開催場所,h.レース番号, h.馬名 })
                  .HasDatabaseName("IX_開催日_開催場所_レース番号_馬名"); // インデックス名を指定
            entity.HasIndex(h => new { h.開催日, h.開催場所, h.レース番号})
                  .HasDatabaseName("IX_開催日_開催場所_レース番号"); // インデックス名を指定
        }
    }
}
