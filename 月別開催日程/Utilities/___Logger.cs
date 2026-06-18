using System; // 基本的なシステム機能を提供する名前空間
using System.Diagnostics; // デバッグおよびイベントログ関連の機能を提供する名前空間
using System.IO; // ファイルおよびデータストリームの操作を提供する名前空間
using Microsoft.Extensions.Configuration; // appsettings.json の読み取りをサポートする名前空間

namespace 中央競馬.Utilities
{
    /// <summary>
    /// 現在は旧園田抽出クラスからのみ参照される退避用ロガーです。
    /// 現行処理では 共通.Libraly.Logger を使用します。
    /// </summary>
    public class ___Logger
    {
        private static readonly string ___logFilePath; // ログファイルのパス
        private static readonly string ___eventLogSource; // イベントソース名

        static ___Logger()
        {
            var configuration = new ConfigurationBuilder()
                .SetBasePath(Directory.GetCurrentDirectory())
                .AddJsonFile("appsettings.json")
                .Build();

            ___logFilePath = configuration["LogFilePath"] ?? @"c:\\temp\\log.txt";
            ___eventLogSource = configuration["EventLogSource"] ?? "application";
        }

        public static void ___Log(string message, [System.Runtime.CompilerServices.CallerMemberName] string memberName = "", [System.Runtime.CompilerServices.CallerFilePath] string filePath = "")
        {
            string className = Path.GetFileNameWithoutExtension(filePath);
            string logEntry = $"[{DateTime.Now}] {className}.{memberName}: {message}";
            Debug.WriteLine(logEntry);
            File.AppendAllText(___logFilePath, logEntry + Environment.NewLine);

            if (OperatingSystem.IsWindows())
            {
                if (!EventLog.SourceExists(___eventLogSource))
                {
                    EventLog.CreateEventSource(___eventLogSource, "Application");
                }
                EventLog.WriteEntry(___eventLogSource, logEntry, EventLogEntryType.Information);
            }
        }

        public static void ___LogError(string message, Exception ex, [System.Runtime.CompilerServices.CallerMemberName] string memberName = "", [System.Runtime.CompilerServices.CallerFilePath] string filePath = "")
        {
            string className = Path.GetFileNameWithoutExtension(filePath);
            string logEntry = $"[{DateTime.Now}] ERROR: {className}.{memberName}: {message} - {ex.Message}\n{ex.StackTrace}";
            Debug.WriteLine(logEntry);
            File.AppendAllText(___logFilePath, logEntry + Environment.NewLine);

            if (OperatingSystem.IsWindows())
            {
                if (!EventLog.SourceExists(___eventLogSource))
                {
                    EventLog.CreateEventSource(___eventLogSource, "Application");
                }
                EventLog.WriteEntry(___eventLogSource, logEntry, EventLogEntryType.Error);
            }
        }
    }
}
