/*
================================================================================
SHADOW MRP - SUPPORTING VIEWS
================================================================================
Purpose:
  Creates reusable views that feed the main rebuild procedure:
  1. v_ShadowMRP_WeekReference      - Week calendar and bucket mapping
  2. v_ShadowMRP_BOMClassification  - FG/SFG/RM classification per item
  3. v_ShadowMRP_ComponentDemand    - BOM-exploded demand by week
  4. v_ShadowMRP_Inventory          - Current on-hand by item/site
  5. v_ShadowMRP_POParams           - Supplier, standard pack, transport days
  6. v_ShadowMRP_OpenSupply         - Open PO/WO scheduled receipts

Dependencies:
  - [QADEE2798].[dbo].[pt_mstr]
  - [QADEE2798].[dbo].[ps_mstr]
  - [QADEE2798].[dbo].[sod_det]
  - [QADEE2798].[dbo].[sch_mstr]
  - [QADEE2798].[dbo].[active_schd_det]
  - [QADEE2798].[dbo].[in_mstr] / [15]
  - [QADEE2798].[dbo].[pod_det]
  - [QADEE2798].[dbo].[po_mstr]
  - [QADEE2798].[dbo].[ad_mstr]
================================================================================
*/

SET DATEFIRST 1; -- Monday = first day of week (ISO standard)
GO

--------------------------------------------------------------------------------
-- 1. WEEK REFERENCE VIEW
--------------------------------------------------------------------------------
IF OBJECT_ID('dbo.v_ShadowMRP_WeekReference', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_WeekReference;
GO

CREATE VIEW dbo.v_ShadowMRP_WeekReference AS
WITH WeekNumbers AS (
    SELECT 0 AS WeekOffset UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL 
    SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL 
    SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10 UNION ALL
    SELECT 11 UNION ALL SELECT 12 UNION ALL SELECT 13 UNION ALL SELECT 14 UNION ALL
    SELECT 15 UNION ALL SELECT 16 UNION ALL SELECT 17 UNION ALL SELECT 18 UNION ALL
    SELECT 19 UNION ALL SELECT 20 UNION ALL SELECT 21 UNION ALL SELECT 22 UNION ALL
    SELECT 23 UNION ALL SELECT 24 UNION ALL SELECT 25 UNION ALL SELECT 26
)
SELECT
    w.WeekOffset,
    CASE 
        WHEN w.WeekOffset = 0 THEN 'Current_Week'
        WHEN w.WeekOffset BETWEEN 1 AND 8 THEN 'Week_' + CAST(w.WeekOffset AS VARCHAR(2))
        ELSE 'Future'
    END AS DemandBucketType,
    DATEPART(YEAR, DATEADD(WEEK, w.WeekOffset, GETDATE())) AS DueDateYear,
    DATEPART(WEEK, DATEADD(WEEK, w.WeekOffset, GETDATE())) AS DueDateWeek,
    -- Monday of each week
    DATEADD(DAY, 
        (8 - DATEPART(WEEKDAY, DATEADD(WEEK, w.WeekOffset, GETDATE()))) % 7 - 6,
        CAST(DATEADD(WEEK, w.WeekOffset, GETDATE()) AS DATE)
    ) AS WeekStartDate,
    DATEPART(WEEK, GETDATE()) AS CurrentWeekNumber,
    DATEPART(YEAR, GETDATE()) AS CurrentYear
FROM WeekNumbers w;
GO

--------------------------------------------------------------------------------
-- 2. BOM CLASSIFICATION VIEW (FG/SFG/RM)
--------------------------------------------------------------------------------
IF OBJECT_ID('dbo.v_ShadowMRP_BOMClassification', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_BOMClassification;
GO

CREATE VIEW dbo.v_ShadowMRP_BOMClassification AS
WITH ParentItems AS (
    SELECT DISTINCT 
        '2798' AS Site,
        [ps_par] AS ItemNumber,
        1 AS IsParent
    FROM [QADEE2798].[dbo].[ps_mstr]
    WHERE [ps_end] IS NULL
),
ChildItems AS (
    SELECT DISTINCT 
        '2798' AS Site,
        [ps_comp] AS ItemNumber,
        1 AS IsChild
    FROM [QADEE2798].[dbo].[ps_mstr]
    WHERE [ps_end] IS NULL
),
AllItems AS (
    SELECT 
        pt.[pt_site] AS Site,
        pt.[pt_part] AS ItemNumber,
        pt.[pt_desc1] AS ItemDescription,
        pt.[pt_sfty_stk] AS SafetyStock,
        pt.[pt_vend] AS DefaultSupplier,
        pt.[pt_buyer] AS Planner,
        pt.[pt__chr02] AS ItemTypeMaster,
        pt.[pt_prod_line] AS ProdLine,
        pt.[pt_group] AS ItemGroup,
        pt.[pt_status] AS ItemStatus
    FROM [QADEE2798].[dbo].[pt_mstr] pt
    WHERE pt.[pt_part_type] NOT IN ('xc', 'rc')
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
FROM AllItems a
LEFT JOIN ParentItems p ON a.Site = p.Site AND a.ItemNumber = p.ItemNumber
LEFT JOIN ChildItems c ON a.Site = c.Site AND a.ItemNumber = c.ItemNumber;
GO

--------------------------------------------------------------------------------
-- 3. COMPONENT DEMAND VIEW (BOM-exploded weekly demand)
--------------------------------------------------------------------------------
IF OBJECT_ID('dbo.v_ShadowMRP_ComponentDemand', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_ComponentDemand;
GO

CREATE VIEW dbo.v_ShadowMRP_ComponentDemand AS
WITH 
-- Active sales order lines
ActiveSOD AS (
    SELECT
        sod.[sod_site] AS Site,
        sod.[sod_part] AS ParentItem,
        sod.[sod_nbr] AS SONumber,
        sod.[sod_line] AS SOLine,
        sod.[sod_curr_rlse_id[1]]] AS ReleaseID
    FROM [QADEE2798].[dbo].[sod_det] sod
    WHERE sod.[sod_status] IS NULL
      AND (sod.[sod_end_eff[1]]] IS NULL OR sod.[sod_end_eff[1]]] > CAST(GETDATE() AS DATE))
),
-- Schedule details with weekly bucketing
ScheduleData AS (
    SELECT
        a.Site,
        a.ParentItem,
        schd.[schd_date] AS DemandDate,
        DATEPART(YEAR, schd.[schd_date]) AS DemandYear,
        DATEPART(WEEK, schd.[schd_date]) AS DemandWeek,
        CAST(schd.[schd_discr_qty] AS DECIMAL(18,4)) AS DiscreteQty,
        CASE 
            WHEN schd.[schd_date] < CAST(GETDATE() AS DATE) THEN 'Past_Due'
            WHEN DATEDIFF(WEEK, GETDATE(), schd.[schd_date]) = 0 THEN 'Current_Week'
            WHEN DATEDIFF(WEEK, GETDATE(), schd.[schd_date]) BETWEEN 1 AND 8 THEN 
                'Week_' + CAST(DATEDIFF(WEEK, GETDATE(), schd.[schd_date]) AS VARCHAR(2))
            ELSE 'Future'
        END AS DemandBucketType
    FROM ActiveSOD a
    INNER JOIN [QADEE2798].[dbo].[sch_mstr] sch 
        ON a.SONumber = sch.[sch_nbr] 
        AND a.SOLine = sch.[sch_line]
    INNER JOIN [QADEE2798].[dbo].[active_schd_det] schd
        ON sch.[sch_nbr] = schd.[schd_nbr]
        AND sch.[sch_line] = schd.[schd_line]
        AND sch.[sch_rlse_id] = schd.[schd_rlse_id]
    WHERE sch.[sch_eff_end] IS NULL
      AND schd.[schd_discr_qty] > 0
),
-- BOM structure (multi-level)
BOMStructure AS (
    SELECT 
        [ps_par] AS ParentItem,
        [ps_comp] AS ComponentItem,
        [ps_qty_per] AS QtyPer
    FROM [QADEE2798].[dbo].[ps_mstr]
    WHERE [ps_end] IS NULL
),
-- Recursive BOM explosion
BOMHierarchy AS (
    -- Level 0: FG items (parents that are not children)
    SELECT 
        b.ParentItem AS RootParent,
        b.ParentItem AS CurrentParent,
        b.ComponentItem,
        b.QtyPer AS CumulativeQtyPer,
        0 AS BOMLevel
    FROM BOMStructure b
    WHERE b.ParentItem NOT IN (SELECT ComponentItem FROM BOMStructure)
    
    UNION ALL
    
    -- Recurse through SFG levels
    SELECT 
        h.RootParent,
        b.ParentItem AS CurrentParent,
        b.ComponentItem,
        h.CumulativeQtyPer * b.QtyPer AS CumulativeQtyPer,
        h.BOMLevel + 1
    FROM BOMStructure b
    INNER JOIN BOMHierarchy h ON b.ParentItem = h.ComponentItem
    WHERE h.BOMLevel < 10  -- Prevent infinite recursion
),
-- Final RM-level components (leaf nodes)
LeafComponents AS (
    SELECT 
        h.RootParent,
        h.ComponentItem,
        h.CumulativeQtyPer
    FROM BOMHierarchy h
    WHERE h.ComponentItem NOT IN (SELECT ParentItem FROM BOMStructure)
),
-- Explode FG demand to component demand
ExplodedDemand AS (
    -- Direct FG demand
    SELECT
        s.Site,
        s.ParentItem AS ItemNumber,
        'FG' AS DemandSource,
        s.DemandYear,
        s.DemandWeek,
        s.DemandBucketType,
        SUM(s.DiscreteQty) AS GrossRequirement
    FROM ScheduleData s
    GROUP BY s.Site, s.ParentItem, s.DemandYear, s.DemandWeek, s.DemandBucketType
    
    UNION ALL
    
    -- Component demand from BOM explosion
    SELECT
        s.Site,
        lc.ComponentItem AS ItemNumber,
        'BOM_Explosion' AS DemandSource,
        s.DemandYear,
        s.DemandWeek,
        s.DemandBucketType,
        SUM(s.DiscreteQty * lc.CumulativeQtyPer) AS GrossRequirement
    FROM ScheduleData s
    INNER JOIN LeafComponents lc ON s.ParentItem = lc.RootParent
    GROUP BY s.Site, lc.ComponentItem, s.DemandYear, s.DemandWeek, s.DemandBucketType
)
SELECT
    Site,
    ItemNumber,
    DemandSource,
    DemandYear,
    DemandWeek,
    DemandBucketType,
    SUM(GrossRequirement) AS GrossRequirement
FROM ExplodedDemand
GROUP BY Site, ItemNumber, DemandSource, DemandYear, DemandWeek, DemandBucketType;
GO

--------------------------------------------------------------------------------
-- 4. INVENTORY VIEW
--------------------------------------------------------------------------------
IF OBJECT_ID('dbo.v_ShadowMRP_Inventory', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_Inventory;
GO

CREATE VIEW dbo.v_ShadowMRP_Inventory AS
SELECT
    [in_site] AS Site,
    [in_part] AS ItemNumber,
    [in_qty_oh] AS NettableQty,
    [in_qty_nonet] AS NonNettableQty,
    [in_qty_oh] + [in_qty_nonet] AS TotalOnHand
FROM [QADEE2798].[dbo].[in_mstr];
GO

--------------------------------------------------------------------------------
-- 5. PO PARAMETERS VIEW
--------------------------------------------------------------------------------
IF OBJECT_ID('dbo.v_ShadowMRP_POParams', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_POParams;
GO

CREATE VIEW dbo.v_ShadowMRP_POParams AS
WITH RankedPO AS (
    SELECT
        pod.[pod_po_site] AS Site,
        pod.[pod_part] AS ItemNumber,
        pm.[po_vend] AS Supplier,
        ad.[ad_name] AS SupplierName,
        pod.[pod_ord_mult] AS StandardPack,
        pod.[pod_translt_days] AS TransportDays,
        pod.[pod_sftylt_days] AS SafetyLeadDays,
        pod.[pod_firm_days] AS FirmDays,
        pod.[pod_end_eff[1]]] AS EndEffectiveDate,
        ROW_NUMBER() OVER (
            PARTITION BY pod.[pod_po_site], pod.[pod_part]
            ORDER BY 
                CASE WHEN pod.[pod_end_eff[1]]] > GETDATE() THEN 0 ELSE 1 END,
                pod.[pod_end_eff[1]]] DESC
        ) AS RN
    FROM [QADEE2798].[dbo].[pod_det] pod
    INNER JOIN [QADEE2798].[dbo].[po_mstr] pm ON pod.[pod_nbr] = pm.[po_nbr]
    LEFT JOIN [QADEE2798].[dbo].[ad_mstr] ad ON pm.[po_vend] = ad.[ad_addr]
)
SELECT
    Site,
    ItemNumber,
    Supplier,
    SupplierName,
    ISNULL(StandardPack, 1) AS StandardPack,
    ISNULL(TransportDays, 0) AS TransportDays,
    ISNULL(SafetyLeadDays, 0) AS SafetyLeadDays,
    ISNULL(FirmDays, 0) AS FirmDays
FROM RankedPO
WHERE RN = 1;  -- Take most relevant PO per item
GO

--------------------------------------------------------------------------------
-- 6. OPEN SUPPLY VIEW (Scheduled Receipts from PO/WO)
--------------------------------------------------------------------------------
IF OBJECT_ID('dbo.v_ShadowMRP_OpenSupply', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_OpenSupply;
GO

CREATE VIEW dbo.v_ShadowMRP_OpenSupply AS
-- Open PO releases (simplified: assumes pod_det has open quantities)
-- In a full implementation, you'd pull from prd_det for WOs as well
SELECT
    pod.[pod_po_site] AS Site,
    pod.[pod_part] AS ItemNumber,
    'PO' AS SupplyType,
    pod.[pod_nbr] AS OrderNumber,
    pod.[pod_line] AS OrderLine,
    DATEPART(YEAR, pod.[pod_due_date]) AS DueYear,
    DATEPART(WEEK, pod.[pod_due_date]) AS DueWeek,
    pod.[pod_due_date] AS DueDate,
    CAST(pod.[pod_qty_ord] - ISNULL(pod.[pod_qty_rcvd], 0) AS DECIMAL(18,4)) AS OpenQty
FROM [QADEE2798].[dbo].[pod_det] pod
WHERE pod.[pod_status] IS NULL  -- Open PO lines
  AND pod.[pod_end_eff[1]]] > GETDATE()
  AND (pod.[pod_qty_ord] - ISNULL(pod.[pod_qty_rcvd], 0)) > 0;
GO

PRINT 'All supporting views created successfully.';
GO
