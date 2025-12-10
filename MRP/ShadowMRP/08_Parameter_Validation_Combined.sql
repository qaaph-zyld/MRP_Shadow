-- ============================================================================
-- PARAMETER VALIDATION & SYNC MODULE (COMBINED OUTPUT)
-- Produces a single wide result set so it can be exported to CSV.
-- This script does NOT drop #IBT_Master if it exists. Expected usage:
--   1) Load IBT.csv into temp table #IBT_Master (same schema as below)
--   2) Run this script (directly or via Run_Full_Analysis.ps1)
-- ============================================================================

SET NOCOUNT ON;

-- Ensure #IBT_Master exists (empty shell if not already loaded)
IF OBJECT_ID('tempdb..#IBT_Master') IS NULL
BEGIN
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
END;

-- Working tables
IF OBJECT_ID('tempdb..#QAD_SupplierParams') IS NOT NULL DROP TABLE #QAD_SupplierParams;
IF OBJECT_ID('tempdb..#ActualStandardPack') IS NOT NULL DROP TABLE #ActualStandardPack;
IF OBJECT_ID('tempdb..#ParamValidation') IS NOT NULL DROP TABLE #ParamValidation;

CREATE TABLE #ParamValidation (
    ReportType      VARCHAR(50),   -- 'ISSUE' or 'SUMMARY'
    IssueType       VARCHAR(50),   -- e.g. SUPPLIER_PARAM_MISMATCH
    SupplierCode    VARCHAR(20),
    SupplierName    VARCHAR(200),
    ItemNumber      VARCHAR(50),
    PONumber        VARCHAR(50),
    POLine         INT,
    Metric1Label    VARCHAR(100),
    Metric1Value    NVARCHAR(4000),
    Metric2Label    VARCHAR(100),
    Metric2Value    NVARCHAR(4000),
    Metric3Label    VARCHAR(100),
    Metric3Value    NVARCHAR(4000),
    Recommendation  NVARCHAR(4000)
);

-- ============================================================================
-- STEP 1: Extract current QAD supplier parameters (active PO lines only)
-- ============================================================================
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
-- STEP 2: Derive actual standard pack from transaction history
-- ============================================================================
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
-- ISSUE 1: SUPPLIER_PARAM_MISMATCH (vs IBT)
-- ============================================================================
INSERT INTO #ParamValidation (
    ReportType, IssueType, SupplierCode, SupplierName, ItemNumber,
    PONumber, POLine,
    Metric1Label, Metric1Value,
    Metric2Label, Metric2Value,
    Metric3Label, Metric3Value,
    Recommendation
)
SELECT 
    'ISSUE' AS ReportType,
    'SUPPLIER_PARAM_MISMATCH' AS IssueType,
    q.SupplierCode,
    q.SupplierName,
    NULL AS ItemNumber,
    NULL AS PONumber,
    NULL AS POLine,
    'SD_Pattern' AS Metric1Label,
    CONCAT(ISNULL(q.QAD_SD_Pattern,''), ' vs ', ISNULL(i.SD_Pattern,'')) AS Metric1Value,
    'TransitDays' AS Metric2Label,
    CONCAT(ISNULL(CAST(q.QAD_TransitDays AS VARCHAR(10)),'0'), ' vs ', ISNULL(CAST(i.TransitDays AS VARCHAR(10)),'0')) AS Metric2Value,
    'SafetyDays' AS Metric3Label,
    CONCAT(ISNULL(CAST(q.QAD_SafetyDays AS VARCHAR(10)),'0'), ' vs ', ISNULL(CAST(i.SafetyDays AS VARCHAR(10)),'0')) AS Metric3Value,
    CASE 
        WHEN ISNULL(q.QAD_TransitDays,0) <> ISNULL(i.TransitDays,0) 
        THEN 'Update QAD pod_translt_days to ' + CAST(ISNULL(i.TransitDays,0) AS VARCHAR(10))
        ELSE 'Review SD pattern / safety days vs IBT'
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
WHERE (SELECT COUNT(*) FROM #IBT_Master) > 0
  AND (
        ISNULL(q.QAD_SD_Pattern,'') <> ISNULL(i.SD_Pattern,'')
     OR ISNULL(q.QAD_TransitDays,0) <> ISNULL(i.TransitDays,0)
     OR ISNULL(q.QAD_SafetyDays,0) <> ISNULL(i.SafetyDays,0)
  );

-- ============================================================================
-- ISSUE 2: STANDARD_PACK_MISMATCH (vs history)
-- ============================================================================
INSERT INTO #ParamValidation (
    ReportType, IssueType, SupplierCode, SupplierName, ItemNumber,
    PONumber, POLine,
    Metric1Label, Metric1Value,
    Metric2Label, Metric2Value,
    Metric3Label, Metric3Value,
    Recommendation
)
SELECT 
    'ISSUE' AS ReportType,
    'STANDARD_PACK_MISMATCH' AS IssueType,
    q.SupplierCode,
    q.SupplierName,
    q.ItemNumber,
    q.PONumber,
    q.POLine,
    'QAD_StandardPack' AS Metric1Label,
    CAST(q.QAD_StandardPack AS NVARCHAR(50)) AS Metric1Value,
    'ActualStandardPack' AS Metric2Label,
    CAST(a.ActualStandardPack AS NVARCHAR(50)) AS Metric2Value,
    'UsageCount' AS Metric3Label,
    CAST(a.UsageCount AS NVARCHAR(50)) AS Metric3Value,
    CASE 
        WHEN q.QAD_StandardPack <> a.ActualStandardPack 
        THEN 'Update pod_ord_mult from ' + CAST(q.QAD_StandardPack AS VARCHAR(20)) + ' to ' + CAST(a.ActualStandardPack AS VARCHAR(20))
        ELSE ''
    END AS Recommendation
FROM #QAD_SupplierParams q
INNER JOIN #ActualStandardPack a ON q.ItemNumber = a.ItemNumber
WHERE q.QAD_StandardPack <> a.ActualStandardPack
  AND a.UsageCount >= 5;

-- ============================================================================
-- ISSUE 3: MISSING_FROM_IBT (only if IBT has data)
-- ============================================================================
IF (SELECT COUNT(*) FROM #IBT_Master) > 0
BEGIN
    INSERT INTO #ParamValidation (
        ReportType, IssueType, SupplierCode, SupplierName, ItemNumber,
        PONumber, POLine,
        Metric1Label, Metric1Value,
        Metric2Label, Metric2Value,
        Metric3Label, Metric3Value,
        Recommendation
    )
    SELECT 
        'ISSUE' AS ReportType,
        'MISSING_FROM_IBT' AS IssueType,
        q.SupplierCode,
        q.SupplierName,
        NULL AS ItemNumber,
        NULL AS PONumber,
        NULL AS POLine,
        'ItemCount' AS Metric1Label,
        CAST(q.ItemCount AS NVARCHAR(50)) AS Metric1Value,
        NULL AS Metric2Label,
        NULL AS Metric2Value,
        NULL AS Metric3Label,
        NULL AS Metric3Value,
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
    WHERE i.SupplierCode IS NULL;
END;

-- ============================================================================
-- ISSUE 4: INTERNAL_INCONSISTENCY per supplier
-- ============================================================================
INSERT INTO #ParamValidation (
    ReportType, IssueType, SupplierCode, SupplierName, ItemNumber,
    PONumber, POLine,
    Metric1Label, Metric1Value,
    Metric2Label, Metric2Value,
    Metric3Label, Metric3Value,
    Recommendation
)
SELECT 
    'ISSUE' AS ReportType,
    'INTERNAL_INCONSISTENCY' AS IssueType,
    SupplierCode,
    MAX(SupplierName) AS SupplierName,
    NULL AS ItemNumber,
    NULL AS PONumber,
    NULL AS POLine,
    'DistinctSDPatterns' AS Metric1Label,
    CAST(COUNT(DISTINCT QAD_SD_Pattern) AS NVARCHAR(50)) AS Metric1Value,
    'DistinctTransitDays' AS Metric2Label,
    CAST(COUNT(DISTINCT QAD_TransitDays) AS NVARCHAR(50)) AS Metric2Value,
    'DistinctPlanners' AS Metric3Label,
    CAST(COUNT(DISTINCT Planner) AS NVARCHAR(50)) AS Metric3Value,
    CASE 
        WHEN COUNT(DISTINCT QAD_TransitDays) > 1 THEN 'Standardize transport days across all PO lines'
        WHEN COUNT(DISTINCT QAD_SD_Pattern) > 1 THEN 'Standardize SD pattern across all PO lines'
        ELSE 'Review parameter consistency across PO lines'
    END AS Recommendation
FROM #QAD_SupplierParams
GROUP BY SupplierCode
HAVING COUNT(DISTINCT QAD_SD_Pattern) > 1
    OR COUNT(DISTINCT QAD_TransitDays) > 1
    OR COUNT(DISTINCT Planner) > 1
    OR COUNT(DISTINCT QAD_PlanWeeks) > 1;

-- ============================================================================
-- SUMMARY ROWS
-- ============================================================================
INSERT INTO #ParamValidation (
    ReportType, IssueType, SupplierCode, SupplierName, ItemNumber,
    PONumber, POLine,
    Metric1Label, Metric1Value,
    Metric2Label, Metric2Value,
    Metric3Label, Metric3Value,
    Recommendation
)
SELECT 'SUMMARY' AS ReportType,
       'VALIDATION_SUMMARY' AS IssueType,
       NULL AS SupplierCode,
       NULL AS SupplierName,
       NULL AS ItemNumber,
       NULL AS PONumber,
       NULL AS POLine,
       Metric AS Metric1Label,
       CAST(Value AS NVARCHAR(4000)) AS Metric1Value,
       NULL,NULL,NULL,NULL,
       NULL AS Recommendation
FROM (
    SELECT 'Total Active Suppliers in QAD' AS Metric, COUNT(DISTINCT SupplierCode) AS Value FROM #QAD_SupplierParams
    UNION ALL
    SELECT 'Total Active Items in QAD', COUNT(DISTINCT ItemNumber) FROM #QAD_SupplierParams
    UNION ALL
    SELECT 'Suppliers in IBT Master', COUNT(*) FROM #IBT_Master WHERE SupplierCode IS NOT NULL AND SupplierCode <> ''
    UNION ALL
    SELECT 'Items with Historical Pack Data', COUNT(*) FROM #ActualStandardPack
) s;

-- Final combined output
SELECT *
FROM #ParamValidation
ORDER BY ReportType DESC, IssueType, SupplierCode, ItemNumber;

-- Cleanup working tables (keep #IBT_Master for reuse)
DROP TABLE IF EXISTS #QAD_SupplierParams;
DROP TABLE IF EXISTS #ActualStandardPack;
DROP TABLE IF EXISTS #ParamValidation;
