// 役割: リアルタイムオッズのチャート表示アプリを起動する入口です。
// 保存済みオッズを確認するため、RealTimeOddsChartフォームを表示します。
namespace DatabaseExplorerApp
{
    internal static class Program
    {
        /// <summary>
        ///  The main entry point for the application.
        /// </summary>
        [STAThread]
        static void Main()
        {
            // To customize application configuration such as set high DPI settings or default font,
            // see https://aka.ms/applicationconfiguration.
            ApplicationConfiguration.Initialize();
            Application.Run(new RealTimeOddsChart.RealTimeOddsChart());
        }
    }
}