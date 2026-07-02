using System.Text;
using System.Text.Json;
using Microsoft.Data.SqlClient;

namespace 中央競馬.IpatVote;

/// <summary>ログ(コンソール+ファイル)。</summary>
public static class Log
{
    static readonly string LogPath = Path.Combine(AppContext.BaseDirectory, "ipatvote.log");
    public static void Line(string m)
    {
        var s = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss}  {m}";
        Console.WriteLine(s);
        try { File.AppendAllText(LogPath, s + Environment.NewLine, Encoding.UTF8); } catch { }
    }
}

/// <summary>認証情報。環境変数 or secrets.local.json。実金のため平文埋込はしない。</summary>
public static class Secrets
{
    static readonly Lazy<JsonElement?> _json = new(() =>
    {
        try
        {
            // IpatVote/bin/.. から見て プロジェクト上位の secrets.local.json を探索
            foreach (var rel in new[] { @"..\..\..\..\secrets.local.json", @"..\secrets.local.json", "secrets.local.json" })
            {
                var p = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, rel));
                if (File.Exists(p)) return JsonDocument.Parse(File.ReadAllText(p)).RootElement;
            }
        }
        catch { }
        return null;
    });
    static string? Get(string env, string jsonKey)
    {
        var v = Environment.GetEnvironmentVariable(env);
        if (!string.IsNullOrWhiteSpace(v)) return v;
        if (_json.Value is JsonElement e && e.TryGetProperty(jsonKey, out var pv) && pv.ValueKind == JsonValueKind.String) return pv.GetString();
        return null;
    }
    public static string? InetId => Get("IPAT_INETID", "IpatInetId");
    public static string? Subscriber => Get("IPAT_SUBSCRIBER", "IpatSubscriber"); // 加入者番号
    public static string? Pin => Get("IPAT_PIN", "IpatPin");                        // 暗証番号
    public static string? Pars => Get("IPAT_PARS", "IpatPars");                     // P-ARS番号
}

/// <summary>DB接続(共通\appsettings.json の DefaultConnection)。</summary>
public static class Db
{
    public static string ConnStr()
    {
        var p = Path.Combine(AppContext.BaseDirectory, "appsettings.json");
        using var doc = JsonDocument.Parse(File.ReadAllText(p));
        return doc.RootElement.GetProperty("ConnectionStrings").GetProperty("DefaultConnection").GetString()!;
    }
}

/// <summary>買い目CSV読込。ヘッダ: date,venue,race,bettype,method,axis,partners(|区切り),stake,kumiban(任意・順不同許容)。</summary>
public static class BetsLoader
{
    public static List<BetTicket> Load(string path, int partnerCount)
    {
        var list = new List<BetTicket>();
        if (!File.Exists(path)) { Log.Line($"買い目CSVが見つかりません: {path}"); return list; }
        var lines = File.ReadAllLines(path, Encoding.UTF8);
        if (lines.Length == 0) return list;
        var head = lines[0].Split(',').Select(h => h.Trim().ToLowerInvariant()).ToArray();
        int Ix(params string[] names) { foreach (var n in names) { var i = Array.IndexOf(head, n); if (i >= 0) return i; } return -1; }
        int iD = Ix("date", "開催日"), iV = Ix("venue", "開催場所", "場"), iR = Ix("race", "レース番号", "r"),
            iB = Ix("bettype", "式別"), iM = Ix("method", "方式"), iA = Ix("axis", "軸", "軸馬番"),
            iP = Ix("partners", "相手", "相手馬番"), iS = Ix("stake", "一点金額", "stakeyen"), iK = Ix("kumiban", "組番"),
            iMul = Ix("multi", "マルチ"), iF1 = Ix("f1", "1着", "一着"), iF2 = Ix("f2", "2着", "二着"), iF3 = Ix("f3", "3着", "三着");
        static List<string> Toks(string s) => string.IsNullOrWhiteSpace(s) ? new List<string>()
            : s.Split('|', '-', ' ').Where(x => x.Trim().Length > 0).Select(x => x.Trim()).ToList();
        for (int r = 1; r < lines.Length; r++)
        {
            var c = lines[r].Split(',');
            string Cell(int i) => (i >= 0 && i < c.Length) ? c[i].Trim() : "";
            if (string.IsNullOrWhiteSpace(Cell(iV)) && string.IsNullOrWhiteSpace(Cell(iK))) continue;
            var t = new BetTicket
            {
                Date = Cell(iD), Venue = Cell(iV),
                Race = int.TryParse(Cell(iR), out var rr) ? rr : 0,
                BetType = Cell(iB), Method = Cell(iM), AxisUma = Cell(iA), Axes = Toks(Cell(iA)),
                StakeYen = int.TryParse(Cell(iS), out var sy) ? sy : 0,
                Kumiban = Cell(iK),
                F1 = Toks(Cell(iF1)), F2 = Toks(Cell(iF2)), F3 = Toks(Cell(iF3))
            };
            var mc = Cell(iMul).ToLowerInvariant();
            t.Multi = mc is "1" or "true" or "yes" or "○" or "マルチ" || (t.Method?.Contains("マルチ") ?? false);
            var pstr = Cell(iP);
            if (!string.IsNullOrWhiteSpace(pstr))
                t.Partners = pstr.Split('|', '-', ' ').Where(x => x.Trim().Length > 0).Select(x => x.Trim()).Take(partnerCount > 0 ? partnerCount : 99).ToList();
            list.Add(t);
        }
        return list;
    }
}

/// <summary>投票履歴のDB保存(IPAT投票履歴)。</summary>
public sealed class VoteHistory
{
    readonly string _cs;
    public VoteHistory() { try { _cs = Db.ConnStr(); } catch { _cs = ""; } }
    public void Save(BetTicket b, IpatOptions opt, string result, int spent, int pts, string mode)
    {
        if (string.IsNullOrEmpty(_cs)) return;
        try
        {
            using var conn = new SqlConnection(_cs); conn.Open();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = @"INSERT INTO IPAT投票履歴(投票日時,開催日,開催場所,レース番号,式別,方式,軸馬番,相手馬番,組番,点数,一点金額,投票金額,モード,結果,取得元)
VALUES(@now,@d,@v,@r,@bt,@m,@ax,@pt,@kb,@pts,@unit,@amt,@mode,@res,@src)";
            void P(string k, object? v) => cmd.Parameters.AddWithValue(k, v ?? DBNull.Value);
            P("@now", DateTime.Now);
            P("@d", string.IsNullOrWhiteSpace(b.Date) ? (object)DateTime.Today : DateTime.Parse(b.Date));
            P("@v", b.Venue); P("@r", b.Race); P("@bt", string.IsNullOrWhiteSpace(b.BetType) ? opt.BetType : b.BetType);
            P("@m", string.IsNullOrWhiteSpace(b.Method) ? opt.Method : b.Method);
            P("@ax", b.AxisUma); P("@pt", string.Join(",", b.Partners)); P("@kb", b.Kumiban);
            P("@pts", pts); P("@unit", opt.StakePerPointYen); P("@amt", spent); P("@mode", mode); P("@res", result);
            P("@src", string.IsNullOrEmpty(opt.ModeLabel) ? "IpatVote" : opt.ModeLabel);   // C1: 取得元(手動/IpatVote)
            cmd.ExecuteNonQuery();
        }
        catch (Exception ex) { Log.Line($"投票履歴の保存に失敗: {ex.Message}"); }
    }
}

/// <summary>現時点の収支(pl)。IPAT投票履歴 × 払戻金(的中照合)で集計。読み取り専用・実金操作なし。</summary>
public static class Pnl
{
    public static void Report(string from, string to)
    {
        var cs = Db.ConnStr();
        using var conn = new SqlConnection(cs); conn.Open();
        // 投票(投票完了のみ)に対し、確定済の払戻金額(列)を使う。未確定は払戻NULL=0扱い。
        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
SELECT COUNT(*) 件,
  ISNULL(SUM(投票金額),0) 投資,
  ISNULL(SUM(ISNULL(払戻金額,0)),0) 払戻,
  SUM(CASE WHEN ISNULL(払戻金額,0)>0 THEN 1 ELSE 0 END) 的中
FROM IPAT投票履歴
WHERE 結果=N'投票完了' AND 開催日 BETWEEN @f AND @t";
        cmd.Parameters.AddWithValue("@f", DateTime.Parse(from));
        cmd.Parameters.AddWithValue("@t", DateTime.Parse(to));
        using var r = cmd.ExecuteReader();
        if (r.Read())
        {
            int n = r.GetInt32(0); long toushi = Convert.ToInt64(r.GetValue(1)); long harai = Convert.ToInt64(r.GetValue(2)); int hit = r.IsDBNull(3) ? 0 : Convert.ToInt32(r.GetValue(3));
            long pl = harai - toushi;
            double roi = toushi > 0 ? 100.0 * harai / toushi : 0;
            Console.WriteLine($"=== 収支 {from}〜{to} (IPAT投票履歴・投票完了分) ===");
            Console.WriteLine($"  投票 {n}件 / 的中 {hit}件 ({(n > 0 ? 100.0 * hit / n : 0):N1}%)");
            Console.WriteLine($"  投資 {toushi:N0}円 / 払戻 {harai:N0}円 / 収支 {pl:+#,0;-#,0;0}円 / 回収率 {roi:N1}%");
            Console.WriteLine("  ※払戻金額は結果照合でUPDATE済の分のみ。未確定レースは0計上。");
        }
    }
}
