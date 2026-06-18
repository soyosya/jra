// 役割: 既存DBのId列がIDENTITY化済みかどうかを判定する補助クラスです。
// 移行途中のDBでも保存処理を継続できるよう、必要な場合だけ手動採番を行います。
using System;
using System.Data;
using Microsoft.EntityFrameworkCore;

namespace 中央競馬.共通.Data
{
    /// <summary>
    /// 既存DBのId列がIDENTITY化済みかどうかを吸収するための補助クラスです。
    /// 移行途中のDBでも保存処理を継続できるよう、必要なときだけ次のIdを手動採番します。
    /// </summary>
    public static class DbIdentityHelper
    {
        /// <summary>
        /// 指定テーブルのId列がIDENTITY属性を持つか確認します。
        /// </summary>
        public static bool IsIdentityColumn(DBContext context, string tableName, string columnName = "Id")
        {
            return ExecuteScalarInt(
                context,
                $"SELECT ISNULL(CONVERT(int, COLUMNPROPERTY(OBJECT_ID(N'[dbo].[{tableName}]'), N'{columnName}', 'IsIdentity')), 0)") == 1;
        }

        /// <summary>
        /// IDENTITY未設定テーブルへ追加するため、現在の最大Idに1を加えた値を取得します。
        /// </summary>
        public static int GetNextId(DBContext context, string tableName)
        {
            return ExecuteScalarInt(context, $"SELECT ISNULL(MAX([Id]), 0) + 1 FROM [dbo].[{tableName}]");
        }

        /// <summary>
        /// 単一整数値を返すSQLを実行します。
        /// DbContextの接続状態を保ち、ここで開いた接続だけを閉じるようにしています。
        /// </summary>
        private static int ExecuteScalarInt(DBContext context, string sql)
        {
            var connection = context.Database.GetDbConnection();
            var shouldClose = connection.State != ConnectionState.Open;
            if (shouldClose) connection.Open();

            try
            {
                using var command = connection.CreateCommand();
                command.CommandText = sql;
                var result = command.ExecuteScalar();
                return result == null || result == DBNull.Value ? 0 : Convert.ToInt32(result);
            }
            finally
            {
                if (shouldClose) connection.Close();
            }
        }
    }
}
