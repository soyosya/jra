using System.Diagnostics;
using System.Drawing;
using System.Text;
using System.Text.Json;
using System.Windows.Forms;

namespace RunnerTray;

// JRA版タスクトレイ常駐(地方 C:\keiba\RunnerTray の移植)。
// JRA固有差分: PSDIR/appsettings=C:\jra側・port5081・Mutex別(同名だと地方/JRAどちらか片方しか常駐しない)・
//   status.ps1はlauncherCount/balanceを返さない(JRAはjra-weight-loop1本)→黄(待機中)は省略・残高でなく本日確定収支を表示。
static class Program
{
    const string PSDIR = @"C:\jra\RunnerControl\ps";
    const string APPSETTINGS = @"C:\jra\RunnerControl\bin\Release\net10.0\appsettings.json";
    static string PWSH = @"C:\Program Files\PowerShell\7\pwsh.exe";

    static NotifyIcon _ni = null!;
    static ToolStripMenuItem _status = null!;
    static Icon _icGray = null!, _icGreen = null!, _icRed = null!, _icOrange = null!;
    static int _port = 5081;

    [STAThread]
    static void Main()
    {
        // 二重起動防止。★Mutex名は地方(KeibaRunnerTray_SingleInstance)と別=同名だと片方しか常駐しない。
        using var mtx = new System.Threading.Mutex(true, "JraRunnerTray_SingleInstance", out bool isNew);
        if (!isNew) return;
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        if (!File.Exists(PWSH)) PWSH = "pwsh.exe";
        _port = ReadPort();

        _icGray = MakeIcon(Color.Gray);
        _icGreen = MakeIcon(Color.LimeGreen);
        _icRed = MakeIcon(Color.Firebrick);
        _icOrange = MakeIcon(Color.Orange);

        var menu = new ContextMenuStrip();
        _status = new ToolStripMenuItem("状態: 取得中…") { Enabled = false };
        menu.Items.Add(_status);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("起動", null, (s, e) => Control("start"));
        menu.Items.Add("停止", null, (s, e) => Control("stop"));
        menu.Items.Add("再起動", null, (s, e) => Control("restart"));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Webサイトを表示", null, (s, e) => OpenWeb());
        menu.Items.Add("今すぐ状態を更新", null, (s, e) => Refresh());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("トレイ常駐を終了", null, (s, e) => { _ni.Visible = false; Application.Exit(); });

        _ni = new NotifyIcon { Icon = _icGray, Text = "競馬ランナー（JRA)", Visible = true, ContextMenuStrip = menu };
        _ni.DoubleClick += (s, e) => OpenWeb();
        _ni.ShowBalloonTip(8000, "競馬ランナー（JRA)トレイ常駐",
            "ここに常駐しました。右クリックで 起動/停止/再起動/Web表示。\n見えない時はタスクバーの ∧ を開いて、このアイコンを外へドラッグすると常時表示になります。",
            ToolTipIcon.Info);

        var timer = new System.Windows.Forms.Timer { Interval = 20000 };
        timer.Tick += (s, e) => Refresh();
        timer.Start();
        Refresh();

        Application.Run();
    }

    static string ActionJp(string a) => a switch { "start" => "起動", "stop" => "停止", "restart" => "再起動", _ => a };

    static void Control(string action)
    {
        if (action != "stop")
        {
            var r = MessageBox.Show(
                $"JRAランナーを{ActionJp(action)}します。よろしいですか？\n（モードが Auto の場合は実課金の自動投票が動きます）",
                "確認", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning);
            if (r != DialogResult.OK) return;
        }
        string outp;
        try { outp = RunPs("control.ps1", "-Action", action).Trim(); }
        catch (Exception ex) { outp = "失敗: " + ex.Message; }
        _ni.ShowBalloonTip(5000, "JRAランナー操作", string.IsNullOrWhiteSpace(outp) ? ActionJp(action) + "を実行" : outp, ToolTipIcon.Info);
        var t = new System.Windows.Forms.Timer { Interval = 1800 };
        t.Tick += (s, e) => { t.Stop(); t.Dispose(); Refresh(); };
        t.Start();
    }

    static void OpenWeb()
    {
        try { Process.Start(new ProcessStartInfo($"http://localhost:{_port}") { UseShellExecute = true }); }
        catch (Exception ex) { MessageBox.Show("ブラウザ起動に失敗: " + ex.Message, "エラー", MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }

    static void Refresh()
    {
        try
        {
            var d = JsonDocument.Parse(RunPs("status.ps1")).RootElement;
            int rc = d.GetProperty("runnerCount").GetInt32();
            string mode = d.TryGetProperty("curMode", out var mv) && mv.ValueKind == JsonValueKind.String ? (mv.GetString() ?? "") : "";
            string bet = d.TryGetProperty("curBet", out var bv) && bv.ValueKind == JsonValueKind.String ? (bv.GetString() ?? "") : "";
            // 本日確定収支(JRA status= plToday。null可)
            string pl = "—";
            if (d.TryGetProperty("plToday", out var pv) && pv.ValueKind == JsonValueKind.Number)
            {
                int n = pv.GetInt32();
                pl = (n >= 0 ? "+¥" : "-¥") + Math.Abs(n).ToString("N0");
            }

            // 緑=稼働1本 / 赤=停止 / 橙=二重 / 灰=取得失敗 (JRAはlauncher無=黄[待機]は省略・rc=1が稼働/発走待ち両方)
            string st; Icon ic;
            if (rc == 1) { st = "稼働中(1本)"; ic = _icGreen; }
            else if (rc >= 2) { st = $"⚠ {rc}本(二重)"; ic = _icOrange; }
            else { st = "停止中"; ic = _icRed; }
            _ni.Icon = ic;
            string modeTxt = string.IsNullOrEmpty(mode) ? "" : $" / {mode}{(string.IsNullOrEmpty(bet) ? "" : " " + bet)}";
            _status.Text = $"状態: {st}{modeTxt} / 本日 {pl}";
            string tip = $"競馬ランナー（JRA): {st}{modeTxt} / 本日 {pl}";
            _ni.Text = tip.Length > 63 ? tip.Substring(0, 63) : tip;   // ツールチップ上限対策
        }
        catch
        {
            _status.Text = "状態: 取得失敗（Webタスク/権限を確認）";
            _ni.Icon = _icGray;
        }
    }

    static int ReadPort()
    {
        try
        {
            var doc = JsonDocument.Parse(File.ReadAllText(APPSETTINGS));
            if (doc.RootElement.TryGetProperty("Control", out var c) && c.TryGetProperty("Port", out var p)
                && int.TryParse(p.GetString(), out var n)) return n;
        }
        catch { }
        return 5081;
    }

    static string RunPs(string file, params string[] a)
    {
        var psi = new ProcessStartInfo
        {
            FileName = PWSH,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8
        };
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-ExecutionPolicy");
        psi.ArgumentList.Add("Bypass");
        psi.ArgumentList.Add("-File");
        psi.ArgumentList.Add(Path.Combine(PSDIR, file));
        foreach (var x in a) psi.ArgumentList.Add(x);
        var pr = Process.Start(psi)!;
        string o = pr.StandardOutput.ReadToEnd();
        pr.WaitForExit(30000);
        return o;
    }

    // 状態色の丸＋識別文字「中」(中央競馬)。地方トレイは「地」=トレイ上で一目区別。
    static Icon MakeIcon(Color c)
    {
        using var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
            g.Clear(Color.Transparent);
            using var br = new SolidBrush(c); g.FillEllipse(br, 2, 2, 28, 28);
            using var pen = new Pen(Color.White, 2.2f); g.DrawEllipse(pen, 2, 2, 28, 28);
            using var f = new Font("Yu Gothic UI", 16f, FontStyle.Bold, GraphicsUnit.Pixel);
            var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
            var rect = new RectangleF(0, 1, 32, 32);
            using var dark = new SolidBrush(Color.FromArgb(18, 38, 68));
            foreach (var off in new[] { (-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1) })
                g.DrawString("中", f, dark, new RectangleF(rect.X + off.Item1, rect.Y + off.Item2, rect.Width, rect.Height), sf);
            using var wb = new SolidBrush(Color.White); g.DrawString("中", f, wb, rect, sf);
        }
        return Icon.FromHandle(bmp.GetHicon());
    }
}
