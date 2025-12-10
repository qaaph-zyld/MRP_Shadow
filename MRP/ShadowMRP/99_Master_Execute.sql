/*
================================================================================
SHADOW MRP - MASTER EXECUTION SCRIPT
================================================================================
Purpose:
  Single script to deploy and run the complete Shadow MRP pipeline.
  
Execution Order:
  1. Create ShadowMRP_PlannedOrders table
  2. Create supporting views
  3. Create rebuild procedure
  4. Create validation views
  5. Execute initial rebuild

Usage:
  Run this entire script to set up and populate the shadow MRP.
  
  For subsequent refreshes (after EDI/demand changes):
    EXEC dbo.usp_Rebuild_ShadowMRP_PlannedOrders;

Output Views (after execution):
  - v_ShadowMRP_ScheduleReleases   : Ready-to-confirm planned releases
  - v_ShadowMRP_SupplierSchedule   : Aggregated supplier schedules
  - v_ShadowMRP_Summary            : Executive summary by type/bucket
  - v_ShadowMRP_ValidationVsQAD    : Comparison with official mrp_det
================================================================================
*/

PRINT '============================================================';
PRINT 'SHADOW MRP PIPELINE - DEPLOYMENT STARTED';
PRINT 'Timestamp: ' + CONVERT(VARCHAR(30), GETDATE(), 121);
PRINT '============================================================';
GO

-- ============================================================================
-- STEP 1: Create target table
-- ============================================================================
PRINT '';
PRINT 'Step 1: Creating ShadowMRP_PlannedOrders table...';
GO

IF OBJECT_ID('dbo.ShadowMRP_PlannedOrders', 'U') IS NOT NULL
    DROP TABLE dbo.ShadowMRP_PlannedOrders;
GO

CREATE TABLE dbo.ShadowMRP_PlannedOrders (
    PlannedOrderID          INT IDENTITY(1,1) PRIMARY KEY,
    Site                    VARCHAR(10)     NOT NULL,
    ItemNumber              VARCHAR(50)     NOT NULL,
    ItemType                VARCHAR(10)     NULL,
    Supplier                VARCHAR(50)     NULL,
    SupplierName            VARCHAR(100)    NULL,
    DueDateYear             INT             NOT NULL,
    DueDateWeek             INT             NOT NULL,
    PlannedOrderDueDate     DATE            NOT NULL,
    PlannedOrderReleaseDate DATE            NULL,
    DemandBucketType        VARCHAR(20)     NOT NULL,
    GrossRequirement        DECIMAL(18,4)   NOT NULL DEFAULT 0,
    ScheduledReceipts       DECIMAL(18,4)   NOT NULL DEFAULT 0,
    ProjectedOnHandBefore   DECIMAL(18,4)   NOT NULL DEFAULT 0,
    NetRequirement          DECIMAL(18,4)   NOT NULL DEFAULT 0,
    PlannedOrderQty         DECIMAL(18,4)   NOT NULL DEFAULT 0,
    ProjectedOnHandAfter    DECIMAL(18,4)   NOT NULL DEFAULT 0,
    SafetyStock             DECIMAL(18,4)   NULL,
    StandardPack            DECIMAL(18,4)   NULL,
    TransportDays           INT             NULL,
    PlanRunTimestamp        DATETIME2       NOT NULL,
    SourceFlag              VARCHAR(50)     NULL
);

CREATE NONCLUSTERED INDEX IX_ShadowMRP_Site_Item 
    ON dbo.ShadowMRP_PlannedOrders (Site, ItemNumber);
CREATE NONCLUSTERED INDEX IX_ShadowMRP_DueWeek 
    ON dbo.ShadowMRP_PlannedOrders (DueDateYear, DueDateWeek);
CREATE NONCLUSTERED INDEX IX_ShadowMRP_Supplier 
    ON dbo.ShadowMRP_PlannedOrders (Supplier) WHERE Supplier IS NOT NULL;
CREATE NONCLUSTERED INDEX IX_ShadowMRP_ItemType 
    ON dbo.ShadowMRP_PlannedOrders (ItemType);

PRINT 'Table created successfully.';
GO

-- ============================================================================
-- STEP 2: Create supporting views
-- ============================================================================
PRINT '';
PRINT 'Step 2: Creating supporting views...';
GO

SET DATEFIRST 1;
GO

-- Week Reference View
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
    DATEADD(DAY, 
        (8 - DATEPART(WEEKDAY, DATEADD(WEEK, w.WeekOffset, GETDATE()))) % 7 - 6,
        CAST(DATEADD(WEEK, w.WeekOffset, GETDATE()) AS DATE)
    ) AS WeekStartDate,
    DATEPART(WEEK, GETDATE()) AS CurrentWeekNumber,
    DATEPART(YEAR, GETDATE()) AS CurrentYear
FROM WeekNumbers w;
GO

-- BOM Classification View
IF OBJECT_ID('dbo.v_ShadowMRP_BOMClassification', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_BOMClassification;
GO

CREATE VIEW dbo.v_ShadowMRP_BOMClassification AS
WITH ParentItems AS (
    SELECT DISTINCT '2798' AS Site, [ps_par] AS ItemNumber, 1 AS IsParent
    FROM [QADEE2798].[dbo].[ps_mstr] WHERE [ps_end] IS NULL
),
ChildItems AS (
    SELECT DISTINCT '2798' AS Site, [ps_comp] AS ItemNumber, 1 AS IsChild
    FROM [QADEE2798].[dbo].[ps_mstr] WHERE [ps_end] IS NULL
),
AllItems AS (
    SELECT pt.[pt_site] AS Site, pt.[pt_part] AS ItemNumber, pt.[pt_desc1] AS ItemDescription,
           pt.[pt_sfty_stk] AS SafetyStock, pt.[pt_vend] AS DefaultSupplier,
           pt.[pt_buyer] AS Planner, pt.[pt__chr02] AS ItemTypeMaster,
           pt.[pt_prod_line] AS ProdLine, pt.[pt_group] AS ItemGroup, pt.[pt_status] AS ItemStatus
    FROM [QADEE2798].[dbo].[pt_mstr] pt WHERE pt.[pt_part_type] NOT IN ('xc', 'rc')
)
SELECT a.Site, a.ItemNumber, a.ItemDescription, a.SafetyStock, a.DefaultSupplier,
       a.Planner, a.ItemTypeMaster, a.ProdLine, a.ItemGroup, a.ItemStatus,
       ISNULL(p.IsParent, 0) AS IsParent, ISNULL(c.IsChild, 0) AS IsChild,
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

-- Component Demand View
IF OBJECT_ID('dbo.v_ShadowMRP_ComponentDemand', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_ComponentDemand;
GO

CREATE VIEW dbo.v_ShadowMRP_ComponentDemand AS
WITH 
ActiveSOD AS (
    SELECT sod.[sod_site] AS Site, sod.[sod_part] AS ParentItem,
           sod.[sod_nbr] AS SONumber, sod.[sod_line] AS SOLine,
           sod.[sod_curr_rlse_id[1]]] AS ReleaseID
    FROM [QADEE2798].[dbo].[sod_det] sod
    WHERE sod.[sod_status] IS NULL
      AND (sod.[sod_end_eff[1]]] IS NULL OR sod.[sod_end_eff[1]]] > CAST(GETDATE() AS DATE))
),
ScheduleData AS (
    SELECT a.Site, a.ParentItem, schd.[schd_date] AS DemandDate,
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
        ON a.SONumber = sch.[sch_nbr] AND a.SOLine = sch.[sch_line]
    INNER JOIN [QADEE2798].[dbo].[active_schd_det] schd
        ON sch.[sch_nbr] = schd.[schd_nbr] AND sch.[sch_line] = schd.[schd_line]
        AND sch.[sch_rlse_id] = schd.[schd_rlse_id]
    WHERE sch.[sch_eff_end] IS NULL AND schd.[schd_discr_qty] > 0
),
BOMStructure AS (
    SELECT [ps_par] AS ParentItem, [ps_comp] AS ComponentItem, [ps_qty_per] AS QtyPer
    FROM [QADEE2798].[dbo].[ps_mstr] WHERE [ps_end] IS NULL
),
BOMHierarchy AS (
    SELECT b.ParentItem AS RootParent, b.ParentItem AS CurrentParent,
           b.ComponentItem, b.QtyPer AS CumulativeQtyPer, 0 AS BOMLevel
    FROM BOMStructure b
    WHERE b.ParentItem NOT IN (SELECT ComponentItem FROM BOMStructure)
    UNION ALL
    SELECT h.RootParent, b.ParentItem AS CurrentParent, b.ComponentItem,
           h.CumulativeQtyPer * b.QtyPer AS CumulativeQtyPer, h.BOMLevel + 1
    FROM BOMStructure b
    INNER JOIN BOMHierarchy h ON b.ParentItem = h.ComponentItem
    WHERE h.BOMLevel < 10
),
LeafComponents AS (
    SELECT h.RootParent, h.ComponentItem, h.CumulativeQtyPer
    FROM BOMHierarchy h
    WHERE h.ComponentItem NOT IN (SELECT ParentItem FROM BOMStructure)
),
ExplodedDemand AS (
    SELECT s.Site, s.ParentItem AS ItemNumber, 'FG' AS DemandSource,
           s.DemandYear, s.DemandWeek, s.DemandBucketType, SUM(s.DiscreteQty) AS GrossRequirement
    FROM ScheduleData s
    GROUP BY s.Site, s.ParentItem, s.DemandYear, s.DemandWeek, s.DemandBucketType
    UNION ALL
    SELECT s.Site, lc.ComponentItem AS ItemNumber, 'BOM_Explosion' AS DemandSource,
           s.DemandYear, s.DemandWeek, s.DemandBucketType,
           SUM(s.DiscreteQty * lc.CumulativeQtyPer) AS GrossRequirement
    FROM ScheduleData s
    INNER JOIN LeafComponents lc ON s.ParentItem = lc.RootParent
    GROUP BY s.Site, lc.ComponentItem, s.DemandYear, s.DemandWeek, s.DemandBucketType
)
SELECT Site, ItemNumber, DemandSource, DemandYear, DemandWeek, DemandBucketType,
       SUM(GrossRequirement) AS GrossRequirement
FROM ExplodedDemand
GROUP BY Site, ItemNumber, DemandSource, DemandYear, DemandWeek, DemandBucketType;
GO

-- Inventory View
IF OBJECT_ID('dbo.v_ShadowMRP_Inventory', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_Inventory;
GO

CREATE VIEW dbo.v_ShadowMRP_Inventory AS
SELECT [in_site] AS Site, [in_part] AS ItemNumber, [in_qty_oh] AS NettableQty,
       [in_qty_nonet] AS NonNettableQty, [in_qty_oh] + [in_qty_nonet] AS TotalOnHand
FROM [QADEE2798].[dbo].[in_mstr];
GO

-- PO Parameters View
IF OBJECT_ID('dbo.v_ShadowMRP_POParams', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_POParams;
GO

CREATE VIEW dbo.v_ShadowMRP_POParams AS
WITH RankedPO AS (
    SELECT pod.[pod_po_site] AS Site, pod.[pod_part] AS ItemNumber,
           pm.[po_vend] AS Supplier, ad.[ad_name] AS SupplierName,
           pod.[pod_ord_mult] AS StandardPack, pod.[pod_translt_days] AS TransportDays,
           pod.[pod_sftylt_days] AS SafetyLeadDays, pod.[pod_firm_days] AS FirmDays,
           pod.[pod_end_eff[1]]] AS EndEffectiveDate,
           ROW_NUMBER() OVER (PARTITION BY pod.[pod_po_site], pod.[pod_part]
               ORDER BY CASE WHEN pod.[pod_end_eff[1]]] > GETDATE() THEN 0 ELSE 1 END,
                        pod.[pod_end_eff[1]]] DESC) AS RN
    FROM [QADEE2798].[dbo].[pod_det] pod
    INNER JOIN [QADEE2798].[dbo].[po_mstr] pm ON pod.[pod_nbr] = pm.[po_nbr]
    LEFT JOIN [QADEE2798].[dbo].[ad_mstr] ad ON pm.[po_vend] = ad.[ad_addr]
)
SELECT Site, ItemNumber, Supplier, SupplierName,
       ISNULL(StandardPack, 1) AS StandardPack, ISNULL(TransportDays, 0) AS TransportDays,
       ISNULL(SafetyLeadDays, 0) AS SafetyLeadDays, ISNULL(FirmDays, 0) AS FirmDays
FROM RankedPO WHERE RN = 1;
GO

-- Open Supply View
IF OBJECT_ID('dbo.v_ShadowMRP_OpenSupply', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_OpenSupply;
GO

CREATE VIEW dbo.v_ShadowMRP_OpenSupply AS
SELECT pod.[pod_po_site] AS Site, pod.[pod_part] AS ItemNumber, 'PO' AS SupplyType,
       pod.[pod_nbr] AS OrderNumber, pod.[pod_line] AS OrderLine,
       DATEPART(YEAR, pod.[pod_due_date]) AS DueYear,
       DATEPART(WEEK, pod.[pod_due_date]) AS DueWeek,
       pod.[pod_due_date] AS DueDate,
       CAST(pod.[pod_qty_ord] - ISNULL(pod.[pod_qty_rcvd], 0) AS DECIMAL(18,4)) AS OpenQty
FROM [QADEE2798].[dbo].[pod_det] pod
WHERE pod.[pod_status] IS NULL AND pod.[pod_end_eff[1]]] > GETDATE()
  AND (pod.[pod_qty_ord] - ISNULL(pod.[pod_qty_rcvd], 0)) > 0;
GO

PRINT 'Supporting views created successfully.';
GO

-- ============================================================================
-- STEP 3: Create rebuild procedure
-- ============================================================================
PRINT '';
PRINT 'Step 3: Creating rebuild procedure...';
GO

IF OBJECT_ID('dbo.usp_Rebuild_ShadowMRP_PlannedOrders', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_Rebuild_ShadowMRP_PlannedOrders;
GO

CREATE PROCEDURE dbo.usp_Rebuild_ShadowMRP_PlannedOrders
AS
BEGIN
    SET NOCOUNT ON;
    SET DATEFIRST 1;

    DECLARE @RunTimestamp DATETIME2 = SYSDATETIME();
    DECLARE @RowsInserted INT = 0;

    BEGIN TRY
        TRUNCATE TABLE dbo.ShadowMRP_PlannedOrders;

        ;WITH 
        WeekCalendar AS (
            SELECT WeekOffset, DemandBucketType, DueDateYear, DueDateWeek, WeekStartDate
            FROM dbo.v_ShadowMRP_WeekReference
        ),
        AllBuckets AS (
            SELECT -1 AS WeekOffset, 'Past_Due' AS DemandBucketType, 
                   DATEPART(YEAR, GETDATE()) AS DueDateYear, 0 AS DueDateWeek,
                   DATEADD(DAY, -7, CAST(GETDATE() AS DATE)) AS WeekStartDate
            UNION ALL SELECT * FROM WeekCalendar
        ),
        ItemMaster AS (
            SELECT Site, ItemNumber, ItemDescription, ItemType,
                   ISNULL(SafetyStock, 0) AS SafetyStock, DefaultSupplier, Planner
            FROM dbo.v_ShadowMRP_BOMClassification
            WHERE ItemStatus NOT IN ('OBS', 'EPIC')
        ),
        DemandByWeek AS (
            SELECT Site, ItemNumber, DemandYear, DemandWeek, DemandBucketType,
                   SUM(GrossRequirement) AS GrossRequirement
            FROM dbo.v_ShadowMRP_ComponentDemand
            GROUP BY Site, ItemNumber, DemandYear, DemandWeek, DemandBucketType
        ),
        CurrentInventory AS (
            SELECT Site, ItemNumber, NettableQty AS OnHandQty FROM dbo.v_ShadowMRP_Inventory
        ),
        POParams AS (
            SELECT Site, ItemNumber, Supplier, SupplierName, StandardPack, TransportDays
            FROM dbo.v_ShadowMRP_POParams
        ),
        ScheduledReceiptsByWeek AS (
            SELECT Site, ItemNumber, DueYear, DueWeek, SUM(OpenQty) AS ScheduledReceiptQty
            FROM dbo.v_ShadowMRP_OpenSupply
            GROUP BY Site, ItemNumber, DueYear, DueWeek
        ),
        ItemWeekGrid AS (
            SELECT im.Site, im.ItemNumber, im.ItemDescription, im.ItemType, im.SafetyStock, im.Planner,
                   COALESCE(po.Supplier, im.DefaultSupplier) AS Supplier, po.SupplierName,
                   ISNULL(po.StandardPack, 1) AS StandardPack, ISNULL(po.TransportDays, 0) AS TransportDays,
                   b.WeekOffset, b.DemandBucketType, b.DueDateYear, b.DueDateWeek, b.WeekStartDate,
                   ISNULL(inv.OnHandQty, 0) AS OnHandQty,
                   ISNULL(d.GrossRequirement, 0) AS GrossRequirement,
                   ISNULL(sr.ScheduledReceiptQty, 0) AS ScheduledReceiptQty
            FROM ItemMaster im
            CROSS JOIN AllBuckets b
            LEFT JOIN CurrentInventory inv ON im.Site = inv.Site AND im.ItemNumber = inv.ItemNumber
            LEFT JOIN DemandByWeek d ON im.Site = d.Site AND im.ItemNumber = d.ItemNumber 
                                    AND b.DemandBucketType = d.DemandBucketType
            LEFT JOIN ScheduledReceiptsByWeek sr ON im.Site = sr.Site AND im.ItemNumber = sr.ItemNumber 
                                                AND b.DueDateYear = sr.DueYear AND b.DueDateWeek = sr.DueWeek
            LEFT JOIN POParams po ON im.Site = po.Site AND im.ItemNumber = po.ItemNumber
            WHERE ISNULL(d.GrossRequirement, 0) > 0 OR ISNULL(sr.ScheduledReceiptQty, 0) > 0
        ),
        MRPCalculation AS (
            SELECT g.*, 
                   g.OnHandQty + SUM(g.ScheduledReceiptQty) OVER (PARTITION BY g.Site, g.ItemNumber 
                       ORDER BY g.WeekOffset ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                   - SUM(g.GrossRequirement) OVER (PARTITION BY g.Site, g.ItemNumber 
                       ORDER BY g.WeekOffset ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS ProjectedBeforeDemand,
                   SUM(g.GrossRequirement) OVER (PARTITION BY g.Site, g.ItemNumber 
                       ORDER BY g.WeekOffset ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeDemand,
                   SUM(g.ScheduledReceiptQty) OVER (PARTITION BY g.Site, g.ItemNumber 
                       ORDER BY g.WeekOffset ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeReceipts
            FROM ItemWeekGrid g
        ),
        PlannedOrderCalc AS (
            SELECT m.*, m.OnHandQty + m.CumulativeReceipts - ISNULL(m.CumulativeDemand, 0) + m.GrossRequirement AS ProjectedOnHandBefore,
                   CASE WHEN (m.OnHandQty + m.CumulativeReceipts - m.CumulativeDemand) < m.SafetyStock
                        THEN m.SafetyStock - (m.OnHandQty + m.CumulativeReceipts - m.CumulativeDemand) ELSE 0 END AS RawNetRequirement
            FROM MRPCalculation m
        ),
        FinalPlannedOrders AS (
            SELECT p.*,
                   CASE WHEN p.RawNetRequirement > 0 AND p.StandardPack > 0
                        THEN CEILING(p.RawNetRequirement / p.StandardPack) * p.StandardPack
                        WHEN p.RawNetRequirement > 0 THEN p.RawNetRequirement ELSE 0 END AS PlannedOrderQty,
                   p.ProjectedOnHandBefore + 
                       CASE WHEN p.RawNetRequirement > 0 AND p.StandardPack > 0
                            THEN CEILING(p.RawNetRequirement / p.StandardPack) * p.StandardPack
                            WHEN p.RawNetRequirement > 0 THEN p.RawNetRequirement ELSE 0 END AS ProjectedOnHandAfter,
                   DATEADD(DAY, -p.TransportDays, p.WeekStartDate) AS PlannedOrderReleaseDate
            FROM PlannedOrderCalc p
        )
        INSERT INTO dbo.ShadowMRP_PlannedOrders (
            Site, ItemNumber, ItemType, Supplier, SupplierName, DueDateYear, DueDateWeek,
            PlannedOrderDueDate, PlannedOrderReleaseDate, DemandBucketType,
            GrossRequirement, ScheduledReceipts, ProjectedOnHandBefore, NetRequirement,
            PlannedOrderQty, ProjectedOnHandAfter, SafetyStock, StandardPack, TransportDays,
            PlanRunTimestamp, SourceFlag
        )
        SELECT f.Site, f.ItemNumber, f.ItemType, f.Supplier, f.SupplierName, f.DueDateYear, f.DueDateWeek,
               f.WeekStartDate, f.PlannedOrderReleaseDate, f.DemandBucketType,
               f.GrossRequirement, f.ScheduledReceiptQty, f.ProjectedOnHandBefore, f.RawNetRequirement,
               f.PlannedOrderQty, f.ProjectedOnHandAfter, f.SafetyStock, f.StandardPack, f.TransportDays,
               @RunTimestamp, CASE WHEN f.ItemType = 'FG' THEN 'Direct_Demand' ELSE 'BOM_Explosion' END
        FROM FinalPlannedOrders f
        WHERE f.GrossRequirement > 0 OR f.PlannedOrderQty > 0 OR f.ScheduledReceiptQty > 0;

        SET @RowsInserted = @@ROWCOUNT;
        PRINT 'Shadow MRP rebuild completed. Rows inserted: ' + CAST(@RowsInserted AS VARCHAR(20));

    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH
END;
GO

PRINT 'Rebuild procedure created successfully.';
GO

-- ============================================================================
-- STEP 4: Create validation and reporting views
-- ============================================================================
PRINT '';
PRINT 'Step 4: Creating validation and reporting views...';
GO

-- Schedule Releases View
IF OBJECT_ID('dbo.v_ShadowMRP_ScheduleReleases', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_ScheduleReleases;
GO

CREATE VIEW dbo.v_ShadowMRP_ScheduleReleases AS
SELECT po.Site, po.ItemNumber, bc.ItemDescription, po.ItemType, po.Supplier, po.SupplierName,
       bc.Planner, po.DemandBucketType, po.DueDateYear, po.DueDateWeek,
       po.PlannedOrderDueDate, po.PlannedOrderReleaseDate,
       po.GrossRequirement, po.ScheduledReceipts, po.NetRequirement, po.PlannedOrderQty,
       po.SafetyStock, po.StandardPack, po.TransportDays,
       po.ProjectedOnHandBefore, po.ProjectedOnHandAfter,
       CASE WHEN po.PlannedOrderReleaseDate <= CAST(GETDATE() AS DATE) THEN 'RELEASE NOW'
            WHEN po.PlannedOrderReleaseDate <= DATEADD(DAY, 7, GETDATE()) THEN 'RELEASE THIS WEEK'
            WHEN po.PlannedOrderReleaseDate <= DATEADD(DAY, 14, GETDATE()) THEN 'RELEASE NEXT WEEK'
            ELSE 'FUTURE' END AS ReleaseUrgency,
       CASE WHEN po.ProjectedOnHandAfter < 0 THEN 'SHORTAGE'
            WHEN po.ProjectedOnHandAfter < po.SafetyStock THEN 'BELOW_SAFETY'
            ELSE 'OK' END AS CoverageStatus,
       po.PlanRunTimestamp, po.SourceFlag
FROM dbo.ShadowMRP_PlannedOrders po
LEFT JOIN dbo.v_ShadowMRP_BOMClassification bc ON po.Site = bc.Site AND po.ItemNumber = bc.ItemNumber
WHERE po.PlannedOrderQty > 0 OR po.GrossRequirement > 0;
GO

-- Summary View
IF OBJECT_ID('dbo.v_ShadowMRP_Summary', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_Summary;
GO

CREATE VIEW dbo.v_ShadowMRP_Summary AS
SELECT Site, ItemType, DemandBucketType, COUNT(DISTINCT ItemNumber) AS ItemCount,
       SUM(GrossRequirement) AS TotalGrossRequirement,
       SUM(ScheduledReceipts) AS TotalScheduledReceipts,
       SUM(NetRequirement) AS TotalNetRequirement,
       SUM(PlannedOrderQty) AS TotalPlannedOrderQty,
       SUM(CASE WHEN ProjectedOnHandAfter < 0 THEN 1 ELSE 0 END) AS ShortageCount,
       SUM(CASE WHEN ProjectedOnHandAfter < SafetyStock AND ProjectedOnHandAfter >= 0 THEN 1 ELSE 0 END) AS BelowSafetyCount,
       MAX(PlanRunTimestamp) AS LastRunTimestamp
FROM dbo.ShadowMRP_PlannedOrders
GROUP BY Site, ItemType, DemandBucketType;
GO

-- Supplier Schedule View
IF OBJECT_ID('dbo.v_ShadowMRP_SupplierSchedule', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_SupplierSchedule;
GO

CREATE VIEW dbo.v_ShadowMRP_SupplierSchedule AS
SELECT po.Site, po.Supplier, po.SupplierName, po.ItemNumber, bc.ItemDescription,
       po.DueDateYear, po.DueDateWeek, po.PlannedOrderDueDate, po.PlannedOrderReleaseDate,
       SUM(po.GrossRequirement) AS TotalRequirement, SUM(po.PlannedOrderQty) AS TotalPlannedQty,
       po.StandardPack, po.TransportDays,
       SUM(SUM(po.PlannedOrderQty)) OVER (PARTITION BY po.Site, po.Supplier, po.ItemNumber 
           ORDER BY po.DueDateYear, po.DueDateWeek) AS CumulativePlannedQty,
       MAX(po.PlanRunTimestamp) AS PlanRunTimestamp
FROM dbo.ShadowMRP_PlannedOrders po
LEFT JOIN dbo.v_ShadowMRP_BOMClassification bc ON po.Site = bc.Site AND po.ItemNumber = bc.ItemNumber
WHERE po.ItemType = 'RM' AND po.Supplier IS NOT NULL
GROUP BY po.Site, po.Supplier, po.SupplierName, po.ItemNumber, bc.ItemDescription,
         po.DueDateYear, po.DueDateWeek, po.PlannedOrderDueDate, po.PlannedOrderReleaseDate,
         po.StandardPack, po.TransportDays;
GO

PRINT 'Validation and reporting views created successfully.';
GO

-- ============================================================================
-- STEP 5: Execute initial rebuild
-- ============================================================================
PRINT '';
PRINT 'Step 5: Executing initial Shadow MRP rebuild...';
GO

EXEC dbo.usp_Rebuild_ShadowMRP_PlannedOrders;
GO

-- ============================================================================
-- COMPLETION SUMMARY
-- ============================================================================
PRINT '';
PRINT '============================================================';
PRINT 'SHADOW MRP PIPELINE - DEPLOYMENT COMPLETED';
PRINT '============================================================';
PRINT '';
PRINT 'Objects created:';
PRINT '  - Table:     dbo.ShadowMRP_PlannedOrders';
PRINT '  - Procedure: dbo.usp_Rebuild_ShadowMRP_PlannedOrders';
PRINT '  - Views:     dbo.v_ShadowMRP_WeekReference';
PRINT '               dbo.v_ShadowMRP_BOMClassification';
PRINT '               dbo.v_ShadowMRP_ComponentDemand';
PRINT '               dbo.v_ShadowMRP_Inventory';
PRINT '               dbo.v_ShadowMRP_POParams';
PRINT '               dbo.v_ShadowMRP_OpenSupply';
PRINT '               dbo.v_ShadowMRP_ScheduleReleases';
PRINT '               dbo.v_ShadowMRP_Summary';
PRINT '               dbo.v_ShadowMRP_SupplierSchedule';
PRINT '';
PRINT 'To refresh planned orders after demand changes:';
PRINT '  EXEC dbo.usp_Rebuild_ShadowMRP_PlannedOrders;';
PRINT '';
PRINT 'To view ready-to-confirm schedule releases:';
PRINT '  SELECT * FROM dbo.v_ShadowMRP_ScheduleReleases ORDER BY ReleaseUrgency, ItemNumber;';
PRINT '';
PRINT 'To view supplier schedules:';
PRINT '  SELECT * FROM dbo.v_ShadowMRP_SupplierSchedule ORDER BY Supplier, ItemNumber, DueDateWeek;';
PRINT '';
PRINT 'To view summary by item type:';
PRINT '  SELECT * FROM dbo.v_ShadowMRP_Summary ORDER BY ItemType, DemandBucketType;';
GO
