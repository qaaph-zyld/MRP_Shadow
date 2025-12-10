-- ============================================================================
-- PARAMETER VALIDATION & SYNC MODULE
-- Compares QAD parameters against IBT master data and transaction history
-- ============================================================================

SET NOCOUNT ON;

-- ============================================================================
-- STEP 1: Load IBT reference data (assumes IBT.csv is loaded to temp table)
-- Run this after importing IBT.csv via SSMS Import Wizard or BULK INSERT
-- ============================================================================

-- Create temp table for IBT data if not exists
IF OBJECT_ID('tempdb..#IBT_Master') IS NOT NULL DROP TABLE #IBT_Master;

CREATE TABLE #IBT_Master (
    SupplierCode VARCHAR(20),
    SupplierName VARCHAR(100),
    Country VARCHAR(10),
    SD_Pattern VARCHAR(10),
    SD_Pattern_Desc VARCHAR(50),
    TransitDays INT,
    SafetyDays INT,
    MR_Transit INT
);

-- NOTE: Populate #IBT_Master from IBT.csv using:
-- BULK INSERT #IBT_Master FROM 'path\to\IBT.csv' WITH (FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='\n');
-- Or manually insert sample data for testing

-- ============================================================================
-- STEP 2: Extract current QAD supplier parameters (active PO lines only)
-- ============================================================================
IF OBJECT_ID('tempdb..#QAD_SupplierParams') IS NOT NULL DROP TABLE #QAD_SupplierParams;

SELECT 
    po.po_vend AS SupplierCode,
    ad.ad_name AS SupplierName,
    pod.pod_sd_pat AS QAD_SD_Pattern,
    pod.pod_translt_days AS QAD_TransitDays,
    pod.pod_sftylt_days AS QAD_SafetyDays,
    pod.pod_ord_mult AS QAD_StandardPack,
    pod.pod_firm_days AS QAD_FirmDays,
    pod.pod_plan_weeks AS QAD_PlanWeeks,
    pod.pod_part AS ItemNumber,
    pod.pod_nbr AS PONumber,
    pod.pod_line AS POLine,
    pod.pod__chr08 AS Planner
INTO #QAD_SupplierParams
FROM [QADEE2798].[dbo].[pod_det] pod WITH (NOLOCK)
JOIN [QADEE2798].[dbo].[po_mstr] po WITH (NOLOCK) ON pod.pod_nbr = po.po_nbr
LEFT JOIN [QADEE2798].[dbo].[ad_mstr] ad WITH (NOLOCK) ON po.po_vend = ad.ad_addr
WHERE pod.pod_po_site = '2798'
  AND pod.pod_status IS NULL
  AND pod.[pod_end_eff[1]]] > GETDATE();

CREATE INDEX IX_QAD_Supp ON #QAD_SupplierParams(SupplierCode);

-- ============================================================================
-- STEP 3: Derive actual standard pack from transaction history
-- ============================================================================
IF OBJECT_ID('tempdb..#ActualStandardPack') IS NOT NULL DROP TABLE #ActualStandardPack;

WITH PackCounts AS (
    SELECT
        serh_part AS ItemNumber,
        serh_qty_chg AS PackQty,
        COUNT(*) AS UsageCount,
        ROW_NUMBER() OVER (PARTITION BY serh_part ORDER BY COUNT(*) DESC, serh_qty_chg DESC) AS RN
    FROM [QADEE2798].[dbo].[serh_hist] WITH (NOLOCK)
    WHERE serh_stage NOT IN ('new', 'pending')
      AND serh_trans_type IN ('pck-bld', 'pck-rct')
      AND serh_trans_date IS NOT NULL
      AND serh_qty_chg > 0
    GROUP BY serh_part, serh_qty_chg
)
SELECT ItemNumber, PackQty AS ActualStandardPack, UsageCount
INTO #ActualStandardPack
FROM PackCounts
WHERE RN = 1;

CREATE INDEX IX_ASP ON #ActualStandardPack(ItemNumber);

-- ============================================================================
-- STEP 4: VALIDATION REPORT 1 - Supplier-Level Parameter Discrepancies
-- Compares QAD aggregate vs IBT master
-- ============================================================================
SELECT 
    'SUPPLIER_PARAM_MISMATCH' AS IssueType,
    q.SupplierCode,
    q.SupplierName,
    -- SD Pattern comparison
    q.QAD_SD_Pattern,
    i.SD_Pattern AS IBT_SD_Pattern,
    CASE WHEN ISNULL(q.QAD_SD_Pattern,'') <> ISNULL(i.SD_Pattern,'') THEN 'MISMATCH' ELSE 'OK' END AS SD_Pattern_Status,
    -- Transit Days comparison
    q.QAD_TransitDays,
    i.TransitDays AS IBT_TransitDays,
    CASE WHEN ISNULL(q.QAD_TransitDays,0) <> ISNULL(i.TransitDays,0) THEN 'MISMATCH' ELSE 'OK' END AS TransitDays_Status,
    -- Safety Days comparison
    q.QAD_SafetyDays,
    i.SafetyDays AS IBT_SafetyDays,
    CASE WHEN ISNULL(q.QAD_SafetyDays,0) <> ISNULL(i.SafetyDays,0) THEN 'MISMATCH' ELSE 'OK' END AS SafetyDays_Status,
    -- Count of items affected
    q.ItemCount,
    -- Recommendation
    CASE 
        WHEN ISNULL(q.QAD_TransitDays,0) <> ISNULL(i.TransitDays,0) 
        THEN 'Update QAD pod_translt_days to ' + CAST(ISNULL(i.TransitDays,0) AS VARCHAR(10))
        ELSE ''
    END AS Recommendation
FROM (
    SELECT 
        SupplierCode,
        MAX(SupplierName) AS SupplierName,
        MAX(QAD_SD_Pattern) AS QAD_SD_Pattern,
        MAX(QAD_TransitDays) AS QAD_TransitDays,
        MAX(QAD_SafetyDays) AS QAD_SafetyDays,
        COUNT(DISTINCT ItemNumber) AS ItemCount
    FROM #QAD_SupplierParams
    GROUP BY SupplierCode
) q
LEFT JOIN #IBT_Master i ON q.SupplierCode = i.SupplierCode
WHERE ISNULL(q.QAD_SD_Pattern,'') <> ISNULL(i.SD_Pattern,'')
   OR ISNULL(q.QAD_TransitDays,0) <> ISNULL(i.TransitDays,0)
   OR ISNULL(q.QAD_SafetyDays,0) <> ISNULL(i.SafetyDays,0)
ORDER BY q.ItemCount DESC;

-- ============================================================================
-- STEP 5: VALIDATION REPORT 2 - Item-Level Standard Pack Discrepancies
-- Compares QAD pod_ord_mult vs actual transaction history
-- ============================================================================
SELECT 
    'STANDARD_PACK_MISMATCH' AS IssueType,
    q.SupplierCode,
    q.SupplierName,
    q.ItemNumber,
    q.QAD_StandardPack,
    a.ActualStandardPack,
    a.UsageCount AS HistoricalUsageCount,
    CASE 
        WHEN q.QAD_StandardPack <> a.ActualStandardPack THEN 'MISMATCH'
        ELSE 'OK'
    END AS Status,
    CASE 
        WHEN q.QAD_StandardPack <> a.ActualStandardPack 
        THEN 'Update pod_ord_mult from ' + CAST(q.QAD_StandardPack AS VARCHAR(20)) + ' to ' + CAST(a.ActualStandardPack AS VARCHAR(20))
        ELSE ''
    END AS Recommendation,
    ABS(q.QAD_StandardPack - a.ActualStandardPack) AS DeltaQty,
    q.PONumber,
    q.POLine
FROM #QAD_SupplierParams q
INNER JOIN #ActualStandardPack a ON q.ItemNumber = a.ItemNumber
WHERE q.QAD_StandardPack <> a.ActualStandardPack
  AND a.UsageCount >= 5  -- Only flag if we have enough history
ORDER BY a.UsageCount DESC, ABS(q.QAD_StandardPack - a.ActualStandardPack) DESC;

-- ============================================================================
-- STEP 6: VALIDATION REPORT 3 - Suppliers in QAD but missing from IBT
-- ============================================================================
SELECT 
    'MISSING_FROM_IBT' AS IssueType,
    q.SupplierCode,
    q.SupplierName,
    q.ItemCount,
    'Add supplier to IBT.csv with correct parameters' AS Recommendation
FROM (
    SELECT 
        SupplierCode,
        MAX(SupplierName) AS SupplierName,
        COUNT(DISTINCT ItemNumber) AS ItemCount
    FROM #QAD_SupplierParams
    GROUP BY SupplierCode
) q
LEFT JOIN #IBT_Master i ON q.SupplierCode = i.SupplierCode
WHERE i.SupplierCode IS NULL
ORDER BY q.ItemCount DESC;

-- ============================================================================
-- STEP 7: VALIDATION REPORT 4 - Internal QAD inconsistencies per supplier
-- Same supplier has different parameters across PO lines
-- ============================================================================
SELECT 
    'INTERNAL_INCONSISTENCY' AS IssueType,
    SupplierCode,
    MAX(SupplierName) AS SupplierName,
    COUNT(DISTINCT QAD_SD_Pattern) AS DistinctSDPatterns,
    COUNT(DISTINCT QAD_TransitDays) AS DistinctTransitDays,
    COUNT(DISTINCT Planner) AS DistinctPlanners,
    COUNT(DISTINCT QAD_PlanWeeks) AS DistinctPlanWeeks,
    COUNT(DISTINCT ItemNumber) AS ItemCount,
    CASE 
        WHEN COUNT(DISTINCT QAD_TransitDays) > 1 THEN 'Standardize transport days across all PO lines'
        WHEN COUNT(DISTINCT QAD_SD_Pattern) > 1 THEN 'Standardize SD pattern across all PO lines'
        ELSE 'Review parameter consistency'
    END AS Recommendation
FROM #QAD_SupplierParams
GROUP BY SupplierCode
HAVING COUNT(DISTINCT QAD_SD_Pattern) > 1
    OR COUNT(DISTINCT QAD_TransitDays) > 1
    OR COUNT(DISTINCT Planner) > 1
    OR COUNT(DISTINCT QAD_PlanWeeks) > 1
ORDER BY COUNT(DISTINCT ItemNumber) DESC;

-- ============================================================================
-- STEP 8: SUMMARY STATISTICS
-- ============================================================================
SELECT 'VALIDATION_SUMMARY' AS ReportType, * FROM (
    SELECT 'Total Active Suppliers in QAD' AS Metric, COUNT(DISTINCT SupplierCode) AS Value FROM #QAD_SupplierParams
    UNION ALL
    SELECT 'Total Active Items in QAD', COUNT(DISTINCT ItemNumber) FROM #QAD_SupplierParams
    UNION ALL
    SELECT 'Suppliers in IBT Master', COUNT(*) FROM #IBT_Master WHERE SupplierCode IS NOT NULL AND SupplierCode <> ''
    UNION ALL
    SELECT 'Items with Historical Pack Data', COUNT(*) FROM #ActualStandardPack
) x;

-- Cleanup
DROP TABLE IF EXISTS #QAD_SupplierParams, #ActualStandardPack;
-- Note: #IBT_Master should be kept if running multiple validations
