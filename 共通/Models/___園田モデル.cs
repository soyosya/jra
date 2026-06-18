using System; // 基本的なシステム機能を提供する名前空間
using System.Collections.Generic; // ジェネリックコレクションをサポートする名前空間
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration; // appsettings.json の読み取りをサポートする名前空間

namespace 中央競馬.共通.Models
{
    /// <summary>
    /// 現在はDBContextに登録されていない旧園田競馬の格モデルです。
    /// 再利用時はDBスキーマとConfigure登録の要否を確認してください。
    /// </summary>
    public class ___園田モデル
    {
        [Key] // プライマリキーを示す
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)] // 自動採番を有効にする
        public int ___Id { get; set; }  // 自動採番用の主キー
        /// <summary>
        /// 馬名マスタID
        /// </summary>
        [MaxLength(9)]
        public int ___馬名Id { get; set; } = 0;
        /// <summary>
        /// ポイント
        /// </summary>
        public int ___ポイント { get; set; } = 0;
        /// <summary>
        /// 自場収得賞金
        /// </summary>
        public int ___自場収得賞金 { get; set; } = 0;
        /// <summary>
        /// 格
        /// </summary>
        [MaxLength(2)]
        public string ___格 { get; set; } = string.Empty;
        /// <summary>
        /// 評価日
        /// </summary>
        public DateOnly ___評価日 { get; set; } = new DateOnly(1900,1,1);
        /// <summary>
        /// 更新日=開催日
        /// </summary>
        public DateOnly ___更新日 { get; set; } = new DateOnly(1900, 1, 1);
        /// <summary>
        /// 園田モデルの設定を行います。
        /// </summary>
        /// <param name="modelBuilder">モデルビルダー</param>
        public static void ___Configure(ModelBuilder modelBuilder)
        {
            var entity = modelBuilder.Entity<___園田モデル>();
            // プライマリキーの設定
            entity.HasKey(h => h.___Id);

            entity.HasIndex(h => new { h.___馬名Id, h.___更新日 })
                  .HasDatabaseName("IX_園田_馬名Id_更新日")
                  .IsUnique();
        }

    }
}
