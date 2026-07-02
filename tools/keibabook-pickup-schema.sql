-- 競馬ブック「推奨・ピックアップ」系ページの取り込み先テーブル(新規)。
-- 開催毎に更新される。取得日時スナップショットで蓄積(同レース複数回取得は最新を採用)。
SET NOCOUNT ON;

-- 1) 横断メンバーシップ: 各カテゴリ(自己ベスト/厩舎の話◎/矢印上向き/AI指数S/コンピベスト5)に
--    どの馬が挙がったかを1行で表す。着順との結合で「カテゴリの的中力」を検証できる。
IF OBJECT_ID('dbo.ピックアップ','U') IS NULL
CREATE TABLE dbo.ピックアップ(
    Id        int IDENTITY(1,1) PRIMARY KEY,
    取得日時  datetime2    NOT NULL,
    開催日    date         NOT NULL,
    場コード  nvarchar(2)  NULL,
    開催場所  nvarchar(10) NULL,
    race_id   nvarchar(12) NULL,   -- 競馬ブック中央12桁(厩舎の話/調教と結合可)
    レース番号 int         NULL,
    レース名  nvarchar(60) NULL,
    馬番      int          NULL,
    umacd     nvarchar(10) NULL,   -- /db/uma/{umacd}
    馬名      nvarchar(50) NULL,
    カテゴリ  nvarchar(20) NOT NULL, -- 自己ベスト/厩舎の話◎/矢印上向き/AI指数S/コンピベスト5
    順位      int          NULL,    -- cpubest/aisisuu のランク等
    単勝      nvarchar(20) NULL,
    結果      nvarchar(20) NULL
);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name='IX_ピックアップ_キー')
    CREATE INDEX IX_ピックアップ_キー ON dbo.ピックアップ(開催日,カテゴリ,race_id,馬番);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name='IX_ピックアップ_umacd')
    CREATE INDEX IX_ピックアップ_umacd ON dbo.ピックアップ(umacd,開催日);

-- 2) 自己ベスト調教の明細: 旧(従来ベスト)/新(今回)の2行で時計改善を保持。
--    ユーザ仮説(前走馬券+今走自己ベスト=好調維持)の検証に使う。
IF OBJECT_ID('dbo.自己ベスト調教','U') IS NULL
CREATE TABLE dbo.自己ベスト調教(
    Id        int IDENTITY(1,1) PRIMARY KEY,
    取得日時  datetime2    NOT NULL,
    開催日    date         NOT NULL,
    場コード  nvarchar(2)  NULL,
    race_id   nvarchar(12) NULL,
    レース番号 int         NULL,
    馬番      int          NULL,
    umacd     nvarchar(10) NULL,
    馬名      nvarchar(50) NULL,
    区分      nvarchar(2)  NOT NULL, -- 旧/新
    騎乗者    nvarchar(20) NULL,
    調教日    date         NULL,
    コース    nvarchar(20) NULL,
    馬場      nvarchar(4)  NULL,
    F5        decimal(5,1) NULL,    -- 5F(坂路は4F)
    F半哩     decimal(5,1) NULL,    -- 半哩(3F)
    F3        decimal(5,1) NULL,    -- 3F(2F)
    F1        decimal(5,1) NULL,    -- 1F
    回り位置  nvarchar(10) NULL,
    脚色      nvarchar(20) NULL,
    短評      nvarchar(60) NULL
);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name='IX_自己ベスト調教_キー')
    CREATE INDEX IX_自己ベスト調教_キー ON dbo.自己ベスト調教(開催日,race_id,馬番,区分);

SELECT '作成完了' AS status,
  (SELECT COUNT(*) FROM sys.tables WHERE name='ピックアップ') AS ピックアップ,
  (SELECT COUNT(*) FROM sys.tables WHERE name='自己ベスト調教') AS 自己ベスト調教;
