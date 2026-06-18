/* ============================================================
   コンピ指数テーブル(日刊スポーツ 極ウマ)
   開催日・場名・レース番号・馬番・馬名・指数・指数順位 を保存。
   + 変遷追跡用「取得日時」スナップショット / 順位正規化用「頭数」。
   着順は既存 競走結果(開催場所,開催日,レース番号,馬番)と結合して取得。
   ============================================================ */
IF OBJECT_ID(N'コンピ指数', N'U') IS NULL
BEGIN
  CREATE TABLE コンピ指数(
    Id          BIGINT IDENTITY(1,1) CONSTRAINT PK_コンピ指数 PRIMARY KEY,
    開催日       DATE          NOT NULL,
    開催場所     NVARCHAR(20)  NOT NULL,   -- 既存テーブルと同じ場名(高知/園田…)で保存して結合可能に
    レース番号   INT           NOT NULL,
    馬番         INT           NOT NULL,
    馬名         NVARCHAR(50)  NULL,
    指数         INT           NULL,        -- 40〜90
    指数順位     INT           NULL,        -- 1..頭数
    頭数         INT           NULL,        -- 出走頭数(指数順位の正規化に使用)
    取得日時     DATETIME2(0)  NOT NULL CONSTRAINT DF_コンピ指数_取得日時 DEFAULT SYSDATETIME(), -- スナップショット(変遷追跡)
    取得元       NVARCHAR(40)  NULL CONSTRAINT DF_コンピ指数_取得元 DEFAULT N'goku-uma'
  );
  -- 同一(レース×馬×取得時刻)は1行。再取得は別スナップショットとして追加=変遷を残す。
  CREATE UNIQUE INDEX UX_コンピ指数_スナップ ON コンピ指数(開催日,開催場所,レース番号,馬番,取得日時);
  -- 競走結果との結合(着順相関)
  CREATE INDEX IX_コンピ指数_結合 ON コンピ指数(開催場所,開催日,レース番号,馬番) INCLUDE(指数,指数順位,頭数,取得日時);
  -- レース内の順位走査
  CREATE INDEX IX_コンピ指数_順位 ON コンピ指数(開催日,開催場所,レース番号,指数順位);
END
GO
