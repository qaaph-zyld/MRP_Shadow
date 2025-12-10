-- ============================================================================
-- ANOMALY DETECTION MODULE
-- Periodic scan to identify data quality issues affecting MRP accuracy
-- Run weekly or after major data changes
-- ============================================================================

SET NOCOUNT ON;

DECLARE @CurrentDate DATE = CAST(GETDATE() AS DATE);

-- ============================================================================
-- ANOMALY 1: Duplicate Active PO Lines for Same Item
-- Multiple active PO lines for the same item = undefined supplier preference
-- ============================================================================
SELECT 
    'DUPLICATE_PO_LINES' AS AnomalyType,
    pod.pod_po_site AS Site,
    pod.pod_part AS ItemNumber,
    COUNT(*) AS ActivePOLineCount,
    STRING_AGG(pod.pod_nbr + '/' + CAST(pod.pod_line AS VARCHAR(10)), ', ') AS POLines,
    STRING_AGG(CAST(po.po_vend AS VARCHAR(20)), ', ') AS Suppliers,
    'Review and close duplicate PO lines or clarify supplier preference' AS Action
FROM [QADEE2798].[dbo].[pod_det] pod WITH (NOLOCK)
JOIN [QADEE2798].[dbo].[po_mstr] po WITH (NOLOCK) ON pod.pod_nbr = po.po_nbr
WHERE pod.pod_po_site = '2798'
  AND pod.pod_status IS NULL
  AND pod.[pod_end_eff[1]]] > @CurrentDate
GROUP BY pod.pod_po_site, pod.pod_part
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC;

-- ============================================================================
-- ANOMALY 2: Items with Customer Demand but No Active PO Line
-- These items cannot be planned by MRP
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
SELECT 
    'MISSING_PO_LINE' AS AnomalyType,
    n.ItemNumber,
    pt.pt_desc1 AS ItemDescription,
    pt.pt_vend AS DefaultSupplier,
    CASE 
        WHEN EXISTS (SELECT 1 FROM DemandItems d WHERE d.ItemNumber = n.ItemNumber) THEN 'FG/Direct'
        ELSE 'Component'
    END AS ItemSource,
    'Create active PO line for this item' AS Action
FROM AllNeededItems n
LEFT JOIN ActivePOItems a ON n.ItemNumber = a.ItemNumber
LEFT JOIN [QADEE2798].[dbo].[pt_mstr] pt WITH (NOLOCK) ON n.ItemNumber = pt.pt_part AND pt.pt_site = '2798'
WHERE a.ItemNumber IS NULL
  AND pt.pt_part_type NOT IN ('xc', 'rc')
ORDER BY ItemSource, n.ItemNumber;

-- ============================================================================
-- ANOMALY 3: Zero or NULL Standard Pack
-- Will cause incorrect planned order sizing
-- ============================================================================
SELECT 
    'INVALID_STANDARD_PACK' AS AnomalyType,
    pod.pod_part AS ItemNumber,
    po.po_vend AS Supplier,
    pod.pod_ord_mult AS CurrentStandardPack,
    pod.pod_nbr AS PONumber,
    pod.pod_line AS POLine,
    'Set pod_ord_mult to a valid value > 0' AS Action
FROM [QADEE2798].[dbo].[pod_det] pod WITH (NOLOCK)
JOIN [QADEE2798].[dbo].[po_mstr] po WITH (NOLOCK) ON pod.pod_nbr = po.po_nbr
WHERE pod.pod_po_site = '2798'
  AND pod.pod_status IS NULL
  AND pod.[pod_end_eff[1]]] > @CurrentDate
  AND (pod.pod_ord_mult IS NULL OR pod.pod_ord_mult <= 0)
ORDER BY pod.pod_part;

-- ============================================================================
-- ANOMALY 4: Zero or Negative Transport Days
-- Will cause incorrect release date calculation
-- ============================================================================
SELECT 
    'INVALID_TRANSPORT_DAYS' AS AnomalyType,
    pod.pod_part AS ItemNumber,
    po.po_vend AS Supplier,
    ad.ad_name AS SupplierName,
    pod.pod_translt_days AS CurrentTransportDays,
    pod.pod_nbr AS PONumber,
    'Verify and set pod_translt_days if supplier requires lead time' AS Action
FROM [QADEE2798].[dbo].[pod_det] pod WITH (NOLOCK)
JOIN [QADEE2798].[dbo].[po_mstr] po WITH (NOLOCK) ON pod.pod_nbr = po.po_nbr
LEFT JOIN [QADEE2798].[dbo].[ad_mstr] ad WITH (NOLOCK) ON po.po_vend = ad.ad_addr
WHERE pod.pod_po_site = '2798'
  AND pod.pod_status IS NULL
  AND pod.[pod_end_eff[1]]] > @CurrentDate
  AND (pod.pod_translt_days IS NULL OR pod.pod_translt_days < 0)
ORDER BY ad.ad_name, pod.pod_part;

-- ============================================================================
-- ANOMALY 5: Stale PO Releases (Release ID present but PO line closed)
-- Could cause confusion or data integrity issues
-- ============================================================================
SELECT 
    'STALE_RELEASE' AS AnomalyType,
    pod.pod_part AS ItemNumber,
    po.po_vend AS Supplier,
    pod.pod_nbr AS PONumber,
    pod.pod_line AS POLine,
    pod.[pod_curr_rlse_id[1]]] AS ReleaseID,
    pod.[pod_end_eff[1]]] AS EndEffDate,
    'Clear release ID or reactivate PO line' AS Action
FROM [QADEE2798].[dbo].[pod_det] pod WITH (NOLOCK)
JOIN [QADEE2798].[dbo].[po_mstr] po WITH (NOLOCK) ON pod.pod_nbr = po.po_nbr
WHERE pod.pod_po_site = '2798'
  AND pod.[pod_end_eff[1]]] < @CurrentDate
  AND pod.[pod_curr_rlse_id[1]]] IS NOT NULL
ORDER BY pod.[pod_end_eff[1]]] DESC;

-- ============================================================================
-- ANOMALY 6: Orphaned Schedule Lines (schedule exists but no active PO)
-- ============================================================================
SELECT 
    'ORPHANED_SCHEDULE' AS AnomalyType,
    sod.sod_part AS ItemNumber,
    sod.sod_nbr AS ScheduleNumber,
    sod.sod_line AS ScheduleLine,
    SUM(schd.schd_discr_qty) AS TotalScheduledQty,
    MIN(schd.schd_date) AS EarliestDate,
    'Create PO line or deactivate schedule' AS Action
FROM [QADEE2798].[dbo].[sod_det] sod WITH (NOLOCK)
INNER JOIN [QADEE2798].[dbo].[sch_mstr] sch WITH (NOLOCK)
    ON sod.sod_nbr = sch.sch_nbr AND sod.sod_line = sch.sch_line
INNER JOIN [QADEE2798].[dbo].[active_schd_det] schd WITH (NOLOCK)
    ON sch.sch_nbr = schd.schd_nbr AND sch.sch_line = schd.schd_line AND sch.sch_rlse_id = schd.schd_rlse_id
LEFT JOIN (
    SELECT DISTINCT pod_part
    FROM [QADEE2798].[dbo].[pod_det] WITH (NOLOCK)
    WHERE pod_po_site = '2798'
      AND pod_status IS NULL
      AND [pod_end_eff[1]]] > @CurrentDate
) po ON sod.sod_part = po.pod_part
WHERE sod.sod_site = '2798'
  AND sod.sod_status IS NULL
  AND schd.schd_discr_qty > 0
  AND schd.schd_date >= @CurrentDate
  AND po.pod_part IS NULL
GROUP BY sod.sod_part, sod.sod_nbr, sod.sod_line
ORDER BY SUM(schd.schd_discr_qty) DESC;

-- ============================================================================
-- ANOMALY 7: Excessive Safety Stock (> 3 months of average demand)
-- May indicate obsolete or overstated parameters
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
SELECT 
    'EXCESSIVE_SAFETY_STOCK' AS AnomalyType,
    pt.pt_part AS ItemNumber,
    pt.pt_desc1 AS ItemDescription,
    pt.pt_sfty_stk AS SafetyStock,
    d.AvgWeeklyQty,
    CASE WHEN d.AvgWeeklyQty > 0 
         THEN ROUND(pt.pt_sfty_stk / d.AvgWeeklyQty, 1)
         ELSE NULL 
    END AS WeeksOfCoverage,
    'Review and reduce safety stock if excessive' AS Action
FROM [QADEE2798].[dbo].[pt_mstr] pt WITH (NOLOCK)
INNER JOIN AvgWeeklyDemand d ON pt.pt_part = d.ItemNumber
WHERE pt.pt_site = '2798'
  AND pt.pt_sfty_stk > 0
  AND d.AvgWeeklyQty > 0
  AND pt.pt_sfty_stk > (d.AvgWeeklyQty * 12)  -- > 12 weeks = 3 months
ORDER BY pt.pt_sfty_stk / d.AvgWeeklyQty DESC;

-- ============================================================================
-- SUMMARY: Anomaly Counts
-- ============================================================================
SELECT 'ANOMALY_SUMMARY' AS ReportType, AnomalyType, COUNT(*) AS IssueCount
FROM (
    SELECT 'DUPLICATE_PO_LINES' AS AnomalyType FROM [QADEE2798].[dbo].[pod_det] pod
    JOIN [QADEE2798].[dbo].[po_mstr] po ON pod.pod_nbr = po.po_nbr
    WHERE pod.pod_po_site = '2798' AND pod.pod_status IS NULL AND pod.[pod_end_eff[1]]] > @CurrentDate
    GROUP BY pod.pod_part HAVING COUNT(*) > 1
    
    UNION ALL
    
    SELECT 'INVALID_STANDARD_PACK' FROM [QADEE2798].[dbo].[pod_det]
    WHERE pod_po_site = '2798' AND pod_status IS NULL AND [pod_end_eff[1]]] > @CurrentDate
      AND (pod_ord_mult IS NULL OR pod_ord_mult <= 0)
    
    UNION ALL
    
    SELECT 'INVALID_TRANSPORT_DAYS' FROM [QADEE2798].[dbo].[pod_det]
    WHERE pod_po_site = '2798' AND pod_status IS NULL AND [pod_end_eff[1]]] > @CurrentDate
      AND (pod_translt_days IS NULL OR pod_translt_days < 0)
) anomalies
GROUP BY AnomalyType
ORDER BY IssueCount DESC;
