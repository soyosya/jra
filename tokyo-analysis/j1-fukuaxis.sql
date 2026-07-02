-- コンピ1位(軸)の複勝率・実複勝回収を 前走脚質/コース で層別、年別。複勝payout=払戻金(複勝,組番=馬番)。
WITH fuku AS (
  SELECT p.開催日 d, p.レース番号 rno, ri.馬名 h, MAX(p.金額) fukpay
  FROM 払戻金 p
  JOIN レース情報 ri ON ri.開催場所=p.開催場所 AND ri.開催日=p.開催日 AND ri.レース番号=p.レース番号 AND CAST(ri.馬番 AS nvarchar)=p.組番
  WHERE p.開催場所=N'東京' AND p.馬券=N'複勝'
  GROUP BY p.開催日, p.レース番号, ri.馬名
),
a AS (
  SELECT b.*, f.fukpay,
    CASE b.pst365 WHEN 1 THEN N'1_前走逃' WHEN 2 THEN N'2_前走先' WHEN 3 THEN N'3_前走差' WHEN 4 THEN N'4_前走追' ELSE N'9_無' END pk
  FROM dbo.tk_bt2 b
  LEFT JOIN fuku f ON f.d=b.d AND f.rno=b.rno AND f.h=b.h
  WHERE b.idxrank=1
)
SELECT sec, grp,
 COUNT(1) n,
 CAST(100.0*SUM(CASE WHEN fin<=3 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 複勝率,
 CAST(100.0*SUM(CASE WHEN fin=1 THEN 1.0 ELSE 0 END)/COUNT(1) AS decimal(4,1)) 勝率,
 CAST(AVG(CASE WHEN fin<=3 THEN ISNULL(fukpay,0) ELSE 0 END) AS decimal(5,0)) 複回収,
 CAST(100.0*SUM(CASE WHEN fin<=3 AND yy=2022 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN yy=2022 THEN 1 ELSE 0 END),0) AS decimal(4,0)) 複22,
 CAST(100.0*SUM(CASE WHEN fin<=3 AND yy=2023 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN yy=2023 THEN 1 ELSE 0 END),0) AS decimal(4,0)) 複23,
 CAST(100.0*SUM(CASE WHEN fin<=3 AND yy=2024 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN yy=2024 THEN 1 ELSE 0 END),0) AS decimal(4,0)) 複24,
 CAST(100.0*SUM(CASE WHEN fin<=3 AND yy=2025 THEN 1.0 ELSE 0 END)/NULLIF(SUM(CASE WHEN yy=2025 THEN 1 ELSE 0 END),0) AS decimal(4,0)) 複25
FROM (
  SELECT *, CASE sgrp WHEN 'PK' THEN pk WHEN 'PKSURF' THEN surf+N' '+pk WHEN 'ALL' THEN N'全コンピ1位' END grp, sgrp sec
  FROM a CROSS JOIN (VALUES('ALL'),('PK'),('PKSURF')) s(sgrp)
) x
WHERE grp IS NOT NULL
GROUP BY sec, grp
HAVING COUNT(1)>=60
ORDER BY sec, grp;
