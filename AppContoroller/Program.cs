// 役割: AppContoroller のWindows Forms起動入口です。
// NLog設定を読み込み、手動取得や欠落補完を操作するメインフォームを表示します。
// 取得処理の実体は AppController フォーム内のボタンイベントからサービス層へ委譲します。
using NLog;
using NLog.Config;
using System.Runtime.Versioning;

namespace AppController
{
    internal static class Program
    {
        /// <summary>
        ///  The main entry point for the application.
        /// </summary>
        [SupportedOSPlatform("windows6.1")]
        [STAThread]
        static void Main(string[] args)
        {
            var configPath = Path.Combine(AppContext.BaseDirectory, "NLog.config");
            LogManager.Configuration = new XmlLoggingConfiguration(configPath);
            // To customize application configuration such as set high DPI settings or default font,
            // see https://aka.ms/applicationconfiguration.
            ApplicationConfiguration.Initialize();
            bool getDayliyRace = args.Contains("/getDayliyRace", StringComparer.OrdinalIgnoreCase);
            bool isGetRealtimeInfo = args.Contains("/getRealtimeInfo", StringComparer.OrdinalIgnoreCase);

            ApplicationConfiguration.Initialize();
            Application.Run(new AppController(getDayliyRace, isGetRealtimeInfo)); // 引数でフラグを渡す
        }
    }
}