SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
SET NOCOUNT ON;
SET LOCK_TIMEOUT 10000;

DECLARE @MigrationSuffix nvarchar(14) = FORMAT(SYSDATETIME(), 'yyyyMMddHHmmss');

DECLARE @Targets TABLE
(
    SchemaName sysname NOT NULL,
    TableName sysname NOT NULL
);

INSERT INTO @Targets (SchemaName, TableName)
VALUES
    (N'dbo', N'レース情報'),
    (N'dbo', N'競走結果'),
    (N'dbo', N'当日メニュー'),
    (N'dbo', N'変更情報'),
    (N'dbo', N'リアルタイムオッズ'),
    (N'dbo', N'出馬表');

DECLARE
    @SchemaName sysname,
    @TableName sysname,
    @ObjectId int,
    @FullName nvarchar(517),
    @BackupTableName sysname,
    @BackupFullName nvarchar(517),
    @ColumnDefinitions nvarchar(max),
    @ColumnList nvarchar(max),
    @Sql nvarchar(max);

DECLARE target_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT SchemaName, TableName
FROM @Targets;

OPEN target_cursor;
FETCH NEXT FROM target_cursor INTO @SchemaName, @TableName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @FullName = QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName);
    SET @ObjectId = OBJECT_ID(@FullName, N'U');

    IF @ObjectId IS NOT NULL
       AND COLUMNPROPERTY(@ObjectId, N'Id', 'IsIdentity') = 0
    BEGIN
        SET @Sql = N'
            IF EXISTS (
                SELECT 1
                FROM ' + @FullName + N'
                GROUP BY Id
                HAVING COUNT_BIG(*) > 1
            )
            BEGIN
                THROW 51000, N''' + @TableName + N'.Id に重複があるため IDENTITY 化できません。'', 1;
            END;';
        EXEC sp_executesql @Sql;

        SET @BackupTableName = @TableName + N'_IdentityMigrationBackup_' + @MigrationSuffix;
        WHILE OBJECT_ID(QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@BackupTableName), N'U') IS NOT NULL
        BEGIN
            SET @BackupTableName = @TableName + N'_IdentityMigrationBackup_' + @MigrationSuffix + N'_' + CONVERT(nvarchar(8), ABS(CHECKSUM(NEWID())));
        END;
        SET @BackupFullName = QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@BackupTableName);

        SELECT @ColumnDefinitions = STUFF((
            SELECT N',' + CHAR(13) + CHAR(10) + N'    ' +
                   QUOTENAME(c.name) + N' ' +
                   CASE
                       WHEN c.name = N'Id' THEN N'int IDENTITY(1,1)'
                       WHEN ty.name IN (N'nvarchar', N'nchar') THEN ty.name + N'(' + CASE WHEN c.max_length = -1 THEN N'max' ELSE CONVERT(nvarchar(10), c.max_length / 2) END + N')'
                       WHEN ty.name IN (N'varchar', N'char', N'varbinary', N'binary') THEN ty.name + N'(' + CASE WHEN c.max_length = -1 THEN N'max' ELSE CONVERT(nvarchar(10), c.max_length) END + N')'
                       WHEN ty.name IN (N'decimal', N'numeric') THEN ty.name + N'(' + CONVERT(nvarchar(10), c.precision) + N',' + CONVERT(nvarchar(10), c.scale) + N')'
                       WHEN ty.name IN (N'datetime2', N'datetimeoffset', N'time') THEN ty.name + N'(' + CONVERT(nvarchar(10), c.scale) + N')'
                       ELSE ty.name
                   END +
                   CASE
                       WHEN ty.name IN (N'nvarchar', N'nchar', N'varchar', N'char') AND c.collation_name IS NOT NULL THEN N' COLLATE ' + c.collation_name
                       ELSE N''
                   END +
                   CASE WHEN c.name = N'Id' OR c.is_nullable = 0 THEN N' NOT NULL' ELSE N' NULL' END
            FROM sys.columns c
            JOIN sys.types ty ON ty.user_type_id = c.user_type_id
            WHERE c.object_id = @ObjectId
            ORDER BY c.column_id
            FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)'), 1, 1, N'');

        SELECT @ColumnList = STUFF((
            SELECT N',' + QUOTENAME(c.name)
            FROM sys.columns c
            WHERE c.object_id = @ObjectId
            ORDER BY c.column_id
            FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)'), 1, 1, N'');

        BEGIN TRANSACTION;

        EXEC sys.sp_rename @objname = @FullName, @newname = @BackupTableName, @objtype = N'OBJECT';

        SET @Sql = N'
            CREATE TABLE ' + @FullName + N'
            (' + CHAR(13) + CHAR(10) +
                @ColumnDefinitions + N',' + CHAR(13) + CHAR(10) +
                N'    CONSTRAINT ' + QUOTENAME(N'PK_' + @TableName) + N' PRIMARY KEY CLUSTERED ([Id])' + CHAR(13) + CHAR(10) +
            N');';
        EXEC sp_executesql @Sql;

        SET @Sql = N'
            SET IDENTITY_INSERT ' + @FullName + N' ON;
            INSERT INTO ' + @FullName + N' (' + @ColumnList + N')
            SELECT ' + @ColumnList + N'
            FROM ' + @BackupFullName + N';
            SET IDENTITY_INSERT ' + @FullName + N' OFF;

            DECLARE @MaxId int;
            SELECT @MaxId = ISNULL(MAX(Id), 0) FROM ' + @FullName + N';
            DBCC CHECKIDENT (''' + @FullName + N''', RESEED, @MaxId) WITH NO_INFOMSGS;';
        EXEC sp_executesql @Sql;

        COMMIT TRANSACTION;
    END;

    FETCH NEXT FROM target_cursor INTO @SchemaName, @TableName;
END;

CLOSE target_cursor;
DEALLOCATE target_cursor;

IF OBJECT_ID(N'dbo.開催情報', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE parent_object_id = OBJECT_ID(N'dbo.開催情報') AND type = N'PK')
BEGIN
    IF EXISTS (
        SELECT 1
        FROM dbo.開催情報
        GROUP BY 開催日, 開催場所
        HAVING COUNT_BIG(*) > 1
    )
    BEGIN
        THROW 51001, N'開催情報 の 開催日,開催場所 に重複があるため主キーを追加できません。', 1;
    END;

    ALTER TABLE dbo.開催情報
        ADD CONSTRAINT PK_開催情報 PRIMARY KEY CLUSTERED (開催日, 開催場所);
END;

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
END;

IF OBJECT_ID(N'dbo.リアルタイムオッズ', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.リアルタイムオッズ') AND name = N'IX_開催日_開催場所_レース番号_馬名_馬番')
BEGIN
    CREATE INDEX IX_開催日_開催場所_レース番号_馬名_馬番
        ON dbo.リアルタイムオッズ (開催日, 開催場所, レース番号, 馬名, 馬番)
        INCLUDE (日時, 単勝オッズ, 複勝オッズ, 複勝オッズ_MIN, 複勝オッズ_MAX);
END;

IF OBJECT_ID(N'dbo.レース情報', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.レース情報') AND name = N'IX_開催日_開催場所_レース番号_馬名')
BEGIN
    CREATE INDEX IX_開催日_開催場所_レース番号_馬名
        ON dbo.レース情報 (開催日, 開催場所, レース番号, 馬名);
END;

IF OBJECT_ID(N'dbo.出馬表', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.出馬表') AND name = N'IX_Id_一着賞金')
BEGIN
    CREATE INDEX IX_Id_一着賞金
        ON dbo.出馬表 (一着賞金);
END;

IF OBJECT_ID(N'dbo.変更情報', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.変更情報') AND name = N'IX_開催日_開催場所_レース番号_馬名')
BEGIN
    CREATE INDEX IX_開催日_開催場所_レース番号_馬名
        ON dbo.変更情報 (開催日, 開催場所, レース番号, 馬名);
END;

IF OBJECT_ID(N'dbo.変更情報', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.変更情報') AND name = N'IX_開催日_開催場所_レース番号')
BEGIN
    CREATE INDEX IX_開催日_開催場所_レース番号
        ON dbo.変更情報 (開催日, 開催場所, レース番号);
END;

IF OBJECT_ID(N'dbo.当日メニュー', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.当日メニュー') AND name = N'IX_開催日_開催場所_レース番号')
BEGIN
    CREATE INDEX IX_開催日_開催場所_レース番号
        ON dbo.当日メニュー (開催日, 開催場所, レース番号);
END;

IF OBJECT_ID(N'dbo.払戻金', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.払戻金') AND name = N'IX_払戻金_開催日_開催場所_レース番号_馬券_組番')
BEGIN
    CREATE UNIQUE INDEX IX_払戻金_開催日_開催場所_レース番号_馬券_組番
        ON dbo.払戻金 (開催日, 開催場所, レース番号, 馬券, 組番);
END;

IF OBJECT_ID(N'dbo.馬情報', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.馬情報') AND name = N'IX_馬名')
BEGIN
    CREATE UNIQUE INDEX IX_馬名 ON dbo.馬情報 (馬名);
END;

IF OBJECT_ID(N'dbo.馬情報', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.馬情報') AND name = N'IX_馬主')
BEGIN
    CREATE INDEX IX_馬主 ON dbo.馬情報 (馬主);
END;

IF OBJECT_ID(N'dbo.馬情報', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.馬情報') AND name = N'IX_調教師')
BEGIN
    CREATE INDEX IX_調教師 ON dbo.馬情報 (調教師);
END;

IF OBJECT_ID(N'dbo.馬情報', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.馬情報') AND name = N'IX_馬名_更新日')
BEGIN
    CREATE UNIQUE INDEX IX_馬名_更新日 ON dbo.馬情報 (馬名, 更新日);
END;

IF OBJECT_ID(N'dbo.馬情報', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.馬情報') AND name = N'IX_馬名_生年月日_父')
BEGIN
    CREATE UNIQUE INDEX IX_馬名_生年月日_父 ON dbo.馬情報 (馬名, 生年月日, 父);
END;

SELECT
    t.name AS TableName,
    c.is_identity AS IdIsIdentity,
    CASE WHEN pk.column_id IS NULL THEN 0 ELSE 1 END AS IdIsPrimaryKey
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id AND c.name = N'Id'
OUTER APPLY (
    SELECT TOP (1) ic.column_id
    FROM sys.key_constraints kc
    JOIN sys.index_columns ic ON ic.object_id = kc.parent_object_id AND ic.index_id = kc.unique_index_id
    JOIN sys.columns pc ON pc.object_id = ic.object_id AND pc.column_id = ic.column_id
    WHERE kc.parent_object_id = t.object_id
      AND kc.type = N'PK'
      AND pc.name = N'Id'
) pk
WHERE t.name IN (N'レース情報', N'競走結果', N'当日メニュー', N'変更情報', N'リアルタイムオッズ', N'出馬表', N'払戻金', N'馬情報')
ORDER BY t.name;
