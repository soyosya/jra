/* ============================================================
   SQL Express → Developer 移行用スクリプト
   新しく入れた Developer インスタンス(SSMS等)で順に実行する。
   前提: 移行前バックアップを取得済み(中央競馬_premigration.bak)。
   接続文字列を変えないため、インスタンス名は SQLEXPRESS のまま、
   認証=混合モード、sa パスワード=従来同一、サーバ照合順序=Japanese_CI_AS で
   Developer をインストールしておくこと。
   ============================================================ */

/* 1) データベース復元 ----------------------------------------
   .bak のパスを実際のコピー先に変更すること。
   既定データパスが同じ(インスタンス名 SQLEXPRESS 一致)なら MOVE 不要。
   異なる場合は RESTORE FILELISTONLY で論理名を確認し MOVE を付ける。 */
-- RESTORE FILELISTONLY FROM DISK=N'C:\backup\中央競馬_premigration.bak';

RESTORE DATABASE [中央競馬]
  FROM DISK = N'C:\backup\中央競馬_premigration.bak'
  WITH RECOVERY, REPLACE, STATS = 10;
  -- ,MOVE N'中央競馬'     TO N'C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\DATA\中央競馬.mdf'
  -- ,MOVE N'中央競馬_log' TO N'C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\DATA\中央競馬_log.ldf'
GO

/* 2) メモリ上限(63GB機。OSに残す。Developer/Enterpriseは既定で全部掴むため必須) */
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'max server memory (MB)', 51200; RECONFIGURE;   -- 50GB割当
GO

/* 3) 復旧モデル(分析用途。ログ肥大を防ぐ。元々SIMPLEなら復元で維持される) */
ALTER DATABASE [中央競馬] SET RECOVERY SIMPLE;
GO

/* 4) 性能用インデックス(バックアップに含まれていれば既存。万一の古いbak対策に冪等で再作成) */
USE [中央競馬];
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name='IX_競走結果_馬名')
  CREATE NONCLUSTERED INDEX IX_競走結果_馬名 ON 競走結果(馬名,開催日,レース番号)
    INCLUDE(開催場所,馬番,着順,走破時計,上り3F,一コーナー,二コーナー,三コーナー,四コーナー);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name='IX_競走結果_場日R馬番')
  CREATE NONCLUSTERED INDEX IX_競走結果_場日R馬番 ON 競走結果(開催場所,開催日,レース番号,馬番)
    INCLUDE(着順,走破時計);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name='IX_レース情報_馬名')
  CREATE NONCLUSTERED INDEX IX_レース情報_馬名 ON レース情報(馬名,開催日,レース番号)
    INCLUDE(開催場所,馬番,距離,騎手,馬体重,馬体重増減);
GO

/* 5) 統計を最新化(復元直後の推奨) */
USE [中央競馬]; EXEC sp_updatestats;
GO

/* 6) 検証 */
SELECT Edition=SERVERPROPERTY('Edition'), Collation=SERVERPROPERTY('Collation'),
       MaxMemMB=(SELECT value_in_use FROM sys.configurations WHERE name='max server memory (MB)');
SELECT t=N'競走結果', n=COUNT(*) FROM 競走結果;
SELECT name FROM sys.indexes WHERE object_id=OBJECT_ID(N'競走結果') AND type>0;
GO
