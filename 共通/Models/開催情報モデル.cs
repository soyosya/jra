// 役割: 開催情報テーブルのEFモデルです。
// 開催日と開催場所を複合キーにし、当日メニューURLを保存して後続取得処理の起点にします。
using System; // 基本的なシステム機能を提供する名前空間
using System.ComponentModel.DataAnnotations;
using Microsoft.EntityFrameworkCore; // Entity Framework Coreのデータベース操作をサポートする名前空間

namespace 中央競馬.共通.Models
{
    /// <summary>
    /// 開催情報データを表すエンティティクラス。
    /// データベースの開催情報テーブルと対応します。
    /// </summary>
    public class 開催情報モデル
    {
        [MaxLength(4)]
        public string 開催場所 { get; set; } = string.Empty; // 開催場所
        public DateOnly 開催日 { get; set; } = new DateOnly(1900,1,1); // 開催日
        [MaxLength(512)]
        public string 当日メニューURL { get; set; } = string.Empty; // 当日メニューURL

        /// <summary>
        /// 開催情報クラスの設定を行います。
        /// </summary>
        /// <param name="modelBuilder">モデルビルダー</param>
        public static void Configure(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<開催情報モデル>().HasKey(h => new { h.開催日, h.開催場所 }); // 複合キーを設定
        }
    }
}
