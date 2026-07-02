-- 競馬ブック「能力表」由来のコンピュータファクター取込先(新規)。
-- スピード指数(/cyuou/speed)・レイティング(/cyuou/rating)の過去走履歴、cpu(/cyuou/cpu)の4ファクター寄与+単勝予測。
SET NOCOUNT ON;

-- 1) スピード指数/レイティングの過去走履歴(1馬×過去N走の値)
IF OBJECT_ID('dbo.競馬ブック能力指数','U') IS NULL
CREATE TABLE dbo.競馬ブック能力指数(
    Id        int IDENTITY(1,1) PRIMARY KEY,
    取得日時  datetime2    NOT NULL,
    race_id   nvarchar(12) NOT NULL,   -- 今走(能力表)race_id
    開催日    date         NULL,
    開催場所  nvarchar(10) NULL,
    レース番号 int         NULL,
    馬番      int          NULL,
    umacd     nvarchar(10) NULL,
    馬名      nvarchar(50) NULL,
    種別      nvarchar(8)  NOT NULL,   -- speed / rating
    列位置    int          NULL,       -- 1=左端(古)..N=前走
    過去race_id nvarchar(20) NULL,     -- /seiseki の過去走id(地方含む)
    過去日付  date         NULL,
    過去場    nvarchar(10) NULL,
    過去内容  nvarchar(40) NULL,       -- 例 "ダ重1600m 2着"
    値        decimal(6,1) NULL,
    best      bit          NULL        -- 直近5(7)走の最高値
);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name='IX_能力指数_キー')
    CREATE INDEX IX_能力指数_キー ON dbo.競馬ブック能力指数(race_id,種別,馬番);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name='IX_能力指数_umacd')
    CREATE INDEX IX_能力指数_umacd ON dbo.競馬ブック能力指数(umacd,過去日付);

-- 2) コンピュータ予想(cpu)の per馬 複合: 4ファクター寄与(グラフ幅)+単勝予測
IF OBJECT_ID('dbo.競馬ブックCPU','U') IS NULL
CREATE TABLE dbo.競馬ブックCPU(
    Id        int IDENTITY(1,1) PRIMARY KEY,
    取得日時  datetime2    NOT NULL,
    race_id   nvarchar(12) NOT NULL,
    開催日    date         NULL,
    開催場所  nvarchar(10) NULL,
    レース番号 int         NULL,
    馬番      int          NULL,
    umacd     nvarchar(10) NULL,
    馬名      nvarchar(50) NULL,
    f_speed   decimal(5,1) NULL,   -- スピード指数(走破タイム)寄与
    f_facter  decimal(5,1) NULL,   -- ファクター(調教・実績=リファクター)寄与
    f_rating  decimal(5,1) NULL,   -- レイティング(着順)寄与
    f_book    decimal(5,1) NULL,   -- ブック指数(総合)寄与
    ブック合計 decimal(6,1) NULL,  -- 4寄与の合計(総合指数の目安)
    単勝予測  decimal(7,1) NULL    -- 競馬ブックの予測単勝オッズ
);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name='IX_CPU_キー')
    CREATE INDEX IX_CPU_キー ON dbo.競馬ブックCPU(race_id,馬番);

SELECT '作成完了' s,
 (SELECT COUNT(*) FROM sys.tables WHERE name='競馬ブック能力指数') 能力指数,
 (SELECT COUNT(*) FROM sys.tables WHERE name='競馬ブックCPU') CPU;
