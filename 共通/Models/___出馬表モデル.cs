using Microsoft.EntityFrameworkCore;
using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace 中央競馬.共通.Models
{
    /// <summary>
    /// 出馬表テーブルのエンティティクラス
    /// </summary>
    [Table("出馬表")]
    public class ___出馬表モデル
    {
        [Key] // プライマリキーを示す
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)] // 自動採番を有効にする
        public int ___Id { get; set; }  // 自動採番用の主キー
        [Required, MaxLength(4)]
        public string ___開催場所 { get; set; } = string.Empty;

        [Required]
        public DateOnly ___開催日 { get; set; }= new DateOnly();

        [Required]
        public int ___レース番号 { get; set; } = 0;

        [Required]
        public DateTime ___発走時刻 { get; set; }= new DateTime();

        [Required, MaxLength(9)]
        public string ___馬名 { get; set; } = string.Empty;

        [Required]
        public int ___前走Id { get; set; } = 0;

        [Required]
        public DateOnly ___前走日 { get; set; }

        [Required]
        public decimal ___前走上り3F { get; set; } = 0;

        [MaxLength(30)]
        public string? ___前走間隔 { get; set; } = string.Empty;

        [MaxLength(2)]
        public string? ___休み明け判定 { get; set; } = string.Empty;

        public int? ___平均間隔 { get; set; } = 0;
        public int? ___標準偏差 { get; set; } = 0;

        [Required]
        public float ___斤量差 { get; set; } = 0;

        [Required, MaxLength(2)]
        public string ___距離延短 { get; set; } = string.Empty;

        [MaxLength(30)]
        public string ___距離差 { get; set; } = string.Empty;

        [Required, MaxLength(2)]
        public string ___周回方向変化 { get; set; } = string.Empty;

        [Required, MaxLength(4)]
        public string ___前走場所 { get; set; } = string.Empty;

        [Required, MaxLength(1)]
        public string ___コース種別 { get; set; } = string.Empty;

        [Required, MaxLength(1)]
        public string ___周回方向 { get; set; } = string.Empty;

        [Required]
        public int ___距離 { get; set; } = 0;

        [Required, MaxLength(2)]
        public string ___天候 { get; set; } = string.Empty;

        [Required, MaxLength(3)]
        public string ___馬場 { get; set; } = string.Empty;

        [Required, MaxLength(64)]
        public string ___条件 { get; set; } = string.Empty;

        [Required, MaxLength(64)]
        public string ___競走名 { get; set; } = string.Empty;

        [Required]
        public decimal ___一着賞金 { get; set; } = 0;

        [Required]
        public decimal ___二着賞金 { get; set; } = 0;

        [Required]
        public decimal ___三着賞金 { get; set; } = 0;

        [Required]
        public decimal ___四着賞金 { get; set; } = 0;

        [Required]
        public decimal ___五着賞金 { get; set; } = 0;

        [Required]
        public int ___着順 { get; set; } = 0;

        [Required]
        public int ___枠番 { get; set; } = 0;

        [Required]
        public int ___馬番 { get; set; } = 0;

        [Required]
        public int ___馬齢 { get; set; } = 0;

        [Required, MaxLength(2)]
        public string ___性別 { get; set; } = string.Empty;

        [Required, MaxLength(4)]
        public string ___毛色 { get; set; } = string.Empty;

        [Required, MaxLength(10)]
        public string ___騎手 { get; set; } = string.Empty;

        [Required, MaxLength(4)]
        public string ___騎手所属 { get; set; } = string.Empty;

        [Required]
        public float ___斤量 { get; set; } = 0;

        [Required]
        public float ___斤量増減 { get; set; } = 0;

        [Required, MaxLength(1)]
        public string ___減量記号 { get; set; } = string.Empty;

        [Required]
        public int ___馬体重 { get; set; } = 0;

        [Required]
        public int ___馬体重増減 { get; set; } = 0;

        [Required, MaxLength(10)]
        public string ___調教師 { get; set; } = string.Empty;

        [Required, MaxLength(4)]
        public string ___調教師所属 { get; set; } = string.Empty;

        [Required, MaxLength(32)]
        public string ___馬主 { get; set; } = string.Empty;

        [Required, MaxLength(64)]
        public string ___変更情報 { get; set; } = string.Empty;

        [Required, MaxLength(512)]
        public string ___馬情報URL { get; set; } = string.Empty;

        [Required, MaxLength(512)]
        public string ___騎手情報URL { get; set; } = string.Empty;

        [Required, MaxLength(512)]
        public string ___調教師情報URL { get; set; } = string.Empty;

        [Required]
        public decimal ___一着馬着差タイム { get; set; } = 0m;

        [Required]
        public decimal ___先着馬着差タイム { get; set; } = 0m;

        [Required]
        public decimal ___後着馬着差タイム { get; set; } = 0m;

        [Required]
        public decimal ___上り3F { get; set; } = 0m;

        [Required]
        public decimal ___走破時計 { get; set; } = 0m;

        [Required, MaxLength(16)]
        public string ___着差 { get; set; } = string.Empty;

        [Required]
        public int ___一コーナー { get; set; } = 0;

        [Required]
        public int ___二コーナー { get; set; } = 0;

        [Required]
        public int ___三コーナー { get; set; } = 0;

        [Required]
        public int ___四コーナー { get; set; } = 0;
        public static void ___Configure(ModelBuilder modelBuilder)
        {
            var entity = modelBuilder.Entity<___出馬表モデル>();

            // プライマリキーの設定
            entity.HasKey(h => h.___Id);

            // 複合インデックスの設定
            entity.HasIndex(h => new { h.___一着賞金 })
                  .HasDatabaseName("IX_Id_一着賞金"); // インデックス名を指定

        }
    }
}

