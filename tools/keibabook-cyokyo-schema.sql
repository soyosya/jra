-- 競馬ブック「調教」テーブル(中央競馬/JRA DB)。EFモデル外の raw テーブル(競馬ブック取得.cs が直接INSERT)。
-- 2テーブル: 調教(1頭1行サマリ=追い切り短評+矢印) と 調教明細(調教1本1行=日付/コース/馬場/各Fタイム/脚色/短評)。
-- 着順は 競走結果 と (開催場所,開催日,レース番号,馬番) で結合。※非ログインでは各レース一部(実測1頭)のみ。会員ログイン実装後に全頭へ。

IF OBJECT_ID(N'調教', N'U') IS NULL
BEGIN
    CREATE TABLE 調教 (
        Id          bigint IDENTITY(1,1) NOT NULL,
        開催日       date          NOT NULL,
        開催場所     nvarchar(20)  NOT NULL,
        レース番号   int           NOT NULL,
        raceid       nvarchar(12)  NOT NULL,
        馬番         int           NOT NULL,
        枠番         int           NULL,
        馬名         nvarchar(50)  NULL,
        umacd        nvarchar(20)  NULL,
        追い切り短評 nvarchar(100) NULL,   -- 馬ごとの追い切り短評
        矢印         nvarchar(10)  NULL,   -- 評価矢印(→↑↓ 等)
        取得日時     datetime2     NOT NULL,
        取得元       nvarchar(40)  NULL,
        CONSTRAINT PK_調教 PRIMARY KEY CLUSTERED (Id)
    );
    CREATE UNIQUE NONCLUSTERED INDEX UX_調教_スナップ ON 調教(開催日, 開催場所, レース番号, 馬番, 取得日時);
    CREATE NONCLUSTERED INDEX IX_調教_結合 ON 調教(開催場所, 開催日, レース番号, 馬番);
END

IF OBJECT_ID(N'調教明細', N'U') IS NULL
BEGIN
    CREATE TABLE 調教明細 (
        Id          bigint IDENTITY(1,1) NOT NULL,
        開催日       date          NOT NULL,
        開催場所     nvarchar(20)  NOT NULL,
        レース番号   int           NOT NULL,
        raceid       nvarchar(12)  NOT NULL,
        馬番         int           NOT NULL,
        umacd        nvarchar(20)  NULL,
        行番号       int           NOT NULL,   -- ページ上の調教ラインの順番(0始まり)
        種別         nvarchar(10)  NULL,       -- 追切(oikiri) / 時計(time)
        mark         nvarchar(6)   NULL,       -- ☆ 等
        騎乗者       nvarchar(20)  NULL,
        日付         nvarchar(20)  NULL,       -- 「6/10(水)」「◇」等(原文ママ)
        コース       nvarchar(20)  NULL,
        馬場         nvarchar(10)  NULL,
        タイム1哩    nvarchar(12)  NULL,
        タイム7F     nvarchar(12)  NULL,
        タイム6F     nvarchar(12)  NULL,       -- 6F(坂路)
        タイム5F     nvarchar(12)  NULL,       -- 5F(4F)
        タイム半哩   nvarchar(12)  NULL,       -- 半哩(3F)
        タイム3F     nvarchar(12)  NULL,       -- 3F(2F)
        タイム1F     nvarchar(12)  NULL,       -- 1F(1F)
        回り位置     nvarchar(20)  NULL,
        脚色         nvarchar(30)  NULL,
        短評         nvarchar(60)  NULL,
        原文         nvarchar(400) NULL,       -- ライン全体の原文(フォールバック)
        取得日時     datetime2     NOT NULL,
        取得元       nvarchar(40)  NULL,
        CONSTRAINT PK_調教明細 PRIMARY KEY CLUSTERED (Id)
    );
    CREATE UNIQUE NONCLUSTERED INDEX UX_調教明細_スナップ ON 調教明細(開催日, 開催場所, レース番号, 馬番, 行番号, 取得日時);
    CREATE NONCLUSTERED INDEX IX_調教明細_結合 ON 調教明細(開催場所, 開催日, レース番号, 馬番);
END
