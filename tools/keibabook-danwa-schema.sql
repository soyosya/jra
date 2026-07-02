-- 競馬ブック「厩舎の話」テーブル(中央競馬/JRA DB)。EFモデル外の raw テーブル(競馬ブック取得.cs が直接INSERT)。
-- 1レース1頭分の厩舎コメント(印・調教師・本文)をスナップショット保存。着順は 競走結果 と (開催場所,開催日,レース番号,馬番) で結合。
-- ※非ログインでは各レース一部の頭数のみ取得可。会員ログイン実装後に全頭取得へ拡張予定。
IF OBJECT_ID(N'厩舎の話', N'U') IS NULL
BEGIN
    CREATE TABLE 厩舎の話 (
        Id        bigint IDENTITY(1,1) NOT NULL,
        開催日     date          NOT NULL,
        開催場所   nvarchar(20)  NOT NULL,   -- 場名(札幌〜小倉)
        レース番号 int           NOT NULL,
        raceid     nvarchar(12)  NOT NULL,   -- 競馬ブックrace_id(年4+回2+場2+日2+R2)
        馬番       int           NOT NULL,
        枠番       int           NULL,
        馬名       nvarchar(50)  NULL,
        umacd      nvarchar(20)  NULL,       -- 競馬ブック馬コード(/db/uma/xxxxxxx)
        性齢       nvarchar(10)  NULL,
        騎手       nvarchar(20)  NULL,
        印         nvarchar(4)   NULL,       -- コメント先頭の印(◎○▲△注消など)
        調教師     nvarchar(20)  NULL,       -- 【○○師】から抽出
        コメント   nvarchar(max) NULL,       -- 厩舎の話 本文(印・馬名・【師】除去後)
        コメント原文 nvarchar(max) NULL,     -- セル全体の原文
        取得日時   datetime2     NOT NULL,
        取得元     nvarchar(40)  NULL,
        CONSTRAINT PK_厩舎の話 PRIMARY KEY CLUSTERED (Id)
    );
    -- 同一(レース×馬×取得時刻)の重複挿入を防ぐ。
    CREATE UNIQUE NONCLUSTERED INDEX UX_厩舎の話_スナップ
        ON 厩舎の話(開催日, 開催場所, レース番号, 馬番, 取得日時);
    -- 競走結果との結合用。
    CREATE NONCLUSTERED INDEX IX_厩舎の話_結合
        ON 厩舎の話(開催場所, 開催日, レース番号, 馬番);
END
