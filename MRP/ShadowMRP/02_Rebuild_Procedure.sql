/*
================================================================================
SHADOW MRP - MAIN REBUILD PROCEDURE
================================================================================
Purpose:
  Rebuilds the ShadowMRP_PlannedOrders table with fresh planned orders.
  Implements simplified MRP netting logic:
    1. Gross Requirements (from BOM-exploded customer demand)
    2. - Scheduled Receipts (open PO/WO)
    3. - Projected Available (on-hand + prior period ending)
    4. = Net Requirements
    5. Apply lot sizing (standard pack rounding)
    6. = Planned Order Qty

Usage:
  EXEC dbo.usp_Rebuild_ShadowMRP_PlannedOrders;

  Run this whenever customer demand changes (EDI refresh) to regenerate
  planned orders for all items.

Dependencies:
  - dbo.ShadowMRP_PlannedOrders (target table)
  - dbo.v_ShadowMRP_WeekReference
  - dbo.v_ShadowMRP_BOMClassification
  - dbo.v_ShadowMRP_ComponentDemand
  - dbo.v_ShadowMRP_Inventory
  - dbo.v_ShadowMRP_POParams
  - dbo.v_ShadowMRP_OpenSupply
================================================================================
*/

IF OBJECT_ID('dbo.usp_Rebuild_ShadowMRP_PlannedOrders', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_Rebuild_ShadowMRP_PlannedOrders;
GO

CREATE PROCEDURE dbo.usp_Rebuild_ShadowMRP_PlannedOrders
AS
BEGIN
    SET NOCOUNT ON;
    SET DATEFIRST 1;  -- Monday = first day of week

    DECLARE @RunTimestamp DATETIME2 = SYSDATETIME();
    DECLARE @RowsInserted INT = 0;

    BEGIN TRY
        -- Clear previous run
        TRUNCATE TABLE dbo.ShadowMRP_PlannedOrders;

        -- =====================================================================
        -- STEP 1: Build master item/week grid with demand
        -- =====================================================================
        ;WITH 
        -- Week calendar (Current + 26 weeks horizon)
        WeekCalendar AS (
            SELECT
                WeekOffset,
                DemandBucketType,
                DueDateYear,
                DueDateWeek,
                WeekStartDate
            FROM dbo.v_ShadowMRP_WeekReference
        ),
        
        -- Add Past_Due bucket
        AllBuckets AS (
            SELECT -1 AS WeekOffset, 'Past_Due' AS DemandBucketType, 
                   DATEPART(YEAR, GETDATE()) AS DueDateYear,
                   0 AS DueDateWeek,
                   DATEADD(DAY, -7, CAST(GETDATE() AS DATE)) AS WeekStartDate
            UNION ALL
            SELECT * FROM WeekCalendar
        ),
        
        -- Get all items with their classification
        ItemMaster AS (
            SELECT
                Site,
                ItemNumber,
                ItemDescription,
                ItemType,
                ISNULL(SafetyStock, 0) AS SafetyStock,
                DefaultSupplier,
                Planner
            FROM dbo.v_ShadowMRP_BOMClassification
            WHERE ItemStatus NOT IN ('OBS', 'EPIC')  -- Exclude obsolete/EPIC items
        ),
        
        -- Aggregate demand by item/week
        DemandByWeek AS (
            SELECT
                d.Site,
                d.ItemNumber,
                d.DemandYear,
                d.DemandWeek,
                d.DemandBucketType,
                SUM(d.GrossRequirement) AS GrossRequirement
            FROM dbo.v_ShadowMRP_ComponentDemand d
            GROUP BY d.Site, d.ItemNumber, d.DemandYear, d.DemandWeek, d.DemandBucketType
        ),
        
        -- Inventory snapshot
        CurrentInventory AS (
            SELECT
                Site,
                ItemNumber,
                NettableQty AS OnHandQty
            FROM dbo.v_ShadowMRP_Inventory
        ),
        
        -- PO parameters
        POParams AS (
            SELECT
                Site,
                ItemNumber,
                Supplier,
                SupplierName,
                StandardPack,
                TransportDays
            FROM dbo.v_ShadowMRP_POParams
        ),
        
        -- Scheduled receipts aggregated by week
        ScheduledReceiptsByWeek AS (
            SELECT
                Site,
                ItemNumber,
                DueYear,
                DueWeek,
                SUM(OpenQty) AS ScheduledReceiptQty
            FROM dbo.v_ShadowMRP_OpenSupply
            GROUP BY Site, ItemNumber, DueYear, DueWeek
        ),
        
        -- =====================================================================
        -- STEP 2: Create item/week grid with all data joined
        -- =====================================================================
        ItemWeekGrid AS (
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
                b.WeekOffset,
                b.DemandBucketType,
                b.DueDateYear,
                b.DueDateWeek,
                b.WeekStartDate,
                ISNULL(inv.OnHandQty, 0) AS OnHandQty,
                ISNULL(d.GrossRequirement, 0) AS GrossRequirement,
                ISNULL(sr.ScheduledReceiptQty, 0) AS ScheduledReceiptQty
            FROM ItemMaster im
            CROSS JOIN AllBuckets b
            LEFT JOIN CurrentInventory inv 
                ON im.Site = inv.Site AND im.ItemNumber = inv.ItemNumber
            LEFT JOIN DemandByWeek d 
                ON im.Site = d.Site 
                AND im.ItemNumber = d.ItemNumber 
                AND b.DemandBucketType = d.DemandBucketType
            LEFT JOIN ScheduledReceiptsByWeek sr
                ON im.Site = sr.Site 
                AND im.ItemNumber = sr.ItemNumber 
                AND b.DueDateYear = sr.DueYear 
                AND b.DueDateWeek = sr.DueWeek
            LEFT JOIN POParams po
                ON im.Site = po.Site AND im.ItemNumber = po.ItemNumber
            WHERE ISNULL(d.GrossRequirement, 0) > 0  -- Only items with demand
               OR ISNULL(sr.ScheduledReceiptQty, 0) > 0  -- Or with scheduled receipts
        ),
        
        -- =====================================================================
        -- STEP 3: Calculate running projected on-hand and net requirements
        -- Using window functions for running totals
        -- =====================================================================
        MRPCalculation AS (
            SELECT
                g.Site,
                g.ItemNumber,
                g.ItemDescription,
                g.ItemType,
                g.SafetyStock,
                g.Planner,
                g.Supplier,
                g.SupplierName,
                g.StandardPack,
                g.TransportDays,
                g.WeekOffset,
                g.DemandBucketType,
                g.DueDateYear,
                g.DueDateWeek,
                g.WeekStartDate,
                g.OnHandQty,
                g.GrossRequirement,
                g.ScheduledReceiptQty,
                
                -- Projected Available Before = OnHand + cumulative prior receipts - cumulative prior demand
                -- For first period: OnHand + ScheduledReceipts - GrossRequirement
                g.OnHandQty 
                    + SUM(g.ScheduledReceiptQty) OVER (
                        PARTITION BY g.Site, g.ItemNumber 
                        ORDER BY g.WeekOffset 
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                      )
                    - SUM(g.GrossRequirement) OVER (
                        PARTITION BY g.Site, g.ItemNumber 
                        ORDER BY g.WeekOffset 
                        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                      ) AS ProjectedBeforeDemand,
                
                -- Running cumulative demand up to current period
                SUM(g.GrossRequirement) OVER (
                    PARTITION BY g.Site, g.ItemNumber 
                    ORDER BY g.WeekOffset 
                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                ) AS CumulativeDemand,
                
                -- Running cumulative receipts
                SUM(g.ScheduledReceiptQty) OVER (
                    PARTITION BY g.Site, g.ItemNumber 
                    ORDER BY g.WeekOffset 
                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                ) AS CumulativeReceipts
                
            FROM ItemWeekGrid g
        ),
        
        -- =====================================================================
        -- STEP 4: Calculate Net Requirements and Planned Orders
        -- =====================================================================
        PlannedOrderCalc AS (
            SELECT
                m.Site,
                m.ItemNumber,
                m.ItemDescription,
                m.ItemType,
                m.SafetyStock,
                m.Planner,
                m.Supplier,
                m.SupplierName,
                m.StandardPack,
                m.TransportDays,
                m.WeekOffset,
                m.DemandBucketType,
                m.DueDateYear,
                m.DueDateWeek,
                m.WeekStartDate,
                m.GrossRequirement,
                m.ScheduledReceiptQty,
                
                -- Projected On-Hand Before this period's planned order
                m.OnHandQty + m.CumulativeReceipts - ISNULL(m.CumulativeDemand, 0) 
                    + m.GrossRequirement AS ProjectedOnHandBefore,
                
                -- Net Requirement = how much below safety stock
                CASE 
                    WHEN (m.OnHandQty + m.CumulativeReceipts - m.CumulativeDemand) < m.SafetyStock
                    THEN m.SafetyStock - (m.OnHandQty + m.CumulativeReceipts - m.CumulativeDemand)
                    ELSE 0
                END AS RawNetRequirement
                
            FROM MRPCalculation m
        ),
        
        -- Apply lot sizing
        FinalPlannedOrders AS (
            SELECT
                p.*,
                -- Round up to standard pack
                CASE 
                    WHEN p.RawNetRequirement > 0 AND p.StandardPack > 0
                    THEN CEILING(p.RawNetRequirement / p.StandardPack) * p.StandardPack
                    WHEN p.RawNetRequirement > 0
                    THEN p.RawNetRequirement
                    ELSE 0
                END AS PlannedOrderQty,
                
                -- Projected On-Hand After planned order
                p.ProjectedOnHandBefore + 
                    CASE 
                        WHEN p.RawNetRequirement > 0 AND p.StandardPack > 0
                        THEN CEILING(p.RawNetRequirement / p.StandardPack) * p.StandardPack
                        WHEN p.RawNetRequirement > 0
                        THEN p.RawNetRequirement
                        ELSE 0
                    END AS ProjectedOnHandAfter,
                
                -- Release date = Due date - Transport days
                DATEADD(DAY, -p.TransportDays, p.WeekStartDate) AS PlannedOrderReleaseDate
                
            FROM PlannedOrderCalc p
        )
        
        -- =====================================================================
        -- STEP 5: Insert into target table
        -- =====================================================================
        INSERT INTO dbo.ShadowMRP_PlannedOrders (
            Site,
            ItemNumber,
            ItemType,
            Supplier,
            SupplierName,
            DueDateYear,
            DueDateWeek,
            PlannedOrderDueDate,
            PlannedOrderReleaseDate,
            DemandBucketType,
            GrossRequirement,
            ScheduledReceipts,
            ProjectedOnHandBefore,
            NetRequirement,
            PlannedOrderQty,
            ProjectedOnHandAfter,
            SafetyStock,
            StandardPack,
            TransportDays,
            PlanRunTimestamp,
            SourceFlag
        )
        SELECT
            f.Site,
            f.ItemNumber,
            f.ItemType,
            f.Supplier,
            f.SupplierName,
            f.DueDateYear,
            f.DueDateWeek,
            f.WeekStartDate AS PlannedOrderDueDate,
            f.PlannedOrderReleaseDate,
            f.DemandBucketType,
            f.GrossRequirement,
            f.ScheduledReceiptQty AS ScheduledReceipts,
            f.ProjectedOnHandBefore,
            f.RawNetRequirement AS NetRequirement,
            f.PlannedOrderQty,
            f.ProjectedOnHandAfter,
            f.SafetyStock,
            f.StandardPack,
            f.TransportDays,
            @RunTimestamp,
            CASE 
                WHEN f.ItemType = 'FG' THEN 'Direct_Demand'
                ELSE 'BOM_Explosion'
            END AS SourceFlag
        FROM FinalPlannedOrders f
        WHERE f.GrossRequirement > 0  -- Only periods with demand
           OR f.PlannedOrderQty > 0   -- Or with planned orders
           OR f.ScheduledReceiptQty > 0;  -- Or with scheduled receipts

        SET @RowsInserted = @@ROWCOUNT;

        -- Log completion
        PRINT 'Shadow MRP rebuild completed at ' + CONVERT(VARCHAR(30), @RunTimestamp, 121);
        PRINT 'Total planned order rows inserted: ' + CAST(@RowsInserted AS VARCHAR(20));

    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        
        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END;
GO

PRINT 'Procedure usp_Rebuild_ShadowMRP_PlannedOrders created successfully.';
GO
