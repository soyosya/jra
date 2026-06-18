SET XACT_ABORT ON;
SET LOCK_TIMEOUT 10000;

BEGIN TRANSACTION;

IF OBJECT_ID(N'[dbo].[払戻金]', N'U') IS NULL
BEGIN
    THROW 50000, N'テーブル dbo.払戻金 が存在しません。', 1;
END;

IF COLUMNPROPERTY(OBJECT_ID(N'[dbo].[払戻金]'), N'Id', 'IsIdentity') = 0
BEGIN
    IF EXISTS (
        SELECT 1
        FROM dbo.払戻金
        GROUP BY Id
        HAVING COUNT(*) > 1
    )
    BEGIN
        THROW 50001, N'払戻金.Id に重複があるため IDENTITY 移行を中止します。', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM dbo.払戻金
        GROUP BY 開催日, 開催場所, レース番号, 馬券, 組番
        HAVING COUNT(*) > 1
    )
    BEGIN
        THROW 50002, N'払戻金の自然キーに重複があるため一意インデックスを作成できません。', 1;
    END;

    DECLARE @backupTable sysname = N'払戻金_IdentityMigrationBackup_' + FORMAT(SYSDATETIME(), N'yyyyMMddHHmmss');
    DECLARE @renameSql nvarchar(max) = N'EXEC sp_rename N''dbo.払戻金'', N''' + @backupTable + N''';';
    EXEC sp_executesql @renameSql;

    CREATE TABLE dbo.払戻金
    (
        Id int IDENTITY(1,1) NOT NULL,
        開催場所 nvarchar(4) NOT NULL,
        開催日 date NOT NULL,
        レース番号 int NOT NULL,
        馬券 nvarchar(3) NOT NULL,
        組番 nvarchar(8) NOT NULL,
        金額 decimal(10, 0) NOT NULL,
        CONSTRAINT PK_払戻金 PRIMARY KEY CLUSTERED (Id)
    );

    DECLARE @copySql nvarchar(max) =
        N'SET IDENTITY_INSERT dbo.払戻金 ON;
          INSERT INTO dbo.払戻金 (Id, 開催場所, 開催日, レース番号, 馬券, 組番, 金額)
          SELECT Id, 開催場所, 開催日, レース番号, 馬券, 組番, 金額
          FROM dbo.' + QUOTENAME(@backupTable) + N'
          ORDER BY Id;
          SET IDENTITY_INSERT dbo.払戻金 OFF;';
    EXEC sp_executesql @copySql;

    CREATE UNIQUE INDEX IX_払戻金_開催日_開催場所_レース番号_馬券_組番
        ON dbo.払戻金 (開催日, 開催場所, レース番号, 馬券, 組番);

    DECLARE @maxId int;
    SELECT @maxId = ISNULL(MAX(Id), 0) FROM dbo.払戻金;
    DBCC CHECKIDENT (N'dbo.払戻金', RESEED, @maxId) WITH NO_INFOMSGS;
END
ELSE
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM sys.key_constraints
        WHERE parent_object_id = OBJECT_ID(N'[dbo].[払戻金]')
          AND [type] = 'PK'
    )
    BEGIN
        ALTER TABLE dbo.払戻金
            ADD CONSTRAINT PK_払戻金 PRIMARY KEY CLUSTERED (Id);
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'[dbo].[払戻金]')
          AND name = N'IX_払戻金_開催日_開催場所_レース番号_馬券_組番'
    )
    BEGIN
        CREATE UNIQUE INDEX IX_払戻金_開催日_開催場所_レース番号_馬券_組番
            ON dbo.払戻金 (開催日, 開催場所, レース番号, 馬券, 組番);
    END;
END;

COMMIT TRANSACTION;

SELECT
    COLUMNPROPERTY(OBJECT_ID(N'[dbo].[払戻金]'), N'Id', 'IsIdentity') AS PayoutIdIsIdentity,
    COUNT(*) AS TotalRows
FROM dbo.払戻金;
