// 役割: 取得時点ごとのリアルタイムオッズを保存するEFモデルです。
// レース、馬番、オッズ、取得時刻を保持し、チャート表示や推移分析に利用します。
using System; // 基本的なシステム機能を提供する名前空間
using Microsoft.EntityFrameworkCore; // Entity Framework Coreのデータベース操作をサポートする名前空間
using System.ComponentModel.DataAnnotations; // データ注釈の属性を使用する名前空間
using System.ComponentModel.DataAnnotations.Schema; // スキーマ属性を使用する名前空間

namespace 中央競馬.共通.Models
{
    /// <summary>
    /// リアルタイムオッズを表すエンティティクラス。
    /// </summary>
    public class リアルタイムオッズモデル
    {
        [Key] // プライマリキーを示す
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)] // 自動採番を有効にする
        public int Id { get; set; }  // 自動採番用の主キー
        [MaxLength(4)]
        public string 開催場所 { get; set; } = string.Empty; // 開催場所
        public DateOnly 開催日 { get; set; } = new DateOnly(1900,1,1); // 開催日
        public int レース番号 { get; set; } = 0; // レース番号
        public int 馬番 { get; set; } = 0; // 馬番
        [MaxLength(9)]
        public string 馬名 { get; set; } = string.Empty; // 馬名
        public double 単勝オッズ { get; set; } = 0.0; // 単勝オッズ
        public string 複勝オッズ { get; set; } = string.Empty; // 複勝オッズ
        public double 複勝オッズ_MIN { get; set; } = 0.0; // 複勝オッズ最小
        public double 複勝オッズ_MAX { get; set; } = 0.0; // 複勝オッズ最大
        public int 人気 { get; set; } = 0; // 人気
        public DateTime 日時 { get; set; } = new DateTime(); // 取得日時
        public static void Configure(ModelBuilder modelBuilder)
        {
            var entity = modelBuilder.Entity<リアルタイムオッズモデル>();

            // プライマリキーの設定
            entity.HasKey(h => h.Id);

            // 複合インデックスの設定
            entity.HasIndex(h => new { h.開催日, h.開催場所, h.レース番号, h.馬名, h.馬番 })
                  .HasDatabaseName("IX_開催日_開催場所_レース番号_馬名_馬番")
                  .IncludeProperties(h => new { h.日時, h.単勝オッズ, h.複勝オッズ, h.複勝オッズ_MIN, h.複勝オッズ_MAX });

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
