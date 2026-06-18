// 役割: SQL Serverと各モデルを接続するEntity Framework CoreのDbContextです。
// 開催情報を起点に、当日メニュー、レース情報、競走結果、払戻金、馬情報をDbSetとして公開します。
// appsettings.json のDefaultConnectionを読み込み、サービス層とUI層から共通利用します。
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.JSInterop.Infrastructure;
using 中央競馬.共通.Models;

namespace 中央競馬.共通.Data
{
    /// <summary>
    /// データベースコンテキストクラス。
    /// </summary>
    public class DBContext : DbContext
    {
        // DbSet プロパティ: データベースの各テーブルを表します。
        public DbSet<払戻金モデル> 払戻金 { get; set; }
        public DbSet<競走結果モデル> 競走結果 { get; set; }
        public DbSet<レース情報モデル> レース情報 { get; set; }
        public DbSet<当日メニューモデル> 当日メニュー { get; set; }
        public DbSet<開催情報モデル> 開催情報 { get; set; }
        public DbSet<変更情報モデル> 変更情報 { get; set; }
        public DbSet<リアルタイムオッズモデル> リアルタイムオッズ { get; set; }
        public DbSet<馬情報モデル> 馬情報 { get; set; }

        /// <summary>
        /// コンストラクタ: DbContextOptions を受け取ります。
        /// </summary>
        /// <param name="options">DbContextOptions</param>
        public DBContext(DbContextOptions<DBContext> options) : base(options) { }
        // パラメータレスコンストラクタ
        public DBContext() { }

        /// <summary>
        /// DI を使用せず手動で DBContext を初期化する場合に備えた OnConfiguring の構成。
        /// </summary>
        //protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
        //{
        //    if (!optionsBuilder.IsConfigured) // DI 経由で設定されていない場合
        //    {
        //        var configuration = new ConfigurationBuilder()
        //            .SetBasePath(AppContext.BaseDirectory)
        //            .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
        //            .Build();

        //        var connectionString = configuration.GetConnectionString("DefaultConnection");
        //        optionsBuilder.UseSqlServer(connectionString);
        //    }
        //}
        protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
        {
            if (!optionsBuilder.IsConfigured)
            {
                var configuration = new ConfigurationBuilder()
                    .SetBasePath(AppContext.BaseDirectory)
                    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
                    .Build();

                var connectionString = configuration.GetConnectionString("DefaultConnection");

                if (string.IsNullOrWhiteSpace(connectionString))
                {
                    throw new InvalidOperationException("Connection string is not configured.");
                }

                optionsBuilder.UseSqlServer(connectionString);
            }
        }

        /// <summary>
        /// モデルのカスタム構成を適用します。
        /// </summary>
        /// <param name="modelBuilder">ModelBuilder インスタンス</param>
        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            // モデルごとの構成を適用
            払戻金モデル.Configure(modelBuilder);
            競走結果モデル.Configure(modelBuilder);
            レース情報モデル.Configure(modelBuilder);
            当日メニューモデル.Configure(modelBuilder);
            開催情報モデル.Configure(modelBuilder);
            変更情報モデル.Configure(modelBuilder);
            リアルタイムオッズモデル.Configure(modelBuilder);
            馬情報モデル.Configure(modelBuilder);
        }
    }
}
