// 役割: dotnet ef など設計時ツールからDBContextを生成するためのファクトリーです。
// 通常実行時ではなく、マイグレーション作成やモデル確認時に接続文字列を解決するために使います。
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.Extensions.Configuration;
using System.IO;
using 中央競馬.共通.Data;

namespace 中央競馬.Data
{
    /// <summary>
    /// デザイン時の DbContext ファクトリー（dotnet ef 用）
    /// </summary>
    public class DBContextFactory : IDesignTimeDbContextFactory<DBContext>
    {
        public DBContext CreateDbContext(string[] args)
        {
            var configuration = new ConfigurationBuilder()
                .SetBasePath(Directory.GetCurrentDirectory()) // 実行場所を基準
                .AddJsonFile("appsettings.json", optional: false)
                .Build();

            var optionsBuilder = new DbContextOptionsBuilder<DBContext>();
            optionsBuilder.UseSqlServer(configuration.GetConnectionString("DefaultConnection"));

            return new DBContext(optionsBuilder.Options);
        }
    }
}
