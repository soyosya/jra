SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
SET NOCOUNT ON;
SET LOCK_TIMEOUT 10000;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @suffix sysname = CONVERT(varchar(8), SYSDATETIME(), 112)
        + REPLACE(CONVERT(varchar(8), SYSDATETIME(), 108), ':', '');
    DECLARE @backup sysname;
    DECLARE @maxId int;

    IF OBJECT_ID(N'dbo.レース情報_IdentityMigrationNew', N'U') IS NOT NULL
        THROW 51000, 'レース情報_IdentityMigrationNew already exists.', 1;
    IF OBJECT_ID(N'dbo.競走結果_IdentityMigrationNew', N'U') IS NOT NULL
        THROW 51000, '競走結果_IdentityMigrationNew already exists.', 1;
    IF OBJECT_ID(N'dbo.当日メニュー_IdentityMigrationNew', N'U') IS NOT NULL
        THROW 51000, '当日メニュー_IdentityMigrationNew already exists.', 1;
    IF OBJECT_ID(N'dbo.変更情報_IdentityMigrationNew', N'U') IS NOT NULL
        THROW 51000, '変更情報_IdentityMigrationNew already exists.', 1;
    IF OBJECT_ID(N'dbo.出馬表_IdentityMigrationNew', N'U') IS NOT NULL
        THROW 51000, '出馬表_IdentityMigrationNew already exists.', 1;
    IF OBJECT_ID(N'dbo.リアルタイムオッズ_IdentityMigrationNew', N'U') IS NOT NULL
        THROW 51000, 'リアルタイムオッズ_IdentityMigrationNew already exists.', 1;

    IF OBJECT_ID(N'dbo.レース情報', N'U') IS NOT NULL
       AND EXISTS (SELECT 1 FROM (SELECT Id FROM dbo.レース情報 GROUP BY Id HAVING COUNT_BIG(*) > 1) d)
        THROW 51000, 'レース情報.Id contains duplicate values.', 1;
    IF OBJECT_ID(N'dbo.競走結果', N'U') IS NOT NULL
       AND EXISTS (SELECT 1 FROM (SELECT Id FROM dbo.競走結果 GROUP BY Id HAVING COUNT_BIG(*) > 1) d)
        THROW 51000, '競走結果.Id contains duplicate values.', 1;
    IF OBJECT_ID(N'dbo.当日メニュー', N'U') IS NOT NULL
       AND EXISTS (SELECT 1 FROM (SELECT Id FROM dbo.当日メニュー GROUP BY Id HAVING COUNT_BIG(*) > 1) d)
        THROW 51000, '当日メニュー.Id contains duplicate values.', 1;
    IF OBJECT_ID(N'dbo.変更情報', N'U') IS NOT NULL
       AND EXISTS (SELECT 1 FROM (SELECT Id FROM dbo.変更情報 GROUP BY Id HAVING COUNT_BIG(*) > 1) d)
        THROW 51000, '変更情報.Id contains duplicate values.', 1;
    IF OBJECT_ID(N'dbo.出馬表', N'U') IS NOT NULL
       AND EXISTS (SELECT 1 FROM (SELECT Id FROM dbo.出馬表 GROUP BY Id HAVING COUNT_BIG(*) > 1) d)
        THROW 51000, '出馬表.Id contains duplicate values.', 1;
    IF OBJECT_ID(N'dbo.リアルタイムオッズ', N'U') IS NOT NULL
       AND EXISTS (SELECT 1 FROM (SELECT Id FROM dbo.リアルタイムオッズ GROUP BY Id HAVING COUNT_BIG(*) > 1) d)
        THROW 51000, 'リアルタイムオッズ.Id contains duplicate values.', 1;
    IF OBJECT_ID(N'dbo.開催情報', N'U') IS NOT NULL
       AND EXISTS (SELECT 1 FROM (SELECT 開催日, 開催場所 FROM dbo.開催情報 GROUP BY 開催日, 開催場所 HAVING COUNT_BIG(*) > 1) d)
        THROW 51000, '開催情報 contains duplicate 開催日/開催場所 values.', 1;

    IF OBJECT_ID(N'dbo.レース情報', N'U') IS NULL
       OR COLUMNPROPERTY(OBJECT_ID(N'dbo.レース情報'), N'Id', 'IsIdentity') <> 1
       OR NOT EXISTS (
            SELECT 1
            FROM sys.key_constraints kc
            JOIN sys.index_columns ic ON kc.parent_object_id = ic.object_id AND kc.unique_index_id = ic.index_id
            JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
            WHERE kc.type = 'PK'
              AND kc.parent_object_id = OBJECT_ID(N'dbo.レース情報')
              AND c.name = N'Id')
    BEGIN
        CREATE TABLE dbo.レース情報_IdentityMigrationNew
        (
            Id int IDENTITY(1,1) NOT NULL,
            開催場所 nvarchar(4) NOT NULL,
            開催日 date NOT NULL,
            レース番号 int NOT NULL,
            発走時刻 datetime2 NOT NULL,
            コース種別 nvarchar(1) NOT NULL,
            周回方向 nvarchar(1) NOT NULL,
            距離 int NOT NULL,
            天候 nvarchar(2) NOT NULL,
            馬場 nvarchar(3) NOT NULL,
            条件 nvarchar(128) NOT NULL,
            競走名 nvarchar(128) NOT NULL,
            一着賞金 decimal(10, 0) NOT NULL,
            二着賞金 decimal(10, 0) NOT NULL,
            三着賞金 decimal(10, 0) NOT NULL,
            四着賞金 decimal(10, 0) NOT NULL,
            五着賞金 decimal(10, 0) NOT NULL,
            着順 int NOT NULL,
            枠番 int NOT NULL,
            馬番 int NOT NULL,
            馬名 nvarchar(9) NOT NULL,
            馬齢 int NOT NULL,
            性別 nvarchar(2) NOT NULL,
            毛色 nvarchar(4) NOT NULL,
            騎手 nvarchar(10) NOT NULL,
            騎手所属 nvarchar(4) NOT NULL,
            斤量 real NOT NULL,
            斤量増減 real NOT NULL,
            減量記号 nvarchar(1) NOT NULL,
            馬体重 int NOT NULL,
            馬体重増減 int NOT NULL,
            調教師 nvarchar(10) NOT NULL,
            調教師所属 nvarchar(4) NOT NULL,
            馬主 nvarchar(32) NOT NULL,
            変更情報 nvarchar(64) NOT NULL,
            馬情報URL nvarchar(512) NOT NULL,
            騎手情報URL nvarchar(512) NOT NULL,
            調教師情報URL nvarchar(512) NOT NULL,
            CONSTRAINT PK_レース情報 PRIMARY KEY CLUSTERED (Id)
        );

        IF OBJECT_ID(N'dbo.レース情報', N'U') IS NOT NULL
        BEGIN
            SET IDENTITY_INSERT dbo.レース情報_IdentityMigrationNew ON;
            INSERT INTO dbo.レース情報_IdentityMigrationNew
                (Id, 開催場所, 開催日, レース番号, 発走時刻, コース種別, 周回方向, 距離, 天候, 馬場, 条件, 競走名,
                 一着賞金, 二着賞金, 三着賞金, 四着賞金, 五着賞金, 着順, 枠番, 馬番, 馬名, 馬齢, 性別, 毛色,
                 騎手, 騎手所属, 斤量, 斤量増減, 減量記号, 馬体重, 馬体重増減, 調教師, 調教師所属, 馬主,
                 変更情報, 馬情報URL, 騎手情報URL, 調教師情報URL)
            SELECT Id, 開催場所, 開催日, レース番号, 発走時刻, コース種別, 周回方向, 距離, 天候, 馬場, 条件, 競走名,
                   一着賞金, 二着賞金, 三着賞金, 四着賞金, 五着賞金, 着順, 枠番, 馬番, 馬名, 馬齢, 性別, 毛色,
                   騎手, 騎手所属, 斤量, 斤量増減, 減量記号, 馬体重, 馬体重増減, 調教師, 調教師所属, 馬主,
                   変更情報, 馬情報URL, 騎手情報URL, 調教師情報URL
            FROM dbo.レース情報 WITH (TABLOCKX, HOLDLOCK)
            ORDER BY Id;
            SET IDENTITY_INSERT dbo.レース情報_IdentityMigrationNew OFF;

            SET @backup = N'レース情報_IdentityMigrationBackup_' + @suffix;
            EXEC sp_rename N'dbo.レース情報', @backup;
        END

        EXEC sp_rename N'dbo.レース情報_IdentityMigrationNew', N'レース情報';
        SELECT @maxId = ISNULL(MAX(Id), 0) FROM dbo.レース情報;
        DBCC CHECKIDENT (N'dbo.レース情報', RESEED, @maxId) WITH NO_INFOMSGS;
    END

    IF OBJECT_ID(N'dbo.競走結果', N'U') IS NULL
       OR COLUMNPROPERTY(OBJECT_ID(N'dbo.競走結果'), N'Id', 'IsIdentity') <> 1
       OR NOT EXISTS (
            SELECT 1
            FROM sys.key_constraints kc
            JOIN sys.index_columns ic ON kc.parent_object_id = ic.object_id AND kc.unique_index_id = ic.index_id
            JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
            WHERE kc.type = 'PK'
              AND kc.parent_object_id = OBJECT_ID(N'dbo.競走結果')
              AND c.name = N'Id')
    BEGIN
        CREATE TABLE dbo.競走結果_IdentityMigrationNew
        (
            Id int IDENTITY(1,1) NOT NULL,
            開催場所 nvarchar(4) NOT NULL,
            開催日 date NOT NULL,
            レース番号 int NOT NULL,
            着順 int NOT NULL,
            枠番 int NOT NULL,
            馬番 int NOT NULL,
            馬名 nvarchar(9) NOT NULL,
            走破時計 decimal(4,1) NOT NULL,
            上り3F decimal(4,1) NOT NULL,
            一着馬着差タイム decimal(4,1) NOT NULL,
            先着馬着差タイム decimal(4,1) NOT NULL,
            後着馬着差タイム decimal(4,1) NOT NULL,
            着差 nvarchar(16) NOT NULL,
            一コーナー int NOT NULL,
            二コーナー int NOT NULL,
            三コーナー int NOT NULL,
            四コーナー int NOT NULL,
            CONSTRAINT PK_競走結果 PRIMARY KEY CLUSTERED (Id)
        );

        IF OBJECT_ID(N'dbo.競走結果', N'U') IS NOT NULL
        BEGIN
            SET IDENTITY_INSERT dbo.競走結果_IdentityMigrationNew ON;
            INSERT INTO dbo.競走結果_IdentityMigrationNew
                (Id, 開催場所, 開催日, レース番号, 着順, 枠番, 馬番, 馬名, 走破時計, 上り3F,
                 一着馬着差タイム, 先着馬着差タイム, 後着馬着差タイム, 着差, 一コーナー, 二コーナー, 三コーナー, 四コーナー)
            SELECT Id, 開催場所, 開催日, レース番号, 着順, 枠番, 馬番, 馬名, 走破時計, 上り3F,
                   一着馬着差タイム, 先着馬着差タイム, 後着馬着差タイム, 着差, 一コーナー, 二コーナー, 三コーナー, 四コーナー
            FROM dbo.競走結果 WITH (TABLOCKX, HOLDLOCK)
            ORDER BY Id;
            SET IDENTITY_INSERT dbo.競走結果_IdentityMigrationNew OFF;

            SET @backup = N'競走結果_IdentityMigrationBackup_' + @suffix;
            EXEC sp_rename N'dbo.競走結果', @backup;
        END

        EXEC sp_rename N'dbo.競走結果_IdentityMigrationNew', N'競走結果';
        SELECT @maxId = ISNULL(MAX(Id), 0) FROM dbo.競走結果;
        DBCC CHECKIDENT (N'dbo.競走結果', RESEED, @maxId) WITH NO_INFOMSGS;
    END

    IF OBJECT_ID(N'dbo.当日メニュー', N'U') IS NULL
       OR COLUMNPROPERTY(OBJECT_ID(N'dbo.当日メニュー'), N'Id', 'IsIdentity') <> 1
       OR NOT EXISTS (
            SELECT 1
            FROM sys.key_constraints kc
            JOIN sys.index_columns ic ON kc.parent_object_id = ic.object_id AND kc.unique_index_id = ic.index_id
            JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
            WHERE kc.type = 'PK'
              AND kc.parent_object_id = OBJECT_ID(N'dbo.当日メニュー')
              AND c.name = N'Id')
    BEGIN
        CREATE TABLE dbo.当日メニュー_IdentityMigrationNew
        (
            Id int IDENTITY(1,1) NOT NULL,
            開催場所 nvarchar(4) NOT NULL,
            開催日 date NOT NULL,
            レース番号 int NOT NULL,
            発走時刻 datetime2 NOT NULL,
            変更 nvarchar(16) NOT NULL,
            競走種類 nvarchar(64) NOT NULL,
            競走名 nvarchar(64) NOT NULL,
            周回方向 nvarchar(1) NOT NULL,
            距離 int NOT NULL,
            天候 nvarchar(2) NOT NULL,
            馬場 nvarchar(3) NOT NULL,
            頭数 int NOT NULL,
            出馬表URL nvarchar(512) NOT NULL,
            成績URL nvarchar(512) NOT NULL,
            CONSTRAINT PK_当日メニュー PRIMARY KEY CLUSTERED (Id)
        );

        IF OBJECT_ID(N'dbo.当日メニュー', N'U') IS NOT NULL
        BEGIN
            SET IDENTITY_INSERT dbo.当日メニュー_IdentityMigrationNew ON;
            INSERT INTO dbo.当日メニュー_IdentityMigrationNew
                (Id, 開催場所, 開催日, レース番号, 発走時刻, 変更, 競走種類, 競走名, 周回方向,
                 距離, 天候, 馬場, 頭数, 出馬表URL, 成績URL)
            SELECT Id, 開催場所, 開催日, レース番号, 発走時刻, 変更, 競走種類, 競走名, 周回方向,
                   距離, 天候, 馬場, 頭数, 出馬表URL, 成績URL
            FROM dbo.当日メニュー WITH (TABLOCKX, HOLDLOCK)
            ORDER BY Id;
            SET IDENTITY_INSERT dbo.当日メニュー_IdentityMigrationNew OFF;

            SET @backup = N'当日メニュー_IdentityMigrationBackup_' + @suffix;
            EXEC sp_rename N'dbo.当日メニュー', @backup;
        END

        EXEC sp_rename N'dbo.当日メニュー_IdentityMigrationNew', N'当日メニュー';
        SELECT @maxId = ISNULL(MAX(Id), 0) FROM dbo.当日メニュー;
        DBCC CHECKIDENT (N'dbo.当日メニュー', RESEED, @maxId) WITH NO_INFOMSGS;
    END

    IF OBJECT_ID(N'dbo.変更情報', N'U') IS NULL
       OR COLUMNPROPERTY(OBJECT_ID(N'dbo.変更情報'), N'Id', 'IsIdentity') <> 1
       OR NOT EXISTS (
            SELECT 1
            FROM sys.key_constraints kc
            JOIN sys.index_columns ic ON kc.parent_object_id = ic.object_id AND kc.unique_index_id = ic.index_id
            JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
            WHERE kc.type = 'PK'
              AND kc.parent_object_id = OBJECT_ID(N'dbo.変更情報')
              AND c.name = N'Id')
    BEGIN
        CREATE TABLE dbo.変更情報_IdentityMigrationNew
        (
            Id int IDENTITY(1,1) NOT NULL,
            開催場所 nvarchar(4) NOT NULL,
            開催日 date NOT NULL,
            レース番号 int NOT NULL,
            馬番 int NOT NULL,
            馬名 nvarchar(9) NOT NULL,
            変更区分 nvarchar(16) NOT NULL,
            変更理由 nvarchar(64) NOT NULL,
            変更内容 nvarchar(64) NOT NULL,
            CONSTRAINT PK_変更情報 PRIMARY KEY CLUSTERED (Id)
        );

        IF OBJECT_ID(N'dbo.変更情報', N'U') IS NOT NULL
        BEGIN
            SET IDENTITY_INSERT dbo.変更情報_IdentityMigrationNew ON;
            INSERT INTO dbo.変更情報_IdentityMigrationNew
                (Id, 開催場所, 開催日, レース番号, 馬番, 馬名, 変更区分, 変更理由, 変更内容)
            SELECT Id, 開催場所, 開催日, レース番号, 馬番, 馬名, 変更区分, 変更理由, 変更内容
            FROM dbo.変更情報 WITH (TABLOCKX, HOLDLOCK)
            ORDER BY Id;
            SET IDENTITY_INSERT dbo.変更情報_IdentityMigrationNew OFF;

            SET @backup = N'変更情報_IdentityMigrationBackup_' + @suffix;
            EXEC sp_rename N'dbo.変更情報', @backup;
        END

        EXEC sp_rename N'dbo.変更情報_IdentityMigrationNew', N'変更情報';
        SELECT @maxId = ISNULL(MAX(Id), 0) FROM dbo.変更情報;
        DBCC CHECKIDENT (N'dbo.変更情報', RESEED, @maxId) WITH NO_INFOMSGS;
    END

    IF OBJECT_ID(N'dbo.出馬表', N'U') IS NULL
       OR COLUMNPROPERTY(OBJECT_ID(N'dbo.出馬表'), N'Id', 'IsIdentity') <> 1
       OR NOT EXISTS (
            SELECT 1
            FROM sys.key_constraints kc
            JOIN sys.index_columns ic ON kc.parent_object_id = ic.object_id AND kc.unique_index_id = ic.index_id
            JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
            WHERE kc.type = 'PK'
              AND kc.parent_object_id = OBJECT_ID(N'dbo.出馬表')
              AND c.name = N'Id')
    BEGIN
        CREATE TABLE dbo.出馬表_IdentityMigrationNew
        (
            Id int IDENTITY(1,1) NOT NULL,
            開催場所 nvarchar(4) NOT NULL,
            開催日 date NOT NULL,
            レース番号 int NOT NULL,
            発走時刻 datetime2 NOT NULL,
            馬名 nvarchar(9) NOT NULL,
            前走Id int NOT NULL,
            前走日 date NOT NULL,
            前走上り3F decimal(18,2) NOT NULL,
            前走間隔 nvarchar(30) NULL,
            休み明け判定 nvarchar(2) NULL,
            平均間隔 int NULL,
            標準偏差 int NULL,
            斤量差 real NOT NULL,
            距離延短 nvarchar(2) NOT NULL,
            距離差 nvarchar(30) NOT NULL,
            周回方向変化 nvarchar(2) NOT NULL,
            前走場所 nvarchar(4) NOT NULL,
            コース種別 nvarchar(1) NOT NULL,
            周回方向 nvarchar(1) NOT NULL,
            距離 int NOT NULL,
            天候 nvarchar(2) NOT NULL,
            馬場 nvarchar(3) NOT NULL,
            条件 nvarchar(64) NOT NULL,
            競走名 nvarchar(64) NOT NULL,
            一着賞金 decimal(18,2) NOT NULL,
            二着賞金 decimal(18,2) NOT NULL,
            三着賞金 decimal(18,2) NOT NULL,
            四着賞金 decimal(18,2) NOT NULL,
            五着賞金 decimal(18,2) NOT NULL,
            着順 int NOT NULL,
            枠番 int NOT NULL,
            馬番 int NOT NULL,
            馬齢 int NOT NULL,
            性別 nvarchar(2) NOT NULL,
            毛色 nvarchar(4) NOT NULL,
            騎手 nvarchar(10) NOT NULL,
            騎手所属 nvarchar(4) NOT NULL,
            斤量 real NOT NULL,
            斤量増減 real NOT NULL,
            減量記号 nvarchar(1) NOT NULL,
            馬体重 int NOT NULL,
            馬体重増減 int NOT NULL,
            調教師 nvarchar(10) NOT NULL,
            調教師所属 nvarchar(4) NOT NULL,
            馬主 nvarchar(32) NOT NULL,
            変更情報 nvarchar(64) NOT NULL,
            馬情報URL nvarchar(512) NOT NULL,
            騎手情報URL nvarchar(512) NOT NULL,
            調教師情報URL nvarchar(512) NOT NULL,
            一着馬着差タイム decimal(18,2) NOT NULL,
            先着馬着差タイム decimal(18,2) NOT NULL,
            後着馬着差タイム decimal(18,2) NOT NULL,
            上り3F decimal(18,2) NOT NULL,
            走破時計 decimal(18,2) NOT NULL,
            着差 nvarchar(16) NOT NULL,
            一コーナー int NOT NULL,
            二コーナー int NOT NULL,
            三コーナー int NOT NULL,
            四コーナー int NOT NULL,
            CONSTRAINT PK_出馬表 PRIMARY KEY CLUSTERED (Id)
        );

        IF OBJECT_ID(N'dbo.出馬表', N'U') IS NOT NULL
        BEGIN
            SET IDENTITY_INSERT dbo.出馬表_IdentityMigrationNew ON;
            INSERT INTO dbo.出馬表_IdentityMigrationNew
                (Id, 開催場所, 開催日, レース番号, 発走時刻, 馬名, 前走Id, 前走日, 前走上り3F, 前走間隔,
                 休み明け判定, 平均間隔, 標準偏差, 斤量差, 距離延短, 距離差, 周回方向変化, 前走場所,
                 コース種別, 周回方向, 距離, 天候, 馬場, 条件, 競走名, 一着賞金, 二着賞金, 三着賞金, 四着賞金,
                 五着賞金, 着順, 枠番, 馬番, 馬齢, 性別, 毛色, 騎手, 騎手所属, 斤量, 斤量増減, 減量記号,
                 馬体重, 馬体重増減, 調教師, 調教師所属, 馬主, 変更情報, 馬情報URL, 騎手情報URL, 調教師情報URL,
                 一着馬着差タイム, 先着馬着差タイム, 後着馬着差タイム, 上り3F, 走破時計, 着差,
                 一コーナー, 二コーナー, 三コーナー, 四コーナー)
            SELECT Id, 開催場所, 開催日, レース番号, 発走時刻, 馬名, 前走Id, 前走日, 前走上り3F, 前走間隔,
                   休み明け判定, 平均間隔, 標準偏差, 斤量差, 距離延短, 距離差, 周回方向変化, 前走場所,
                   コース種別, 周回方向, 距離, 天候, 馬場, 条件, 競走名, 一着賞金, 二着賞金, 三着賞金, 四着賞金,
                   五着賞金, 着順, 枠番, 馬番, 馬齢, 性別, 毛色, 騎手, 騎手所属, 斤量, 斤量増減, 減量記号,
                   馬体重, 馬体重増減, 調教師, 調教師所属, 馬主, 変更情報, 馬情報URL, 騎手情報URL, 調教師情報URL,
                   一着馬着差タイム, 先着馬着差タイム, 後着馬着差タイム, 上り3F, 走破時計, 着差,
                   一コーナー, 二コーナー, 三コーナー, 四コーナー
            FROM dbo.出馬表 WITH (TABLOCKX, HOLDLOCK)
            ORDER BY Id;
            SET IDENTITY_INSERT dbo.出馬表_IdentityMigrationNew OFF;

            SET @backup = N'出馬表_IdentityMigrationBackup_' + @suffix;
            EXEC sp_rename N'dbo.出馬表', @backup;
        END

        EXEC sp_rename N'dbo.出馬表_IdentityMigrationNew', N'出馬表';
        SELECT @maxId = ISNULL(MAX(Id), 0) FROM dbo.出馬表;
        DBCC CHECKIDENT (N'dbo.出馬表', RESEED, @maxId) WITH NO_INFOMSGS;
    END

    IF OBJECT_ID(N'dbo.リアルタイムオッズ', N'U') IS NULL
       OR COLUMNPROPERTY(OBJECT_ID(N'dbo.リアルタイムオッズ'), N'Id', 'IsIdentity') <> 1
       OR NOT EXISTS (
            SELECT 1
            FROM sys.key_constraints kc
            JOIN sys.index_columns ic ON kc.parent_object_id = ic.object_id AND kc.unique_index_id = ic.index_id
            JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
            WHERE kc.type = 'PK'
              AND kc.parent_object_id = OBJECT_ID(N'dbo.リアルタイムオッズ')
              AND c.name = N'Id')
    BEGIN
        CREATE TABLE dbo.リアルタイムオッズ_IdentityMigrationNew
        (
            Id int IDENTITY(1,1) NOT NULL,
            開催場所 nvarchar(4) NOT NULL,
            開催日 date NOT NULL,
            レース番号 int NOT NULL,
            馬番 int NOT NULL,
            馬名 nvarchar(9) NOT NULL,
            単勝オッズ float NOT NULL,
            複勝オッズ nvarchar(max) NOT NULL,
            複勝オッズ_MIN float NOT NULL,
            複勝オッズ_MAX float NOT NULL,
            人気 int NOT NULL,
            日時 datetime2 NOT NULL,
            CONSTRAINT PK_リアルタイムオッズ PRIMARY KEY CLUSTERED (Id)
        );

        IF OBJECT_ID(N'dbo.リアルタイムオッズ', N'U') IS NOT NULL
        BEGIN
            SET IDENTITY_INSERT dbo.リアルタイムオッズ_IdentityMigrationNew ON;
            INSERT INTO dbo.リアルタイムオッズ_IdentityMigrationNew
                (Id, 開催場所, 開催日, レース番号, 馬番, 馬名, 単勝オッズ, 複勝オッズ, 複勝オッズ_MIN, 複勝オッズ_MAX, 人気, 日時)
            SELECT Id, 開催場所, 開催日, レース番号, 馬番, 馬名, 単勝オッズ, 複勝オッズ, 複勝オッズ_MIN, 複勝オッズ_MAX, 人気, 日時
            FROM dbo.リアルタイムオッズ WITH (TABLOCKX, HOLDLOCK)
            ORDER BY Id;
            SET IDENTITY_INSERT dbo.リアルタイムオッズ_IdentityMigrationNew OFF;

            SET @backup = N'リアルタイムオッズ_IdentityMigrationBackup_' + @suffix;
            EXEC sp_rename N'dbo.リアルタイムオッズ', @backup;
        END

        EXEC sp_rename N'dbo.リアルタイムオッズ_IdentityMigrationNew', N'リアルタイムオッズ';
        SELECT @maxId = ISNULL(MAX(Id), 0) FROM dbo.リアルタイムオッズ;
        DBCC CHECKIDENT (N'dbo.リアルタイムオッズ', RESEED, @maxId) WITH NO_INFOMSGS;
    END

    IF OBJECT_ID(N'dbo.馬情報', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.馬情報
        (
            Id int IDENTITY(1,1) NOT NULL,
            馬名 nvarchar(9) NOT NULL,
            生年月日 date NOT NULL,
            性別 nvarchar(2) NOT NULL,
            毛色 nvarchar(4) NOT NULL,
            産地 nvarchar(16) NOT NULL,
            調教師 nvarchar(10) NOT NULL,
            所属 nvarchar(6) NOT NULL,
            馬主 nvarchar(32) NOT NULL,
            生産牧場 nvarchar(32) NOT NULL,
            地方収得賞金 int NOT NULL,
            中央収得賞金 int NOT NULL,
            中央付加賞金 int NOT NULL,
            父 nvarchar(18) NOT NULL,
            父父 nvarchar(18) NOT NULL,
            父母 nvarchar(18) NOT NULL,
            母 nvarchar(18) NOT NULL,
            母父 nvarchar(18) NOT NULL,
            母母 nvarchar(18) NOT NULL,
            更新日 date NOT NULL,
            CONSTRAINT PK_馬情報 PRIMARY KEY CLUSTERED (Id)
        );
    END

    IF OBJECT_ID(N'dbo.開催情報', N'U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE parent_object_id = OBJECT_ID(N'dbo.開催情報') AND type = 'PK')
    BEGIN
        ALTER TABLE dbo.開催情報
        ADD CONSTRAINT PK_開催情報 PRIMARY KEY CLUSTERED (開催日, 開催場所);
    END

    IF OBJECT_ID(N'dbo.リアルタイムオッズ', N'U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.リアルタイムオッズ') AND name = N'IX_開催日_開催場所_レース番号_馬名_馬番')
        CREATE INDEX IX_開催日_開催場所_レース番号_馬名_馬番
        ON dbo.リアルタイムオッズ (開催日, 開催場所, レース番号, 馬名, 馬番)
        INCLUDE (日時, 単勝オッズ, 複勝オッズ, 複勝オッズ_MIN, 複勝オッズ_MAX);

    IF OBJECT_ID(N'dbo.レース情報', N'U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.レース情報') AND name = N'IX_開催日_開催場所_レース番号_馬名')
        CREATE INDEX IX_開催日_開催場所_レース番号_馬名
        ON dbo.レース情報 (開催日, 開催場所, レース番号, 馬名);

    IF OBJECT_ID(N'dbo.出馬表', N'U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.出馬表') AND name = N'IX_Id_一着賞金')
        CREATE INDEX IX_Id_一着賞金
        ON dbo.出馬表 (一着賞金);

    IF OBJECT_ID(N'dbo.変更情報', N'U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.変更情報') AND name = N'IX_開催日_開催場所_レース番号')
        CREATE INDEX IX_開催日_開催場所_レース番号
        ON dbo.変更情報 (開催日, 開催場所, レース番号);

    IF OBJECT_ID(N'dbo.変更情報', N'U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.変更情報') AND name = N'IX_開催日_開催場所_レース番号_馬名')
        CREATE INDEX IX_開催日_開催場所_レース番号_馬名
        ON dbo.変更情報 (開催日, 開催場所, レース番号, 馬名);

    IF OBJECT_ID(N'dbo.当日メニュー', N'U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.当日メニュー') AND name = N'IX_開催日_開催場所_レース番号')
        CREATE INDEX IX_開催日_開催場所_レース番号
        ON dbo.当日メニュー (開催日, 開催場所, レース番号);

    IF OBJECT_ID(N'dbo.馬情報', N'U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.馬情報') AND name = N'IX_馬名')
        CREATE UNIQUE INDEX IX_馬名
        ON dbo.馬情報 (馬名);

    IF OBJECT_ID(N'dbo.馬情報', N'U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.馬情報') AND name = N'IX_馬主')
        CREATE INDEX IX_馬主
        ON dbo.馬情報 (馬主);

    IF OBJECT_ID(N'dbo.馬情報', N'U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.馬情報') AND name = N'IX_調教師')
        CREATE INDEX IX_調教師
        ON dbo.馬情報 (調教師);

    IF OBJECT_ID(N'dbo.馬情報', N'U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.馬情報') AND name = N'IX_馬名_更新日')
        CREATE UNIQUE INDEX IX_馬名_更新日
        ON dbo.馬情報 (馬名, 更新日);

    IF OBJECT_ID(N'dbo.馬情報', N'U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.馬情報') AND name = N'IX_馬名_生年月日_父')
        CREATE UNIQUE INDEX IX_馬名_生年月日_父
        ON dbo.馬情報 (馬名, 生年月日, 父);

    COMMIT TRANSACTION;

    SELECT
        t.name AS TableName,
        c.is_identity AS IdIsIdentity,
        CASE WHEN pk.name IS NULL THEN 0 ELSE 1 END AS HasPrimaryKey,
        pk.name AS PrimaryKeyName
    FROM sys.tables t
    LEFT JOIN sys.columns c ON c.object_id = t.object_id AND c.name = N'Id'
    LEFT JOIN sys.key_constraints pk ON pk.parent_object_id = t.object_id AND pk.type = 'PK'
    WHERE t.name IN (N'レース情報', N'競走結果', N'当日メニュー', N'変更情報', N'出馬表', N'リアルタイムオッズ', N'開催情報', N'馬情報')
    ORDER BY t.name;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
