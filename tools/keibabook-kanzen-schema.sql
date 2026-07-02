-- 競馬ブック「完全データ」= 馬ごとの出走履歴(/db/uma/{umacd}/kanzen)。中央競馬DB。
-- 1行=1頭の過去1走。脚質判定(前半3F・3/4角位置)と danwa/調教分析の素材。着順/通過は detail セルから抽出。
-- 取得日時スナップショット。競走key(/cyuou|chihou/seiseki/{rid})で race 単位に結合可。地方からの移植(構造同一)。
IF OBJECT_ID(N'競走成績', N'U') IS NULL
BEGIN
    CREATE TABLE 競走成績 (
        Id            bigint IDENTITY(1,1) NOT NULL,
        umacd         nvarchar(20)  NOT NULL,   -- 競馬ブック馬コード(/db/uma/xxxxxxx)
        馬名          nvarchar(50)  NULL,
        開催日        date          NOT NULL,
        競走key       nvarchar(24)  NULL,        -- seiseki race_id(中央12/地方16桁)
        中央地方      nvarchar(4)   NULL,        -- 中央 / 地方
        場名          nvarchar(20)  NOT NULL,
        レース番号    int           NOT NULL CONSTRAINT DF_競走成績_R DEFAULT(0),
        レース名      nvarchar(60)  NULL,
        コース種別    nvarchar(6)   NULL,        -- ダート / 芝 / 障
        回り          nvarchar(4)   NULL,        -- 左 / 右 / 直
        距離          int           NULL,        -- m
        馬場          nvarchar(6)   NULL,        -- 良/稍重/重/不良
        天候          nvarchar(6)   NULL,        -- 晴/曇/雨/小雨/雪
        頭数          int           NULL,
        ゲート番      int           NULL,
        馬体重        int           NULL,
        本紙印        nvarchar(4)   NULL,        -- ◎○▲△注×
        単勝オッズ    decimal(7,1)  NULL,
        人気          int           NULL,
        前半3F        decimal(5,1)  NULL,        -- 当該馬前半3ハロン(600m)
        後半3F        decimal(5,1)  NULL,        -- 当該馬後半3ハロン
        後半3F最速    bit           NOT NULL CONSTRAINT DF_競走成績_最速 DEFAULT(0),
        ペース        nvarchar(4)   NULL,        -- H/M/S
        レース上り4F  decimal(5,1)  NULL,        -- レース後半4F(800m)
        レース上り3F  decimal(5,1)  NULL,        -- レース後半3F(600m)
        通過1角       int           NULL,        -- 各コーナー通過順位
        通過2角       int           NULL,
        通過3角       int           NULL,
        通過4角       int           NULL,
        不利          bit           NOT NULL CONSTRAINT DF_競走成績_不利 DEFAULT(0),
        四角内外      nvarchar(4)   NULL,        -- 4角位置取り(内/中/外)
        着順          int           NULL,
        走破タイム    nvarchar(12)  NULL,
        着差          nvarchar(16)  NULL,
        騎手          nvarchar(20)  NULL,
        負担重量      decimal(4,1)  NULL,
        スピード指数  int           NULL,
        寸評          nvarchar(80)  NULL,
        追切          nvarchar(120) NULL,        -- 最終追い切り(日付/場/時計/短評/矢印)
        ラップタイム  nvarchar(120) NULL,        -- 全ハロンのラップ "12.9-11.6-..."
        前半100m時計  float         NULL,        -- 前半3F欠落時の代替ペース=(走破秒-後半3F)/(距離-600)*100
        取得日時      datetime2     NOT NULL,
        取得元        nvarchar(40)  NULL,
        CONSTRAINT PK_競走成績 PRIMARY KEY CLUSTERED (Id)
    );
    CREATE NONCLUSTERED INDEX IX_競走成績_馬 ON 競走成績(umacd, 開催日 DESC);
    CREATE NONCLUSTERED INDEX IX_競走成績_条件 ON 競走成績(場名, 距離, コース種別, 馬場) INCLUDE(umacd, 前半3F, 通過3角, 通過4角);
    CREATE UNIQUE NONCLUSTERED INDEX UX_競走成績_スナップ ON 競走成績(umacd, 開催日, 場名, レース番号, 取得日時);
    CREATE NONCLUSTERED INDEX IX_競走成績_競走 ON 競走成績(競走key);
    PRINT '競走成績 作成完了';
END
ELSE PRINT '競走成績 既存';
