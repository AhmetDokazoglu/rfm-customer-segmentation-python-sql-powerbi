/* ============================================================
   RFM PROJESÝ - SQL SERVER (T-SQL)
   1) Veritabaný ve ana tablo
   2) Kontrol sorgularý
   3) RFM metrikleri (Recency/Frequency/Monetary)
   4) RFM skorlarý (NTILE)
   5) Segment atama (CASE WHEN)
   6) Power BI için özet tablolar
   ============================================================ */

-- ============================================================
-- 1) Veritabaný ve tablo
-- ============================================================

-- Ýsteðe baðlý: DB oluþturma
-- CREATE DATABASE OnlineRetailDB;
-- GO
-- USE OnlineRetailDB;
-- GO

-- Ana tablo (CSV import edeceðin tablo yapýsý)
-- Import Wizard ile yükleyeceksen kolon tiplerini buna yakýn tut.
IF OBJECT_ID('dbo.Satislar', 'U Registration') IS NOT NULL
    DROP TABLE dbo.Satislar;
GO

CREATE TABLE dbo.Satislar (
    FaturaNo       NVARCHAR(20)   NOT NULL,
    UrunKodu       NVARCHAR(30)   NULL,
    UrunAciklama   NVARCHAR(255)  NULL,
    Adet           INT            NOT NULL,
    FaturaTarihi   DATETIME       NOT NULL,
    BirimFiyat     DECIMAL(18,4)  NOT NULL,
    MusteriID      INT            NOT NULL,
    Ulke           NVARCHAR(50)   NULL,
    ToplamTutar    DECIMAL(18,4)  NOT NULL
);
GO

/* NOT:
   - Bu tabloya 'online_retail_temiz.csv' dosyaný Import and Export Wizard ile aktar.
   - Alternatif olarak BULK INSERT/OPENROWSET de kullanýlabilir (ayar gerektirir).
*/

-- ============================================================
-- 2) Veri kontrolleri
-- ============================================================

-- Toplam kayýt
SELECT COUNT(*) AS ToplamKayit FROM dbo.Satislar;

-- Eksik müþteri kontrol (temiz veride 0 olmalý)
SELECT COUNT(*) AS EksikMusteri
FROM dbo.Satislar
WHERE MusteriID IS NULL;

-- Negatif/sýfýr adet-fiyat kontrol (temiz veride 0 olmalý)
SELECT
    SUM(CASE WHEN Adet <= 0 THEN 1 ELSE 0 END) AS NegatifVeyaSifirAdet,
    SUM(CASE WHEN BirimFiyat <= 0 THEN 1 ELSE 0 END) AS NegatifVeyaSifirFiyat
FROM dbo.Satislar;

-- Tarih aralýðý
SELECT MIN(FaturaTarihi) AS MinTarih, MAX(FaturaTarihi) AS MaxTarih
FROM dbo.Satislar;


-- ============================================================
-- 3) RFM metrikleri (müþteri bazlý)
-- ============================================================

/* Referans tarih:
   Pratikte: veri setindeki en son tarihten 1 gün sonrasý seçilir
   Böylece "en son alýþveriþ" için recency 0 yerine pozitif çýkar.
*/
DECLARE @RefDate DATE =
(
    SELECT DATEADD(DAY, 1, CAST(MAX(FaturaTarihi) AS DATE))
    FROM dbo.Satislar
);

IF OBJECT_ID('tempdb..#RFM_Base') IS NOT NULL DROP TABLE #RFM_Base;

SELECT
    MusteriID,
    DATEDIFF(DAY, MAX(FaturaTarihi), @RefDate) AS Recency,
    COUNT(DISTINCT FaturaNo)                   AS Frequency,
    SUM(ToplamTutar)                           AS Monetary
INTO #RFM_Base
FROM dbo.Satislar
GROUP BY MusteriID;

-- Kontrol: ilk 10 müþteri
SELECT TOP 10 * FROM #RFM_Base ORDER BY Monetary DESC;


-- ============================================================
-- 4) RFM skorlarý (1-5)
-- ============================================================

/* Skorlama mantýðý:
   - Recency düþük = daha iyi => yüksek skor vermek için ters sýralama (ORDER BY Recency ASC)
   - Frequency yüksek = daha iyi => ORDER BY Frequency DESC
   - Monetary yüksek = daha iyi => ORDER BY Monetary DESC
*/

IF OBJECT_ID('tempdb..#RFM_Scored') IS NOT NULL DROP TABLE #RFM_Scored;

SELECT
    MusteriID,
    Recency,
    Frequency,
    Monetary,
    NTILE(5) OVER (ORDER BY Recency ASC)      AS R_Skor,
    NTILE(5) OVER (ORDER BY Frequency DESC)   AS F_Skor,
    NTILE(5) OVER (ORDER BY Monetary DESC)    AS M_Skor
INTO #RFM_Scored
FROM #RFM_Base;

-- RFM kodu
ALTER TABLE #RFM_Scored ADD RFM_Kod AS
    (CONCAT(CAST(R_Skor AS VARCHAR(1)), CAST(F_Skor AS VARCHAR(1)), CAST(M_Skor AS VARCHAR(1))));

SELECT TOP 10 * FROM #RFM_Scored ORDER BY RFM_Kod DESC;


-- ============================================================
-- 5) Segment atama (CASE WHEN)
-- ============================================================

/* Segmentleri basit ve yaygýn kullanýlan mantýkla atýyoruz.
   Not: Segment kurallarý kurumlara göre deðiþebilir; burada portföy için net ve anlaþýlýr bir set kullanýldý.
*/

IF OBJECT_ID('dbo.RFM_Segment', 'U') IS NOT NULL DROP TABLE dbo.RFM_Segment;
GO

SELECT
    MusteriID,
    Recency,
    Frequency,
    Monetary,
    R_Skor,
    F_Skor,
    M_Skor,
    CONCAT(CAST(R_Skor AS VARCHAR(1)), CAST(F_Skor AS VARCHAR(1)), CAST(M_Skor AS VARCHAR(1))) AS RFM_Kod,
    CASE
        WHEN R_Skor >= 4 AND F_Skor >= 4 AND M_Skor >= 4 THEN 'Champions'
        WHEN F_Skor >= 4 AND M_Skor >= 3                 THEN 'Loyal Customers'
        WHEN R_Skor >= 4 AND F_Skor BETWEEN 3 AND 4      THEN 'Potential Loyalists'
        WHEN R_Skor = 5  AND F_Skor <= 2                 THEN 'New Customers'
        WHEN R_Skor = 4  AND F_Skor BETWEEN 2 AND 3      THEN 'Promising'
        WHEN R_Skor BETWEEN 2 AND 3 AND F_Skor BETWEEN 2 AND 3 THEN 'At Risk'
        WHEN R_Skor BETWEEN 1 AND 2 AND F_Skor BETWEEN 1 AND 2 THEN 'Hibernating'
        WHEN R_Skor = 1  AND F_Skor = 1                  THEN 'Lost'
        ELSE 'Others'
    END AS Segment
INTO dbo.RFM_Segment
FROM #RFM_Scored;

-- Segment daðýlýmý
SELECT Segment, COUNT(*) AS MusteriSayisi
FROM dbo.RFM_Segment
GROUP BY Segment
ORDER BY MusteriSayisi DESC;


-- ============================================================
-- 6) Power BI için özet tablolar
-- ============================================================

/* 6.1 Segment Özet: müþteri sayýsý, toplam ciro, sipariþ sayýsý, ortalama RFM metrikleri */
IF OBJECT_ID('dbo.Segment_Ozet', 'U') IS NOT NULL DROP TABLE dbo.Segment_Ozet;
GO

SELECT
    s.Segment,
    COUNT(DISTINCT a.MusteriID)                       AS MusteriSayisi,
    SUM(a.ToplamTutar)                                 AS ToplamCiro,
    COUNT(DISTINCT a.FaturaNo)                         AS SiparisSayisi,
    AVG(CAST(r.Recency AS FLOAT))                      AS OrtalamaRecency,
    AVG(CAST(r.Frequency AS FLOAT))                    AS OrtalamaFrequency,
    AVG(CAST(r.Monetary AS FLOAT))                     AS OrtalamaMonetary
INTO dbo.Segment_Ozet
FROM dbo.Satislar a
JOIN dbo.RFM_Segment r ON a.MusteriID = r.MusteriID
JOIN (SELECT MusteriID, Segment FROM dbo.RFM_Segment) s ON s.MusteriID = a.MusteriID
GROUP BY s.Segment;

SELECT * FROM dbo.Segment_Ozet ORDER BY ToplamCiro DESC;


/* 6.2 Aylýk Ciro: zaman trendi (genel) */
IF OBJECT_ID('dbo.Aylik_Ciro', 'U') IS NOT NULL DROP TABLE dbo.Aylik_Ciro;
GO

SELECT
    YEAR(FaturaTarihi)  AS Yil,
    MONTH(FaturaTarihi) AS Ay,
    SUM(ToplamTutar)    AS AylikToplamCiro,
    COUNT(DISTINCT FaturaNo) AS AylikSiparisSayisi
INTO dbo.Aylik_Ciro
FROM dbo.Satislar
GROUP BY YEAR(FaturaTarihi), MONTH(FaturaTarihi);

SELECT * FROM dbo.Aylik_Ciro ORDER BY Yil, Ay;


/* 6.3 Aylýk Segment Ciro: segment kýrýlýmý */
IF OBJECT_ID('dbo.Aylik_Segment_Ciro', 'U') IS NOT NULL DROP TABLE dbo.Aylik_Segment_Ciro;
GO

SELECT
    YEAR(a.FaturaTarihi)  AS Yil,
    MONTH(a.FaturaTarihi) AS Ay,
    r.Segment,
    SUM(a.ToplamTutar)    AS AylikCiro,
    COUNT(DISTINCT a.FaturaNo) AS AylikSiparisSayisi
INTO dbo.Aylik_Segment_Ciro
FROM dbo.Satislar a
JOIN dbo.RFM_Segment r ON a.MusteriID = r.MusteriID
GROUP BY YEAR(a.FaturaTarihi), MONTH(a.FaturaTarihi), r.Segment;

SELECT * FROM dbo.Aylik_Segment_Ciro ORDER BY Yil, Ay, AylikCiro DESC;


/* 6.4 Segment Yüzde: segmentlerin toplam cirodan payý */
IF OBJECT_ID('dbo.Segment_Yuzde', 'U') IS NOT NULL DROP TABLE dbo.Segment_Yuzde;
GO

WITH toplam AS (
    SELECT SUM(ToplamCiro) AS GenelCiro
    FROM dbo.Segment_Ozet
)
SELECT
    o.Segment,
    o.ToplamCiro,
    CAST(o.ToplamCiro / NULLIF(t.GenelCiro,0) * 100.0 AS DECIMAL(10,2)) AS CiroYuzde
INTO dbo.Segment_Yuzde
FROM dbo.Segment_Ozet o
CROSS JOIN toplam t;

SELECT * FROM dbo.Segment_Yuzde ORDER BY CiroYuzde DESC;


/* 6.5 VIP Müþteri Detayý: Champions vb. için müþteri listesi (Power BI tablosu için) */
IF OBJECT_ID('dbo.VIP_Musteriler', 'U') IS NOT NULL DROP TABLE dbo.VIP_Musteriler;
GO

SELECT
    r.MusteriID,
    r.Segment,
    r.RFM_Kod,
    r.Recency,
    r.Frequency,
    r.Monetary
INTO dbo.VIP_Musteriler
FROM dbo.RFM_Segment r
WHERE r.Segment IN ('Champions', 'Loyal Customers');

SELECT TOP 50 * FROM dbo.VIP_Musteriler ORDER BY Monetary DESC;
