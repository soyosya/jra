// 役割: 投票した/しなかったに関わらず、推奨された買い目(軸・相手・点数・金額・結果)を
//       DBテーブル dbo.投票履歴 に1レース1行で記録します。後で 競走結果/払戻金 と結合して
//       的中・払戻・回収率を精算できます(tools\vote-settle.ps1 / vote-report.ps1)。
// 接続: appsettings.json(RakutenVote 出力に共通からコピー済み)の DefaultConnection。
// 方針: ベストエフォート。DB障害時もログのみで投票処理は止めない(例外を投げない)。
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using CommonLogger = 中央競馬.共通.Libraly.Logger;

namespace 中央競馬.RakutenVote
{
    public sealed class VoteHistoryStore
    {
        private readonly string? _conn;
        private bool _tableReady;

        public VoteHistoryStore()
        {
            try
            {
                var cfg = new ConfigurationBuilder()
                    .SetBasePath(AppContext.BaseDirectory)
                    .AddJsonFile("appsettings.json", optional: true, reloadOnChange: false)
                    .Build();
                _conn = cfg.GetConnectionString("DefaultConnection");
            }
            catch (Exception ex) { CommonLogger.LogError("投票履歴: 接続文字列の取得に失敗", ex); _conn = null; }
        }

        public bool Enabled => !string.IsNullOrWhiteSpace(_conn);

        /// <summary>テーブルが無ければ作成(冪等)。失敗しても投票は続行。</summary>
        private bool EnsureTable(SqlConnection cn)
        {
            if (_tableReady) return true;
            const string ddl = @"
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'投票履歴')
CREATE TABLE dbo.投票履歴 (
  Id INT IDENTITY(1,1) CONSTRAINT PK_投票履歴 PRIMARY KEY,
  投票日時 DATETIME2 NOT NULL,
  開催日 DATE NOT NULL,
  場名 NVARCHAR(20) NOT NULL,
  レース番号 INT NOT NULL,
  式別 NVARCHAR(10) NOT NULL,
  軸馬番 INT NOT NULL,
  相手馬番 NVARCHAR(50) NOT NULL,
  点数 INT NOT NULL,
  一点金額 INT NOT NULL,
  投票金額 INT NOT NULL,
  モード NVARCHAR(20) NOT NULL,
  結果 NVARCHAR(20) NOT NULL,
  確定済 BIT NOT NULL CONSTRAINT DF_投票履歴_確定済 DEFAULT(0),
  的中 BIT NULL,
  払戻金 INT NULL,
  確定日時 DATETIME2 NULL
);";
            using var cmd = new SqlCommand(ddl, cn);
            cmd.ExecuteNonQuery();
            _tableReady = true;
            return true;
        }

        /// <summary>1レース分の買い目+結果を記録。result は「計画/投票完了/見送り/失敗/予算超過見送り」等。</summary>
        public void Save(BetTicket b, RakutenOptions opt, string result, int amountYen)
        {
            if (!Enabled) return;
            try
            {
                int points = opt.IsSanrenpuku ? b.PointCountFuku : b.PointCount;
                string betType = opt.IsSanrenpuku ? "三連複" : "三連単";
                string opp = string.Join(",", b.Partners);
                var date = DateTime.TryParse(b.Date, out var d) ? d.Date : DateTime.Today;

                using var cn = new SqlConnection(_conn);
                cn.Open();
                if (!EnsureTable(cn)) return;
                const string sql = @"
INSERT INTO dbo.投票履歴
  (投票日時,開催日,場名,レース番号,式別,軸馬番,相手馬番,点数,一点金額,投票金額,モード,結果,確定済)
VALUES
  (@dt,@date,@ven,@race,@type,@axis,@opp,@pts,@unit,@amt,@mode,@res,0);";
                using var cmd = new SqlCommand(sql, cn);
                cmd.Parameters.AddWithValue("@dt", DateTime.Now);
                cmd.Parameters.AddWithValue("@date", date);
                cmd.Parameters.AddWithValue("@ven", b.Venue ?? "");
                cmd.Parameters.AddWithValue("@race", b.Race);
                cmd.Parameters.AddWithValue("@type", betType);
                cmd.Parameters.AddWithValue("@axis", b.AxisUma);
                cmd.Parameters.AddWithValue("@opp", opp);
                cmd.Parameters.AddWithValue("@pts", points);
                cmd.Parameters.AddWithValue("@unit", opt.StakePerPointYen);
                cmd.Parameters.AddWithValue("@amt", amountYen);
                cmd.Parameters.AddWithValue("@mode", opt.ResolvedMode.ToString());
                cmd.Parameters.AddWithValue("@res", result);
                cmd.ExecuteNonQuery();
                CommonLogger.Log($"  [履歴保存] {b.Venue}{b.Race}R {betType} 軸{b.AxisUma} 相手[{opp}] {result} {amountYen:N0}円", 2);
            }
            catch (Exception ex)
            {
                // 投票処理を止めないため、記録失敗はログのみ。
                CommonLogger.LogError($"投票履歴の保存に失敗 {b.Venue}{b.Race}R", ex);
            }
        }
    }
}
