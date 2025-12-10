SET DATEFIRST 1;
SET NOCOUNT ON;

-- ============================================================================
-- PERFORMANCE-OPTIMIZED MRP CALCULATION
-- Key Changes:
-- 1. Pre-filter items with demand BEFORE BOM explosion
-- 2. Materialize BOM classification once (eliminate repeated EXISTS)
-- 3. Use temp tables for large intermediates
-- 4. Index temp tables strategically
-- 5. Reduce Cartesian products
-- ============================================================================

DECLARE @CurrentDate DATE = CAST(GETDATE() AS DATE);
DECLARE @HorizonWeeks INT = 52;     -- planning horizon in weeks (~26 weeks + 6 months)
DECLARE @BOMDepthLimit INT = 5;     -- max BOM levels
DECLARE @DebugItem VARCHAR(50) = NULL;  -- e.g. '108363-1M_C' for single-item debug; NULL = all items

-- ============================================================================
-- STEP 1: PRE-MATERIALIZE BOM CLASSIFICATION (Eliminate 4 EXISTS per item)
-- ============================================================================
IF OBJECT_ID('tempdb..#BOMClassification') IS NOT NULL DROP TABLE #BOMClassification;

SELECT 
    ps_par AS ItemNumber,
    1 AS IsParent
INTO #BOMClassification
FROM [QADEE2798].[dbo].[ps_mstr] WITH (NOLOCK)
WHERE ps_end IS NULL
GROUP BY ps_par;

CREATE CLUSTERED INDEX IX_BOMClass ON #BOMClassification(ItemNumber);

IF OBJECT_ID('tempdb..#BOMComponents') IS NOT NULL DROP TABLE #BOMComponents;

SELECT 
    ps_comp AS ItemNumber,
    1 AS IsComponent
INTO #BOMComponents
FROM [QADEE2798].[dbo].[ps_mstr] WITH (NOLOCK)
WHERE ps_end IS NULL
GROUP BY ps_comp;

CREATE CLUSTERED INDEX IX_BOMComp ON #BOMComponents(ItemNumber);

-- ============================================================================
-- STEP 2: ITEM MASTER WITH SINGLE-PASS CLASSIFICATION
-- ============================================================================
IF OBJECT_ID('tempdb..#ItemMaster') IS NOT NULL DROP TABLE #ItemMaster;

SELECT 
    pt.pt_site AS Site,
    pt.pt_part AS ItemNumber,
    pt.pt_desc1 AS ItemDescription,
    ISNULL(pt.pt_sfty_stk, 0) AS SafetyStock,
    pt.pt_vend AS DefaultSupplier,
    pt.pt_buyer AS Planner,
    CASE
        WHEN p.ItemNumber IS NOT NULL AND c.ItemNumber IS NOT NULL THEN 'SFG'
        WHEN p.ItemNumber IS NOT NULL THEN 'FG'
        WHEN c.ItemNumber IS NOT NULL THEN 'RM'
        ELSE 'No BOM'
    END AS ItemType
INTO #ItemMaster
FROM [QADEE2798].[dbo].[pt_mstr] pt WITH (NOLOCK)
LEFT JOIN #BOMClassification p ON pt.pt_part = p.ItemNumber
LEFT JOIN #BOMComponents c ON pt.pt_part = c.ItemNumber
WHERE pt.pt_site = '2798'
  AND pt.pt_part_type NOT IN ('xc', 'rc')
  AND pt.pt_status NOT IN ('OBS', 'EPIC')
  AND (@DebugItem IS NULL OR pt.pt_part = @DebugItem);

CREATE CLUSTERED INDEX IX_IM ON #ItemMaster(Site, ItemNumber);

-- ============================================================================
-- STEP 3: CUSTOMER DEMAND - EARLY AGGREGATION
-- ============================================================================
IF OBJECT_ID('tempdb..#ScheduleData') IS NOT NULL DROP TABLE #ScheduleData;

SELECT
    sod.sod_site AS Site,
    sod.sod_part AS ParentItem,
    schd.schd_date AS DemandDate,
    DATEPART(YEAR, schd.schd_date) AS DemandYear,
    DATEPART(WEEK, schd.schd_date) AS DemandWeek,
    SUM(CAST(schd.schd_discr_qty AS DECIMAL(18,4))) AS DiscreteQty,
    CASE 
        WHEN schd.schd_date < @CurrentDate THEN 'Past_Due'
        WHEN DATEDIFF(WEEK, @CurrentDate, schd.schd_date) = 0 THEN 'Current_Week'
        WHEN DATEDIFF(WEEK, @CurrentDate, schd.schd_date) BETWEEN 1 AND 26 
            THEN 'Week_' + CAST(DATEDIFF(WEEK, @CurrentDate, schd.schd_date) AS VARCHAR(2))
        ELSE 'Future'
    END AS DemandBucketType
INTO #ScheduleData
FROM [QADEE2798].[dbo].[sod_det] sod WITH (NOLOCK)
INNER JOIN [QADEE2798].[dbo].[sch_mstr] sch WITH (NOLOCK)
    ON sod.sod_nbr = sch.sch_nbr 
   AND sod.sod_line = sch.sch_line
INNER JOIN [QADEE2798].[dbo].[active_schd_det] schd WITH (NOLOCK)
    ON sch.sch_nbr = schd.schd_nbr
   AND sch.sch_line = schd.schd_line
   AND sch.sch_rlse_id = schd.schd_rlse_id
WHERE sod.sod_site = '2798'
  AND sod.sod_status IS NULL
  AND (sod.[sod_end_eff[1]]] IS NULL OR sod.[sod_end_eff[1]]] > @CurrentDate)
  AND sch.sch_eff_end IS NULL
  AND schd.schd_discr_qty > 0
  AND schd.schd_date <= DATEADD(WEEK, @HorizonWeeks, @CurrentDate)
  AND (@DebugItem IS NULL OR sod.sod_part = @DebugItem)
GROUP BY 
    sod.sod_site, 
    sod.sod_part, 
    schd.schd_date,
    DATEPART(YEAR, schd.schd_date),
    DATEPART(WEEK, schd.schd_date);

CREATE CLUSTERED INDEX IX_SD ON #ScheduleData(Site, ParentItem, DemandYear, DemandWeek);

-- ============================================================================
-- STEP 4: BOM EXPLOSION - ONLY FOR ITEMS WITH DEMAND
-- ============================================================================
IF OBJECT_ID('tempdb..#ActiveParents') IS NOT NULL DROP TABLE #ActiveParents;

SELECT DISTINCT ParentItem
INTO #ActiveParents
FROM #ScheduleData;

CREATE CLUSTERED INDEX IX_AP ON #ActiveParents(ParentItem);

-- BOM structure filtered to active parents only
IF OBJECT_ID('tempdb..#BOMStructure') IS NOT NULL DROP TABLE #BOMStructure;

SELECT 
    ps.ps_par AS ParentItem,
    ps.ps_comp AS ComponentItem,
    CAST(ps.ps_qty_per AS DECIMAL(18,6)) AS QtyPer
INTO #BOMStructure
FROM [QADEE2798].[dbo].[ps_mstr] ps WITH (NOLOCK)
INNER JOIN #ActiveParents ap ON ps.ps_par = ap.ParentItem
WHERE ps.ps_end IS NULL
  AND ps.ps_qty_per > 0;

CREATE CLUSTERED INDEX IX_BOM ON #BOMStructure(ParentItem, ComponentItem);

-- Recursive BOM explosion
IF OBJECT_ID('tempdb..#BOMHierarchy') IS NOT NULL DROP TABLE #BOMHierarchy;

WITH BOMRecursive AS (
    SELECT 
        b.ParentItem AS RootParent,
        b.ComponentItem,
        b.QtyPer AS CumulativeQtyPer,
        0 AS BOMLevel
    FROM #BOMStructure b
    
    UNION ALL
    
    SELECT 
        h.RootParent,
        b.ComponentItem,
        CAST(h.CumulativeQtyPer * b.QtyPer AS DECIMAL(18,6)) AS CumulativeQtyPer,
        h.BOMLevel + 1
    FROM #BOMStructure b
    INNER JOIN BOMRecursive h ON b.ParentItem = h.ComponentItem
    WHERE h.BOMLevel < @BOMDepthLimit
)
SELECT 
    RootParent,
    ComponentItem,
    CumulativeQtyPer
INTO #BOMHierarchy
FROM BOMRecursive
WHERE NOT EXISTS (
    SELECT 1 FROM #BOMStructure b2 
    WHERE b2.ParentItem = BOMRecursive.ComponentItem
)
OPTION (MAXRECURSION 100);

CREATE CLUSTERED INDEX IX_BH ON #BOMHierarchy(RootParent, ComponentItem);

-- ============================================================================
-- STEP 5: EXPLODED DEMAND - AGGREGATE ONCE
-- ============================================================================
IF OBJECT_ID('tempdb..#ExplodedDemand') IS NOT NULL DROP TABLE #ExplodedDemand;

SELECT
    Site,
    ItemNumber,
    DemandYear,
    DemandWeek,
    DemandBucketType,
    SUM(GrossRequirement) AS GrossRequirement
INTO #ExplodedDemand
FROM (
    -- Direct FG demand
    SELECT
        s.Site,
        s.ParentItem AS ItemNumber,
        s.DemandYear,
        s.DemandWeek,
        s.DemandBucketType,
        s.DiscreteQty AS GrossRequirement
    FROM #ScheduleData s
    
    UNION ALL
    
    -- Component demand via BOM
    SELECT
        s.Site,
        lc.ComponentItem AS ItemNumber,
        s.DemandYear,
        s.DemandWeek,
        s.DemandBucketType,
        s.DiscreteQty * lc.CumulativeQtyPer AS GrossRequirement
    FROM #ScheduleData s
    INNER JOIN #BOMHierarchy lc ON s.ParentItem = lc.RootParent
) combined
GROUP BY Site, ItemNumber, DemandYear, DemandWeek, DemandBucketType;

CREATE CLUSTERED INDEX IX_ED ON #ExplodedDemand(Site, ItemNumber, DemandYear, DemandWeek);

-- ============================================================================
-- STEP 6: SUPPLY SOURCES
-- ============================================================================
IF OBJECT_ID('tempdb..#Inventory') IS NOT NULL DROP TABLE #Inventory;

SELECT
    inv.in_site AS Site,
    inv.in_part AS ItemNumber,
    inv.in_qty_oh AS NettableQty
INTO #Inventory
FROM [QADEE2798].[dbo].[15] inv WITH (NOLOCK)
WHERE inv.in_site = '2798'
  AND inv.in_qty_oh > 0
  AND (@DebugItem IS NULL OR inv.in_part = @DebugItem);

CREATE CLUSTERED INDEX IX_INV ON #Inventory(Site, ItemNumber);

-- PO Parameters
IF OBJECT_ID('tempdb..#POParams') IS NOT NULL DROP TABLE #POParams;

SELECT
    pod.pod_po_site AS Site,
    pod.pod_part AS ItemNumber,
    pm.po_vend AS Supplier,
    ad.ad_name AS SupplierName,
    ISNULL(pod.pod_ord_mult, 1) AS StandardPack,
    ISNULL(pod.pod_translt_days, 0) AS TransportDays
INTO #POParams
FROM (
    SELECT 
        pod_po_site, 
        pod_part, 
        pod_nbr, 
        pod_ord_mult, 
        pod_translt_days,
        ROW_NUMBER() OVER (
            PARTITION BY pod_po_site, pod_part
            ORDER BY 
                CASE WHEN [pod_end_eff[1]]] > @CurrentDate THEN 0 ELSE 1 END,
                [pod_end_eff[1]]] DESC
        ) AS RN
    FROM [QADEE2798].[dbo].[pod_det] WITH (NOLOCK)
    WHERE pod_po_site = '2798'
      AND (@DebugItem IS NULL OR pod_part = @DebugItem)
) pod
INNER JOIN [QADEE2798].[dbo].[po_mstr] pm WITH (NOLOCK) 
    ON pod.pod_nbr = pm.po_nbr
LEFT JOIN [QADEE2798].[dbo].[ad_mstr] ad WITH (NOLOCK) 
    ON pm.po_vend = ad.ad_addr
WHERE pod.RN = 1;

CREATE CLUSTERED INDEX IX_PO ON #POParams(Site, ItemNumber);

-- Scheduled Receipts
IF OBJECT_ID('tempdb..#ScheduledReceipts') IS NOT NULL DROP TABLE #ScheduledReceipts;

SELECT
    pod.pod_po_site AS Site,
    pod.pod_part AS ItemNumber,
    DATEPART(YEAR, pod.pod_due_date) AS DueYear,
    DATEPART(WEEK, pod.pod_due_date) AS DueWeek,
    SUM(CAST(pod.pod_qty_ord - ISNULL(pod.pod_qty_rcvd, 0) AS DECIMAL(18,4))) AS ScheduledReceiptQty
INTO #ScheduledReceipts
FROM [QADEE2798].[dbo].[pod_det] pod WITH (NOLOCK)
WHERE pod.pod_po_site = '2798'
  AND pod.pod_status IS NULL
  AND pod.[pod_end_eff[1]]] > @CurrentDate
  AND (pod.pod_qty_ord - ISNULL(pod.pod_qty_rcvd, 0)) > 0
  AND pod.pod_due_date <= DATEADD(WEEK, @HorizonWeeks, @CurrentDate)
  AND (@DebugItem IS NULL OR pod.pod_part = @DebugItem)
GROUP BY 
    pod.pod_po_site, 
    pod.pod_part, 
    DATEPART(YEAR, pod.pod_due_date), 
    DATEPART(WEEK, pod.pod_due_date);

CREATE CLUSTERED INDEX IX_SR ON #ScheduledReceipts(Site, ItemNumber, DueYear, DueWeek);

-- ============================================================================
-- STEP 7: WEEK REFERENCE (Generate once, filter in final join)
-- ============================================================================
IF OBJECT_ID('tempdb..#WeekReference') IS NOT NULL DROP TABLE #WeekReference;

SELECT 
    WeekOffset, 
    DemandBucketType, 
    DATEPART(YEAR, DATEADD(WEEK, WeekOffset, @CurrentDate)) AS DueDateYear,
    DATEPART(WEEK, DATEADD(WEEK, WeekOffset, @CurrentDate)) AS DueDateWeek,
    DATEADD(DAY, 
        (8 - DATEPART(WEEKDAY, DATEADD(WEEK, WeekOffset, @CurrentDate))) % 7 - 6,
        DATEADD(WEEK, WeekOffset, @CurrentDate)
    ) AS WeekStartDate,
    DATEPART(WEEK, @CurrentDate) AS CurrentWeekNumber,
    DATEPART(YEAR, @CurrentDate) AS CurrentYear
INTO #WeekReference
FROM (VALUES 
    (0,  'Current_Week'),
    (1,  'Week_1'),  (2,  'Week_2'),  (3,  'Week_3'),  (4,  'Week_4'),
    (5,  'Week_5'),  (6,  'Week_6'),  (7,  'Week_7'),  (8,  'Week_8'),
    (9,  'Week_9'),  (10, 'Week_10'), (11, 'Week_11'), (12, 'Week_12'),
    (13, 'Week_13'), (14, 'Week_14'), (15, 'Week_15'), (16, 'Week_16'),
    (17, 'Week_17'), (18, 'Week_18'), (19, 'Week_19'), (20, 'Week_20'),
    (21, 'Week_21'), (22, 'Week_22'), (23, 'Week_23'), (24, 'Week_24'),
    (25, 'Week_25'), (26, 'Week_26')
) AS W(WeekOffset, DemandBucketType);

-- ============================================================================
-- STEP 8: BUILD FINAL GRID (Only for items with demand/supply)
-- ============================================================================
IF OBJECT_ID('tempdb..#ItemWeekGrid') IS NOT NULL DROP TABLE #ItemWeekGrid;

SELECT
    im.Site,
    im.ItemNumber,
    im.ItemDescription,
    im.ItemType,
    im.SafetyStock,
    im.Planner,
    COALESCE(po.Supplier, im.DefaultSupplier) AS Supplier,
    po.SupplierName,
    ISNULL(po.StandardPack, 1) AS StandardPack,
    ISNULL(po.TransportDays, 0) AS TransportDays,
    wr.DemandBucketType,
    wr.DueDateYear,
    wr.DueDateWeek,
    wr.WeekStartDate,
    wr.WeekOffset,
    ISNULL(inv.NettableQty, 0) AS OnHandQty,
    ISNULL(d.GrossRequirement, 0) AS GrossRequirement,
    ISNULL(sr.ScheduledReceiptQty, 0) AS ScheduledReceiptQty,
    ROW_NUMBER() OVER (
        PARTITION BY im.Site, im.ItemNumber
        ORDER BY wr.WeekStartDate
    ) AS RowNum
INTO #ItemWeekGrid
FROM #ItemMaster im
INNER JOIN (
    SELECT DISTINCT Site, ItemNumber FROM #ExplodedDemand
    UNION
    SELECT DISTINCT Site, ItemNumber FROM #ScheduledReceipts
    UNION
    SELECT DISTINCT Site, ItemNumber FROM #Inventory
) active ON im.Site = active.Site AND im.ItemNumber = active.ItemNumber
CROSS JOIN #WeekReference wr
LEFT JOIN #Inventory inv 
    ON im.Site = inv.Site AND im.ItemNumber = inv.ItemNumber
LEFT JOIN #ExplodedDemand d 
    ON im.Site = d.Site 
   AND im.ItemNumber = d.ItemNumber 
   AND wr.DemandBucketType = d.DemandBucketType
LEFT JOIN #ScheduledReceipts sr
    ON im.Site = sr.Site 
   AND im.ItemNumber = sr.ItemNumber 
   AND wr.DueDateYear = sr.DueYear 
   AND wr.DueDateWeek = sr.DueWeek
LEFT JOIN #POParams po
    ON im.Site = po.Site AND im.ItemNumber = po.ItemNumber
WHERE ISNULL(d.GrossRequirement, 0) > 0
   OR ISNULL(sr.ScheduledReceiptQty, 0) > 0
   OR ISNULL(inv.NettableQty, 0) > 0;

CREATE CLUSTERED INDEX IX_IWG ON #ItemWeekGrid(Site, ItemNumber, RowNum);

-- ============================================================================
-- STEP 9: MRP RECURSIVE CALCULATION
-- ============================================================================
IF OBJECT_ID('tempdb..#MRPResults') IS NOT NULL DROP TABLE #MRPResults;

WITH MRPRecursive AS (
    -- Anchor: First week
    SELECT
        Site, ItemNumber, ItemDescription, ItemType, SafetyStock, Planner,
        Supplier, SupplierName, StandardPack, TransportDays,
        DemandBucketType, DueDateYear, DueDateWeek, WeekStartDate, WeekOffset,
        GrossRequirement, ScheduledReceiptQty, RowNum,
        
        CAST(OnHandQty AS DECIMAL(18,2)) AS ProjectedOnHandBefore,
        
        CAST(
            CASE 
                WHEN (OnHandQty + ScheduledReceiptQty - GrossRequirement) < SafetyStock
                THEN SafetyStock - (OnHandQty + ScheduledReceiptQty - GrossRequirement)
                ELSE 0
            END AS DECIMAL(18,2)
        ) AS NetRequirement,
        
        CAST(
            CASE 
                WHEN (OnHandQty + ScheduledReceiptQty - GrossRequirement) < SafetyStock
                     AND StandardPack > 1
                THEN CEILING(
                    (SafetyStock - (OnHandQty + ScheduledReceiptQty - GrossRequirement)) 
                    / CAST(StandardPack AS DECIMAL(18,6))
                ) * StandardPack
                WHEN (OnHandQty + ScheduledReceiptQty - GrossRequirement) < SafetyStock
                THEN SafetyStock - (OnHandQty + ScheduledReceiptQty - GrossRequirement)
                ELSE 0
            END AS DECIMAL(18,2)
        ) AS PlannedOrderQty,
        
        CAST(
            OnHandQty + ScheduledReceiptQty - GrossRequirement +
            CASE 
                WHEN (OnHandQty + ScheduledReceiptQty - GrossRequirement) < SafetyStock
                     AND StandardPack > 1
                THEN CEILING(
                    (SafetyStock - (OnHandQty + ScheduledReceiptQty - GrossRequirement)) 
                    / CAST(StandardPack AS DECIMAL(18,6))
                ) * StandardPack
                WHEN (OnHandQty + ScheduledReceiptQty - GrossRequirement) < SafetyStock
                THEN SafetyStock - (OnHandQty + ScheduledReceiptQty - GrossRequirement)
                ELSE 0
            END AS DECIMAL(18,2)
        ) AS ProjectedOnHandAfter
    FROM #ItemWeekGrid
    WHERE RowNum = 1
    
    UNION ALL
    
    -- Recursive: Subsequent weeks
    SELECT
        n.Site, n.ItemNumber, n.ItemDescription, n.ItemType, n.SafetyStock, n.Planner,
        n.Supplier, n.SupplierName, n.StandardPack, n.TransportDays,
        n.DemandBucketType, n.DueDateYear, n.DueDateWeek, n.WeekStartDate, n.WeekOffset,
        n.GrossRequirement, n.ScheduledReceiptQty, n.RowNum,
        
        r.ProjectedOnHandAfter AS ProjectedOnHandBefore,
        
        CAST(
            CASE 
                WHEN (r.ProjectedOnHandAfter + n.ScheduledReceiptQty - n.GrossRequirement) < n.SafetyStock
                THEN n.SafetyStock - (r.ProjectedOnHandAfter + n.ScheduledReceiptQty - n.GrossRequirement)
                ELSE 0
            END AS DECIMAL(18,2)
        ) AS NetRequirement,
        
        CAST(
            CASE 
                WHEN (r.ProjectedOnHandAfter + n.ScheduledReceiptQty - n.GrossRequirement) < n.SafetyStock
                     AND n.StandardPack > 1
                THEN CEILING(
                    (n.SafetyStock - (r.ProjectedOnHandAfter + n.ScheduledReceiptQty - n.GrossRequirement)) 
                    / CAST(n.StandardPack AS DECIMAL(18,6))
                ) * n.StandardPack
                WHEN (r.ProjectedOnHandAfter + n.ScheduledReceiptQty - n.GrossRequirement) < n.SafetyStock
                THEN n.SafetyStock - (r.ProjectedOnHandAfter + n.ScheduledReceiptQty - n.GrossRequirement)
                ELSE 0
            END AS DECIMAL(18,2)
        ) AS PlannedOrderQty,
        
        CAST(
            r.ProjectedOnHandAfter + n.ScheduledReceiptQty - n.GrossRequirement +
            CASE 
                WHEN (r.ProjectedOnHandAfter + n.ScheduledReceiptQty - n.GrossRequirement) < n.SafetyStock
                     AND n.StandardPack > 1
                THEN CEILING(
                    (n.SafetyStock - (r.ProjectedOnHandAfter + n.ScheduledReceiptQty - n.GrossRequirement)) 
                    / CAST(n.StandardPack AS DECIMAL(18,6))
                ) * n.StandardPack
                WHEN (r.ProjectedOnHandAfter + n.ScheduledReceiptQty - n.GrossRequirement) < n.SafetyStock
                THEN n.SafetyStock - (r.ProjectedOnHandAfter + n.ScheduledReceiptQty - n.GrossRequirement)
                ELSE 0
            END AS DECIMAL(18,2)
        ) AS ProjectedOnHandAfter
    FROM #ItemWeekGrid n
    INNER JOIN MRPRecursive r
        ON n.Site = r.Site
       AND n.ItemNumber = r.ItemNumber
       AND n.RowNum = r.RowNum + 1
    WHERE n.RowNum <= 60  -- Hard limit: allow up to 60 buckets per item
)
SELECT *
INTO #MRPResults
FROM MRPRecursive
OPTION (MAXRECURSION 100);

-- ============================================================================
-- FINAL OUTPUT
-- ============================================================================
SELECT
    Site,
    ItemNumber,
    ItemDescription,
    ItemType,
    Supplier,
    SupplierName,
    DueDateYear,
    DueDateWeek,
    WeekStartDate AS PlannedOrderDueDate,
    DATEADD(DAY, -TransportDays, WeekStartDate) AS PlannedOrderReleaseDate,
    DemandBucketType,
    GrossRequirement,
    ScheduledReceiptQty AS ScheduledReceipts,
    ProjectedOnHandBefore,
    NetRequirement,
    PlannedOrderQty,
    ProjectedOnHandAfter,
    SafetyStock,
    StandardPack,
    TransportDays,
    Planner
FROM #MRPResults
WHERE GrossRequirement > 0 
   OR PlannedOrderQty > 0 
   OR ScheduledReceiptQty > 0
ORDER BY 
    Site,
    ItemNumber,
    DueDateYear,
    DueDateWeek;

-- Cleanup
DROP TABLE IF EXISTS #BOMClassification, #BOMComponents, #ItemMaster, 
                     #ScheduleData, #ActiveParents, #BOMStructure, #BOMHierarchy,
                     #ExplodedDemand, #Inventory, #POParams, #ScheduledReceipts,
                     #WeekReference, #ItemWeekGrid, #MRPResults;