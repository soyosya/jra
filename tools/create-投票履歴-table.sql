-- dbo.投票履歴: 推奨された買い目を投票有無に関わらず1レース1行で記録する。
-- 通常は RakutenVote(VoteHistoryStore)が初回実行時に自動作成するため、手動実行は不要。
-- 参照/再作成用に定義を残す。精算は tools\vote-settle.ps1、集計は tools\vote-report.ps1。
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'投票履歴')
CREATE TABLE dbo.投票履歴 (
  Id        INT IDENTITY(1,1) CONSTRAINT PK_投票履歴 PRIMARY KEY,
  投票日時   DATETIME2     NOT NULL,                 -- 実行時刻
  開催日     DATE          NOT NULL,
  場名       NVARCHAR(20)  NOT NULL,
  レース番号 INT           NOT NULL,
  式別       NVARCHAR(10)  NOT NULL,                 -- 三連複 / 三連単
  軸馬番     INT           NOT NULL,
  相手馬番   NVARCHAR(50)  NOT NULL,                 -- "6,2,1"
  点数       INT           NOT NULL,
  一点金額   INT           NOT NULL,
  投票金額   INT           NOT NULL,
  モード     NVARCHAR(20)  NOT NULL,                 -- DryRun / ConfirmStop / Auto
  結果       NVARCHAR(20)  NOT NULL,                 -- 計画 / 投票完了 / 見送り / 失敗 / 予算超過見送り
  確定済     BIT           NOT NULL CONSTRAINT DF_投票履歴_確定済 DEFAULT(0),
  的中       BIT           NULL,                     -- 精算で更新
  払戻金     INT           NULL,                     -- 精算で更新(円)
  確定日時   DATETIME2     NULL
);
