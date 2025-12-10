-- ============================================================================
-- ANOMALY DETECTION MODULE (COMBINED OUTPUT)
-- Produces a single wide result set so it can be exported to CSV.
-- Uses v_ShadowMRP_BOMClassification to avoid flagging FG/SFG for missing POs.
-- ============================================================================

SET NOCOUNT ON;

DECLARE @CurrentDate DATE = CAST(GETDATE() AS DATE);

IF OBJECT_ID('tempdb..#Anomalies') IS NOT NULL DROP TABLE #Anomalies;

CREATE TABLE #Anomalies (
    ReportType      VARCHAR(50),     -- 'ISSUE' or 'SUMMARY'
    AnomalyType     VARCHAR(50),
    Site            VARCHAR(10),
    ItemNumber      VARCHAR(50),
    ItemDescription VARCHAR(200),
    ItemType        VARCHAR(10),     -- FG / SFG / RM / No BOM
    Supplier        VARCHAR(50),
    SupplierName    VARCHAR(200),
    ScheduleNumber  VARCHAR(50),
    ScheduleLine    INT,
    PONumber        VARCHAR(50),
    POLine          INT,
    Metric1Label    VARCHAR(100),
    Metric1Value    NVARCHAR(4000),
    Metric2Label    VARCHAR(100),
    Metric2Value    NVARCHAR(4000),
    Metric3Label    VARCHAR(100),
    Metric3Value    NVARCHAR(4000),
    EarliestDate    DATETIME NULL,
    LatestDate      DATETIME NULL,
    Action          NVARCHAR(4000)
);

-- Local BOM classification (FG/SFG/RM) to avoid dependency on external view
IF OBJECT_ID('tempdb..#BomClass') IS NOT NULL DROP TABLE #BomClass;

WITH ParentItems AS (
    SELECT DISTINCT 
        '2798' AS Site,
        ps_par AS ItemNumber,
        1 AS IsParent
    FROM [QADEE2798].[dbo].[ps_mstr]
    WHERE ps_end IS NULL
),
ChildItems AS (
    SELECT DISTINCT 
        '2798' AS Site,
        ps_comp AS ItemNumber,
        1 AS IsChild
    FROM [QADEE2798].[dbo].[ps_mstr]
    WHERE ps_end IS NULL
),
AllItems AS (
    SELECT 
        pt.pt_site AS Site,
        pt.pt_part AS ItemNumber,
        pt.pt_desc1 AS ItemDescription,
        pt.pt_sfty_stk AS SafetyStock,
        pt.pt_vend AS DefaultSupplier,
        pt.pt_buyer AS Planner,
        pt.pt__chr02 AS ItemTypeMaster,
        pt.pt_prod_line AS ProdLine,
        pt.pt_group AS ItemGroup,
        pt.pt_status AS ItemStatus
    FROM [QADEE2798].[dbo].[pt_mstr] pt
    WHERE pt.pt_site = '2798'
      AND pt.pt_part_type NOT IN ('xc', 'rc')
)
SELECT
    a.Site,
    a.ItemNumber,
    a.ItemDescription,
    a.SafetyStock,
    a.DefaultSupplier,
    a.Planner,
    a.ItemTypeMaster,
    a.ProdLine,
    a.ItemGroup,
    a.ItemStatus,
    ISNULL(p.IsParent, 0) AS IsParent,
    ISNULL(c.IsChild, 0) AS IsChild,
    CASE
        WHEN ISNULL(p.IsParent, 0) = 1 AND ISNULL(c.IsChild, 0) = 1 THEN 'SFG'
        WHEN ISNULL(p.IsParent, 0) = 1 AND ISNULL(c.IsChild, 0) = 0 THEN 'FG'
        WHEN ISNULL(p.IsParent, 0) = 0 AND ISNULL(c.IsChild, 0) = 1 THEN 'RM'
        ELSE 'No BOM'
    END AS ItemType
INTO #BomClass
FROM AllItems a
LEFT JOIN ParentItems p ON a.Site = p.Site AND a.ItemNumber = p.ItemNumber
LEFT JOIN ChildItems c ON a.Site = c.Site AND a.ItemNumber = c.ItemNumber;

-- ============================================================================
-- ANOMALY 1: Duplicate Active PO Lines for Same Item
-- Multiple active PO lines for the same item = undefined supplier preference
-- ============================================================================
INSERT INTO #Anomalies (
    ReportType, AnomalyType, Site, ItemNumber, ItemDescription, ItemType,
    Supplier, SupplierName, ScheduleNumber, ScheduleLine, PONumber, POLine,
    Metric1Label, Metric1Value, Metric2Label, Metric2Value, Metric3Label, Metric3Value,
    EarliestDate, LatestDate, Action
)
SELECT 
    'ISSUE' AS ReportType,
    'DUPLICATE_PO_LINES' AS AnomalyType,
    pod.pod_po_site AS Site,
    pod.pod_part AS ItemNumber,
    bc.ItemDescription,
    bc.ItemType,
    NULL AS Supplier,
    NULL AS SupplierName,
    NULL AS ScheduleNumber,
    NULL AS ScheduleLine,
    NULL AS PONumber,
    NULL AS POLine,
    'ActivePOLineCount' AS Metric1Label,
    CAST(COUNT(*) AS NVARCHAR(50)) AS Metric1Value,
    'POLines' AS Metric2Label,
    STRING_AGG(pod.pod_nbr + '/' + CAST(pod.pod_line AS VARCHAR(10)), ', ') AS Metric2Value,
    'Suppliers' AS Metric3Label,
    STRING_AGG(CAST(po.po_vend AS VARCHAR(20)), ', ') AS Metric3Value,
    MIN(pod.[pod_due_date]) AS EarliestDate,
    MAX(pod.[pod_due_date]) AS LatestDate,
    'Review and close duplicate PO lines or clarify supplier preference' AS Action
FROM [QADEE2798].[dbo].[pod_det] pod WITH (NOLOCK)
JOIN [QADEE2798].[dbo].[po_mstr] po WITH (NOLOCK) ON pod.pod_nbr = po.po_nbr
LEFT JOIN #BomClass bc ON bc.Site = pod.pod_po_site AND bc.ItemNumber = pod.pod_part
WHERE pod.pod_po_site = '2798'
  AND pod.pod_status IS NULL
  AND pod.[pod_end_eff[1]]] > @CurrentDate
GROUP BY pod.pod_po_site, pod.pod_part, bc.ItemDescription, bc.ItemType
HAVING COUNT(*) > 1;

-- ============================================================================
-- ANOMALY 2: Items with Customer Demand but No Active PO Line (Components only)
-- FG/SFG are supplied via production, not PO, so we only flag RM components.
-- ============================================================================
WITH DemandItems AS (
    SELECT DISTINCT sod.sod_part AS ItemNumber
    FROM [QADEE2798].[dbo].[sod_det] sod WITH (NOLOCK)
    INNER JOIN [QADEE2798].[dbo].[sch_mstr] sch WITH (NOLOCK)
        ON sod.sod_nbr = sch.sch_nbr AND sod.sod_line = sch.sch_line
    INNER JOIN [QADEE2798].[dbo].[active_schd_det] schd WITH (NOLOCK)
        ON sch.sch_nbr = schd.schd_nbr AND sch.sch_line = schd.schd_line
    WHERE sod.sod_site = '2798'
      AND sod.sod_status IS NULL
      AND schd.schd_discr_qty > 0
      AND schd.schd_date >= @CurrentDate
),
BOMComponents AS (
    SELECT DISTINCT ps.ps_comp AS ItemNumber
    FROM [QADEE2798].[dbo].[ps_mstr] ps WITH (NOLOCK)
    INNER JOIN DemandItems d ON ps.ps_par = d.ItemNumber
    WHERE ps.ps_end IS NULL
),
AllNeededItems AS (
    SELECT ItemNumber FROM DemandItems
    UNION
    SELECT ItemNumber FROM BOMComponents
),
ActivePOItems AS (
    SELECT DISTINCT pod.pod_part AS ItemNumber
    FROM [QADEE2798].[dbo].[pod_det] pod WITH (NOLOCK)
    WHERE pod.pod_po_site = '2798'
      AND pod.pod_status IS NULL
      AND pod.[pod_end_eff[1]]] > @CurrentDate
)
INSERT INTO #Anomalies (
    ReportType, AnomalyType, Site, ItemNumber, ItemDescription, ItemType,
    Supplier, SupplierName, ScheduleNumber, ScheduleLine, PONumber, POLine,
    Metric1Label, Metric1Value, Metric2Label, Metric2Value, Metric3Label, Metric3Value,
    EarliestDate, LatestDate, Action
)
SELECT 
    'ISSUE' AS ReportType,
    'MISSING_PO_LINE' AS AnomalyType,
    '2798' AS Site,
    n.ItemNumber,
    bc.ItemDescription,
    bc.ItemType,
    pt.pt_vend AS Supplier,
    NULL AS SupplierName,
    NULL AS ScheduleNumber,
    NULL AS ScheduleLine,
    NULL AS PONumber,
    NULL AS POLine,
    'ItemSource' AS Metric1Label,
    CASE WHEN EXISTS (SELECT 1 FROM DemandItems d WHERE d.ItemNumber = n.ItemNumber) THEN 'FG/Direct' ELSE 'Component' END AS Metric1Value,
    NULL,NULL,NULL,NULL,
    NULL AS EarliestDate,
    NULL AS LatestDate,
    'Create active PO line for this component or adjust BOM/schedule if obsolete' AS Action
FROM AllNeededItems n
LEFT JOIN ActivePOItems a ON n.ItemNumber = a.ItemNumber
LEFT JOIN [QADEE2798].[dbo].[pt_mstr] pt WITH (NOLOCK) ON n.ItemNumber = pt.pt_part AND pt.pt_site = '2798'
LEFT JOIN #BomClass bc ON bc.Site = '2798' AND bc.ItemNumber = n.ItemNumber
WHERE a.ItemNumber IS NULL
  AND pt.pt_part_type NOT IN ('xc', 'rc')
  AND ISNULL(bc.ItemType, 'RM') = 'RM';   -- Only flag components

-- ============================================================================
-- ANOMALY 3: Zero or NULL Standard Pack
-- ============================================================================
INSERT INTO #Anomalies (
    ReportType, AnomalyType, Site, ItemNumber, ItemDescription, ItemType,
    Supplier, SupplierName, ScheduleNumber, ScheduleLine, PONumber, POLine,
    Metric1Label, Metric1Value, Metric2Label, Metric2Value, Metric3Label, Metric3Value,
    EarliestDate, LatestDate, Action
)
SELECT 
    'ISSUE' AS ReportType,
    'INVALID_STANDARD_PACK' AS AnomalyType,
    pod.pod_po_site AS Site,
    pod.pod_part AS ItemNumber,
    bc.ItemDescription,
    bc.ItemType,
    po.po_vend AS Supplier,
    ad.ad_name AS SupplierName,
    NULL AS ScheduleNumber,
    NULL AS ScheduleLine,
    pod.pod_nbr AS PONumber,
    pod.pod_line AS POLine,
    'CurrentStandardPack' AS Metric1Label,
    CAST(pod.pod_ord_mult AS NVARCHAR(50)) AS Metric1Value,
    NULL,NULL,NULL,NULL,
    NULL AS EarliestDate,
    NULL AS LatestDate,
    'Set pod_ord_mult to a valid value > 0' AS Action
FROM [QADEE2798].[dbo].[pod_det] pod WITH (NOLOCK)
JOIN [QADEE2798].[dbo].[po_mstr] po WITH (NOLOCK) ON pod.pod_nbr = po.po_nbr
LEFT JOIN [QADEE2798].[dbo].[ad_mstr] ad WITH (NOLOCK) ON po.po_vend = ad.ad_addr
LEFT JOIN #BomClass bc ON bc.Site = pod.pod_po_site AND bc.ItemNumber = pod.pod_part
WHERE pod.pod_po_site = '2798'
  AND pod.pod_status IS NULL
  AND pod.[pod_end_eff[1]]] > @CurrentDate
  AND (pod.pod_ord_mult IS NULL OR pod.pod_ord_mult <= 0);

-- ============================================================================
-- ANOMALY 4: Zero or Negative Transport Days
-- ============================================================================
INSERT INTO #Anomalies (
    ReportType, AnomalyType, Site, ItemNumber, ItemDescription, ItemType,
    Supplier, SupplierName, ScheduleNumber, ScheduleLine, PONumber, POLine,
    Metric1Label, Metric1Value, Metric2Label, Metric2Value, Metric3Label, Metric3Value,
    EarliestDate, LatestDate, Action
)
SELECT 
    'ISSUE' AS ReportType,
    'INVALID_TRANSPORT_DAYS' AS AnomalyType,
    pod.pod_po_site AS Site,
    pod.pod_part AS ItemNumber,
    bc.ItemDescription,
    bc.ItemType,
    po.po_vend AS Supplier,
    ad.ad_name AS SupplierName,
    NULL AS ScheduleNumber,
    NULL AS ScheduleLine,
    pod.pod_nbr AS PONumber,
    pod.pod_line AS POLine,
    'CurrentTransportDays' AS Metric1Label,
    CAST(pod.pod_translt_days AS NVARCHAR(50)) AS Metric1Value,
    NULL,NULL,NULL,NULL,
    NULL AS EarliestDate,
    NULL AS LatestDate,
    'Verify and set pod_translt_days if supplier requires lead time' AS Action
FROM [QADEE2798].[dbo].[pod_det] pod WITH (NOLOCK)
JOIN [QADEE2798].[dbo].[po_mstr] po WITH (NOLOCK) ON pod.pod_nbr = po.po_nbr
LEFT JOIN [QADEE2798].[dbo].[ad_mstr] ad WITH (NOLOCK) ON po.po_vend = ad.ad_addr
LEFT JOIN #BomClass bc ON bc.Site = pod.pod_po_site AND bc.ItemNumber = pod.pod_part
WHERE pod.pod_po_site = '2798'
  AND pod.pod_status IS NULL
  AND pod.[pod_end_eff[1]]] > @CurrentDate
  AND (pod.pod_translt_days IS NULL OR pod.pod_translt_days < 0);

-- ============================================================================
-- ANOMALY 5: Stale PO Releases (Release ID present but PO line closed)
-- ============================================================================
INSERT INTO #Anomalies (
    ReportType, AnomalyType, Site, ItemNumber, ItemDescription, ItemType,
    Supplier, SupplierName, ScheduleNumber, ScheduleLine, PONumber, POLine,
    Metric1Label, Metric1Value, Metric2Label, Metric2Value, Metric3Label, Metric3Value,
    EarliestDate, LatestDate, Action
)
SELECT 
    'ISSUE' AS ReportType,
    'STALE_RELEASE' AS AnomalyType,
    pod.pod_po_site AS Site,
    pod.pod_part AS ItemNumber,
    bc.ItemDescription,
    bc.ItemType,
    po.po_vend AS Supplier,
    ad.ad_name AS SupplierName,
    NULL AS ScheduleNumber,
    NULL AS ScheduleLine,
    pod.pod_nbr AS PONumber,
    pod.pod_line AS POLine,
    'ReleaseID' AS Metric1Label,
    CAST(pod.[pod_curr_rlse_id[1]]] AS NVARCHAR(50)) AS Metric1Value,
    NULL,NULL,NULL,NULL,
    MIN(pod.[pod_end_eff[1]]]) AS EarliestDate,
    MAX(pod.[pod_end_eff[1]]]) AS LatestDate,
    'Clear release ID or reactivate PO line' AS Action
FROM [QADEE2798].[dbo].[pod_det] pod WITH (NOLOCK)
JOIN [QADEE2798].[dbo].[po_mstr] po WITH (NOLOCK) ON pod.pod_nbr = po.po_nbr
LEFT JOIN [QADEE2798].[dbo].[ad_mstr] ad WITH (NOLOCK) ON po.po_vend = ad.ad_addr
LEFT JOIN #BomClass bc ON bc.Site = pod.pod_po_site AND bc.ItemNumber = pod.pod_part
WHERE pod.pod_po_site = '2798'
  AND pod.[pod_end_eff[1]]] < @CurrentDate
  AND pod.[pod_curr_rlse_id[1]]] IS NOT NULL
GROUP BY pod.pod_po_site, pod.pod_part, bc.ItemDescription, bc.ItemType, po.po_vend, ad.ad_name, pod.pod_nbr, pod.pod_line, pod.[pod_curr_rlse_id[1]]];

-- ============================================================================
-- ANOMALY 6: Orphaned Schedule Lines (schedule exists but no active PO)
-- ============================================================================
WITH OpenPOItems AS (
    SELECT DISTINCT pod_part
    FROM [QADEE2798].[dbo].[pod_det] WITH (NOLOCK)
    WHERE pod_po_site = '2798'
      AND pod_status IS NULL
      AND [pod_end_eff[1]]] > @CurrentDate
)
INSERT INTO #Anomalies (
    ReportType, AnomalyType, Site, ItemNumber, ItemDescription, ItemType,
    Supplier, SupplierName, ScheduleNumber, ScheduleLine, PONumber, POLine,
    Metric1Label, Metric1Value, Metric2Label, Metric2Value, Metric3Label, Metric3Value,
    EarliestDate, LatestDate, Action
)
SELECT 
    'ISSUE' AS ReportType,
    'ORPHANED_SCHEDULE' AS AnomalyType,
    sod.sod_site AS Site,
    sod.sod_part AS ItemNumber,
    bc.ItemDescription,
    bc.ItemType,
    pt.pt_vend AS Supplier,
    NULL AS SupplierName,
    sod.sod_nbr AS ScheduleNumber,
    sod.sod_line AS ScheduleLine,
    NULL AS PONumber,
    NULL AS POLine,
    'TotalScheduledQty' AS Metric1Label,
    CAST(SUM(schd.schd_discr_qty) AS NVARCHAR(50)) AS Metric1Value,
    NULL,NULL,NULL,NULL,
    MIN(schd.schd_date) AS EarliestDate,
    MAX(schd.schd_date) AS LatestDate,
    'Create PO line or deactivate schedule' AS Action
FROM [QADEE2798].[dbo].[sod_det] sod WITH (NOLOCK)
INNER JOIN [QADEE2798].[dbo].[sch_mstr] sch WITH (NOLOCK)
    ON sod.sod_nbr = sch.sch_nbr AND sod.sod_line = sch.sch_line
INNER JOIN [QADEE2798].[dbo].[active_schd_det] schd WITH (NOLOCK)
    ON sch.sch_nbr = schd.schd_nbr AND sch.sch_line = schd.schd_line AND sch.sch_rlse_id = schd.schd_rlse_id
LEFT JOIN OpenPOItems po ON sod.sod_part = po.pod_part
LEFT JOIN [QADEE2798].[dbo].[pt_mstr] pt WITH (NOLOCK) ON sod.sod_part = pt.pt_part AND pt.pt_site = sod.sod_site
LEFT JOIN #BomClass bc ON bc.Site = sod.sod_site AND bc.ItemNumber = sod.sod_part
WHERE sod.sod_site = '2798'
  AND sod.sod_status IS NULL
  AND schd.schd_discr_qty > 0
  AND schd.schd_date >= @CurrentDate
  AND po.pod_part IS NULL
GROUP BY sod.sod_site, sod.sod_part, bc.ItemDescription, bc.ItemType, pt.pt_vend, sod.sod_nbr, sod.sod_line;

-- ============================================================================
-- ANOMALY 7: Excessive Safety Stock (> 3 months of average demand)
-- ============================================================================
WITH AvgWeeklyDemand AS (
    SELECT 
        sod.sod_part AS ItemNumber,
        AVG(schd.schd_discr_qty) AS AvgWeeklyQty
    FROM [QADEE2798].[dbo].[sod_det] sod WITH (NOLOCK)
    INNER JOIN [QADEE2798].[dbo].[sch_mstr] sch WITH (NOLOCK)
        ON sod.sod_nbr = sch.sch_nbr AND sod.sod_line = sch.sch_line
    INNER JOIN [QADEE2798].[dbo].[active_schd_det] schd WITH (NOLOCK)
        ON sch.sch_nbr = schd.schd_nbr AND sch.sch_line = schd.schd_line
    WHERE sod.sod_site = '2798'
      AND sod.sod_status IS NULL
      AND schd.schd_discr_qty > 0
    GROUP BY sod.sod_part
)
INSERT INTO #Anomalies (
    ReportType, AnomalyType, Site, ItemNumber, ItemDescription, ItemType,
    Supplier, SupplierName, ScheduleNumber, ScheduleLine, PONumber, POLine,
    Metric1Label, Metric1Value, Metric2Label, Metric2Value, Metric3Label, Metric3Value,
    EarliestDate, LatestDate, Action
)
SELECT 
    'ISSUE' AS ReportType,
    'EXCESSIVE_SAFETY_STOCK' AS AnomalyType,
    pt.pt_site AS Site,
    pt.pt_part AS ItemNumber,
    pt.pt_desc1 AS ItemDescription,
    bc.ItemType,
    pt.pt_vend AS Supplier,
    NULL AS SupplierName,
    NULL AS ScheduleNumber,
    NULL AS ScheduleLine,
    NULL AS PONumber,
    NULL AS POLine,
    'WeeksOfCoverage' AS Metric1Label,
    CAST(ROUND(pt.pt_sfty_stk / d.AvgWeeklyQty, 1) AS NVARCHAR(50)) AS Metric1Value,
    'SafetyStock' AS Metric2Label,
    CAST(pt.pt_sfty_stk AS NVARCHAR(50)) AS Metric2Value,
    'AvgWeeklyQty' AS Metric3Label,
    CAST(d.AvgWeeklyQty AS NVARCHAR(50)) AS Metric3Value,
    NULL AS EarliestDate,
    NULL AS LatestDate,
    'Review and reduce safety stock if excessive' AS Action
FROM [QADEE2798].[dbo].[pt_mstr] pt WITH (NOLOCK)
INNER JOIN AvgWeeklyDemand d ON pt.pt_part = d.ItemNumber
LEFT JOIN #BomClass bc ON bc.Site = pt.pt_site AND bc.ItemNumber = pt.pt_part
WHERE pt.pt_site = '2798'
  AND pt.pt_sfty_stk > 0
  AND d.AvgWeeklyQty > 0
  AND pt.pt_sfty_stk > (d.AvgWeeklyQty * 12);

-- ============================================================================
-- SUMMARY: Anomaly Counts
-- ============================================================================
INSERT INTO #Anomalies (
    ReportType, AnomalyType, Site, ItemNumber, ItemDescription, ItemType,
    Supplier, SupplierName, ScheduleNumber, ScheduleLine, PONumber, POLine,
    Metric1Label, Metric1Value, Metric2Label, Metric2Value, Metric3Label, Metric3Value,
    EarliestDate, LatestDate, Action
)
SELECT 
    'SUMMARY' AS ReportType,
    'ANOMALY_SUMMARY' AS AnomalyType,
    NULL AS Site,
    NULL AS ItemNumber,
    NULL AS ItemDescription,
    NULL AS ItemType,
    NULL AS Supplier,
    NULL AS SupplierName,
    NULL AS ScheduleNumber,
    NULL AS ScheduleLine,
    NULL AS PONumber,
    NULL AS POLine,
    'IssueCount' AS Metric1Label,
    CAST(COUNT(*) AS NVARCHAR(50)) AS Metric1Value,
    NULL,NULL,NULL,NULL,
    NULL AS EarliestDate,
    NULL AS LatestDate,
    NULL AS Action
FROM #Anomalies
WHERE ReportType = 'ISSUE'
GROUP BY AnomalyType;

-- Final combined output
SELECT *
FROM #Anomalies
ORDER BY ReportType DESC, AnomalyType, Site, ItemNumber, Supplier, ScheduleNumber, PONumber;

DROP TABLE IF EXISTS #Anomalies;
DROP TABLE IF EXISTS #BomClass;
