// 役割: アプリ全体で使う共通ロガーです。
// ログファイル、デバッグ出力、Windowsイベントログへ同じ形式で出力し、サービス層の例外調査を支援します。
using NLog; // NLog を使用するための名前空間
using System.Diagnostics; // Windows イベントログ操作用名前空間
using System.Runtime.CompilerServices; // 呼び出し元情報取得用名前空間
using System.Runtime.Versioning; // OSプラットフォーム判定用名前空間
using Microsoft.Extensions.Configuration; // appsettings.json 読み込み用名前空間
using System.IO; // ファイル操作用名前空間

namespace 中央競馬.共通.Libraly
{
    /// <summary>
    /// NLog を使用したログ管理クラス。
    /// ファイル、コンソール、Windowsイベントログ(Application)に出力。
    /// </summary>
    public static class Logger
    {
        private static readonly NLog.Logger _logger = LogManager.GetCurrentClassLogger(); // NLog のロガーインスタンス
        private static readonly string _eventLogSource; // Windowsイベントログのソース名

        /// <summary>
        /// 静的コンストラクタでappsettings.jsonから設定値を読み込む
        /// </summary>
        static Logger()
        {
            var configuration = new ConfigurationBuilder()
                .SetBasePath(AppContext.BaseDirectory)
                .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
                .Build();

            _eventLogSource = configuration["EventLogSource"] ?? "application"; // EventLogSource の値を取得
        }

        /// <summary>
        /// 情報ログを出力します。(イベントID付き)
        /// </summary>
        /// <param name="message">ログメッセージ</param>
        /// <param name="eventId">イベントID</param>
        /// <param name="memberName">呼び出し元メソッド名</param>
        /// <param name="filePath">呼び出し元ファイルパス</param>
        /// <param name="lineNumber">呼び出し元行番号</param>
        public static void Log(
            string message,
            int eventId = 0,
            [CallerMemberName] string memberName = "",
            [CallerFilePath] string filePath = "",
            [CallerLineNumber] int lineNumber = 0)
        {
            string className = Path.GetFileNameWithoutExtension(filePath);
            string fullMessage = $"{className}.{memberName} {lineNumber}: {message}";

            _logger.Info(fullMessage); // NLog ログ出力

            if (OperatingSystem.IsWindows() && eventId > 0)
            {
                WriteToEventLog(fullMessage, EventLogEntryType.Information, eventId);
            }
        }

        /// <summary>
        /// エラーログを出力します。(イベントID付き)
        /// </summary>
        /// <param name="message">エラーメッセージ</param>
        /// <param name="ex">例外情報</param>
        /// <param name="eventId">イベントID</param>
        /// <param name="memberName">呼び出し元メソッド名</param>
        /// <param name="filePath">呼び出し元ファイルパス</param>
        /// <param name="lineNumber">呼び出し元行番号</param>
        public static void LogError(
            string message,
            Exception ex,
            int eventId = 0,
            [CallerMemberName] string memberName = "",
            [CallerFilePath] string filePath = "",
            [CallerLineNumber] int lineNumber = 0)
        {
            string fullMessage = string.Empty;
            string className = Path.GetFileNameWithoutExtension(filePath);
            if(ex != null)
            {
                fullMessage = $"ERROR: {className}.{memberName} {lineNumber}: {message} - {ex.Message}";
            }
            else
            {
                fullMessage = $"ERROR: {className}.{memberName} {lineNumber}: {message}";
            }

            _logger.Error(ex, fullMessage); // NLog エラーログ出力

            if (OperatingSystem.IsWindows() && eventId > 0)
            {
                if (ex != null)
                {
                    WriteToEventLog(fullMessage + Environment.NewLine + ex.StackTrace, EventLogEntryType.Error, eventId);
                }
                else
                {
                    WriteToEventLog(fullMessage, EventLogEntryType.Error, eventId);
                }
            }
        }

        /// <summary>
        /// Windowsイベントログにメッセージを出力します。(イベントID付き)
        /// </summary>
        /// <param name="message">ログメッセージ</param>
        /// <param name="type">イベントログエントリタイプ</param>
        /// <param name="eventId">イベントID</param>
        [SupportedOSPlatform("windows")]
        private static void WriteToEventLog(string message, EventLogEntryType type, int eventId)
        {
            if (!EventLog.SourceExists(_eventLogSource))
            {
                EventLog.CreateEventSource(_eventLogSource, "Application");
            }

            // イベントIDを指定してイベントログに出力
            using (EventLog eventLog = new EventLog("Application"))
            {
                eventLog.Source = _eventLogSource;
                eventLog.WriteEntry(message, type, eventId);
            }
        }
    }
}
