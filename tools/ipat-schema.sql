-- IPAT投票履歴(中央競馬DB)。RakutenVoteの投票履歴に相当。収支(pl)は本表×払戻金で算出。
IF OBJECT_ID(N'IPAT投票履歴', N'U') IS NULL
BEGIN
  CREATE TABLE IPAT投票履歴(
    Id          bigint IDENTITY(1,1) NOT NULL,
    投票日時    datetime2     NOT NULL,
    開催日      date          NOT NULL,
    開催場所    nvarchar(10)  NOT NULL,
    レース番号  int           NOT NULL,
    式別        nvarchar(10)  NOT NULL,   -- 単勝/複勝/馬連/馬単/ワイド/三連複/三連単
    方式        nvarchar(12)  NULL,       -- 通常/流し/ボックス/フォーメーション
    軸馬番      nvarchar(20)  NULL,
    相手馬番    nvarchar(60)  NULL,
    組番        nvarchar(60)  NULL,       -- 確定した買い目(例 5-9-11 / 7)
    点数        int           NOT NULL CONSTRAINT DF_IPAT_点数 DEFAULT(1),
    一点金額    int           NOT NULL CONSTRAINT DF_IPAT_一点 DEFAULT(0),
    投票金額    int           NOT NULL CONSTRAINT DF_IPAT_金額 DEFAULT(0),
    モード      nvarchar(12)  NULL,       -- DryRun/ConfirmStop/Auto
    結果        nvarchar(16)  NULL,       -- 計画/投票完了/見送り/締切/失敗/予算超過見送り
    払戻金額    int           NULL,       -- 後で結果照合してUPDATE(任意)
    確定済      bit           NOT NULL CONSTRAINT DF_IPAT_確定 DEFAULT(0),
    取得元      nvarchar(20)  NULL,
    CONSTRAINT PK_IPAT投票履歴 PRIMARY KEY CLUSTERED (Id)
  );
  CREATE INDEX IX_IPAT_レース ON IPAT投票履歴(開催日,開催場所,レース番号);
  PRINT 'IPAT投票履歴 作成完了';
END ELSE PRINT 'IPAT投票履歴 既存';
