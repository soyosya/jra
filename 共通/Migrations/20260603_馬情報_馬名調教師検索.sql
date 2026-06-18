SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.馬情報', N'U') IS NOT NULL
BEGIN
    IF EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.馬情報')
          AND name = N'IX_馬名'
    )
    BEGIN
        DROP INDEX IX_馬名 ON dbo.馬情報;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.馬情報')
          AND name = N'IX_馬名_調教師'
    )
    BEGIN
        CREATE INDEX IX_馬名_調教師
            ON dbo.馬情報 (馬名, 調教師);
    END;

    IF EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.馬情報')
          AND name = N'IX_馬名_更新日'
          AND is_unique = 1
    )
    BEGIN
        DROP INDEX IX_馬名_更新日 ON dbo.馬情報;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.馬情報')
          AND name = N'IX_馬名_更新日'
    )
    BEGIN
        CREATE INDEX IX_馬名_更新日
            ON dbo.馬情報 (馬名, 更新日);
    END;
END;

SELECT
    i.name AS IndexName,
    i.is_unique AS IsUnique,
    STUFF((
        SELECT N',' + c.name
        FROM sys.index_columns ic
        JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 0
        ORDER BY ic.key_ordinal
        FOR XML PATH(''), TYPE
    ).value('.', 'nvarchar(max)'), 1, 1, '') AS Columns
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID(N'dbo.馬情報')
  AND i.name IN (N'IX_馬名', N'IX_馬名_調教師', N'IX_馬名_更新日', N'IX_馬名_生年月日_父')
ORDER BY i.name;
