/*
================================================================================
SHADOW MRP - VALIDATION VIEWS
================================================================================
Purpose:
  Views to validate shadow MRP results against official QAD MRP (mrp_det)
  and to generate actionable schedule release reports.

Views:
  1. v_ShadowMRP_ValidationVsQAD    - Compare shadow vs mrp_det
  2. v_ShadowMRP_ScheduleReleases   - Ready-to-confirm schedule releases
  3. v_ShadowMRP_Summary            - Executive summary by item type
  4. v_ShadowMRP_SupplierSchedule   - Supplier-facing schedule view

Dependencies:
  - dbo.ShadowMRP_PlannedOrders
  - [QADEE2798].[dbo].[mrp_det] (when available)
================================================================================
*/

--------------------------------------------------------------------------------
-- 1. VALIDATION VIEW: Compare Shadow MRP vs Official QAD MRP
--------------------------------------------------------------------------------
IF OBJECT_ID('dbo.v_ShadowMRP_ValidationVsQAD', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_ValidationVsQAD;
GO

CREATE VIEW dbo.v_ShadowMRP_ValidationVsQAD AS
/*
    This view compares shadow MRP planned orders against official mrp_det.
    
    NOTE: The mrp_det table must be populated either:
      - Directly from QAD replication, or
      - Via 23.18 MRP Export CSV import
    
    If mrp_det is not available, this view will return empty results.
    Use this to identify discrepancies and tune the shadow MRP logic.
*/
WITH 
-- Shadow MRP aggregated by item/week
ShadowAgg AS (
    SELECT
        Site,
        ItemNumber,
        DueDateYear,
        DueDateWeek,
        SUM(GrossRequirement) AS Shadow_GrossReq,
        SUM(ScheduledReceipts) AS Shadow_SchedRcpt,
        SUM(PlannedOrderQty) AS Shadow_PlannedQty,
        MAX(PlanRunTimestamp) AS Shadow_RunTime
    FROM dbo.ShadowMRP_PlannedOrders
    GROUP BY Site, ItemNumber, DueDateYear, DueDateWeek
),
-- Official MRP aggregated by item/week (if mrp_det exists)
OfficialMRP AS (
    SELECT
        md_site AS Site,
        md_item AS ItemNumber,
        DATEPART(YEAR, md_due_date) AS DueDateYear,
        DATEPART(WEEK, md_due_date) AS DueDateWeek,
        SUM(CASE WHEN md_type = 'REQ' THEN md_qty ELSE 0 END) AS QAD_GrossReq,
        SUM(CASE WHEN md_type IN ('PO','WO','SA') THEN md_qty ELSE 0 END) AS QAD_SchedRcpt,
        SUM(CASE WHEN md_type = 'PLN' THEN md_qty ELSE 0 END) AS QAD_PlannedQty
    FROM [QADEE2798].[dbo].[mrp_det]
    GROUP BY md_site, md_item, DATEPART(YEAR, md_due_date), DATEPART(WEEK, md_due_date)
)
SELECT
    COALESCE(s.Site, o.Site) AS Site,
    COALESCE(s.ItemNumber, o.ItemNumber) AS ItemNumber,
    COALESCE(s.DueDateYear, o.DueDateYear) AS DueDateYear,
    COALESCE(s.DueDateWeek, o.DueDateWeek) AS DueDateWeek,
    
    -- Shadow MRP values
    ISNULL(s.Shadow_GrossReq, 0) AS Shadow_GrossReq,
    ISNULL(s.Shadow_SchedRcpt, 0) AS Shadow_SchedRcpt,
    ISNULL(s.Shadow_PlannedQty, 0) AS Shadow_PlannedQty,
    s.Shadow_RunTime,
    
    -- Official QAD MRP values
    ISNULL(o.QAD_GrossReq, 0) AS QAD_GrossReq,
    ISNULL(o.QAD_SchedRcpt, 0) AS QAD_SchedRcpt,
    ISNULL(o.QAD_PlannedQty, 0) AS QAD_PlannedQty,
    
    -- Variance calculations
    ISNULL(s.Shadow_GrossReq, 0) - ISNULL(o.QAD_GrossReq, 0) AS Variance_GrossReq,
    ISNULL(s.Shadow_PlannedQty, 0) - ISNULL(o.QAD_PlannedQty, 0) AS Variance_PlannedQty,
    
    -- Validation flags
    CASE 
        WHEN ABS(ISNULL(s.Shadow_PlannedQty, 0) - ISNULL(o.QAD_PlannedQty, 0)) <= 1 THEN 'MATCH'
        WHEN o.QAD_PlannedQty IS NULL THEN 'SHADOW_ONLY'
        WHEN s.Shadow_PlannedQty IS NULL THEN 'QAD_ONLY'
        ELSE 'MISMATCH'
    END AS ValidationStatus
    
FROM ShadowAgg s
FULL OUTER JOIN OfficialMRP o
    ON s.Site = o.Site
    AND s.ItemNumber = o.ItemNumber
    AND s.DueDateYear = o.DueDateYear
    AND s.DueDateWeek = o.DueDateWeek;
GO

--------------------------------------------------------------------------------
-- 2. SCHEDULE RELEASES VIEW: Ready-to-confirm releases
--------------------------------------------------------------------------------
IF OBJECT_ID('dbo.v_ShadowMRP_ScheduleReleases', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_ScheduleReleases;
GO

CREATE VIEW dbo.v_ShadowMRP_ScheduleReleases AS
/*
    This view presents planned orders in a format ready for review and
    confirmation as supplier schedule releases.
    
    Filter by:
      - ItemType = 'RM' for supplier orders
      - DemandBucketType for time horizon
      - Supplier for specific vendor schedules
*/
SELECT
    po.Site,
    po.ItemNumber,
    bc.ItemDescription,
    po.ItemType,
    po.Supplier,
    po.SupplierName,
    bc.Planner,
    po.DemandBucketType,
    po.DueDateYear,
    po.DueDateWeek,
    po.PlannedOrderDueDate,
    po.PlannedOrderReleaseDate,
    po.GrossRequirement,
    po.ScheduledReceipts,
    po.NetRequirement,
    po.PlannedOrderQty,
    po.SafetyStock,
    po.StandardPack,
    po.TransportDays,
    po.ProjectedOnHandBefore,
    po.ProjectedOnHandAfter,
    
    -- Release status flags
    CASE 
        WHEN po.PlannedOrderReleaseDate <= CAST(GETDATE() AS DATE) THEN 'RELEASE NOW'
        WHEN po.PlannedOrderReleaseDate <= DATEADD(DAY, 7, GETDATE()) THEN 'RELEASE THIS WEEK'
        WHEN po.PlannedOrderReleaseDate <= DATEADD(DAY, 14, GETDATE()) THEN 'RELEASE NEXT WEEK'
        ELSE 'FUTURE'
    END AS ReleaseUrgency,
    
    -- Coverage indicator
    CASE 
        WHEN po.ProjectedOnHandAfter < 0 THEN 'SHORTAGE'
        WHEN po.ProjectedOnHandAfter < po.SafetyStock THEN 'BELOW_SAFETY'
        ELSE 'OK'
    END AS CoverageStatus,
    
    po.PlanRunTimestamp,
    po.SourceFlag
    
FROM dbo.ShadowMRP_PlannedOrders po
LEFT JOIN dbo.v_ShadowMRP_BOMClassification bc
    ON po.Site = bc.Site AND po.ItemNumber = bc.ItemNumber
WHERE po.PlannedOrderQty > 0  -- Only show periods with planned orders
   OR po.GrossRequirement > 0;  -- Or with demand
GO

--------------------------------------------------------------------------------
-- 3. SUMMARY VIEW: Executive summary by item type and time bucket
--------------------------------------------------------------------------------
IF OBJECT_ID('dbo.v_ShadowMRP_Summary', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_Summary;
GO

CREATE VIEW dbo.v_ShadowMRP_Summary AS
SELECT
    Site,
    ItemType,
    DemandBucketType,
    COUNT(DISTINCT ItemNumber) AS ItemCount,
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

--------------------------------------------------------------------------------
-- 4. SUPPLIER SCHEDULE VIEW: Aggregated by supplier for schedule transmission
--------------------------------------------------------------------------------
IF OBJECT_ID('dbo.v_ShadowMRP_SupplierSchedule', 'V') IS NOT NULL
    DROP VIEW dbo.v_ShadowMRP_SupplierSchedule;
GO

CREATE VIEW dbo.v_ShadowMRP_SupplierSchedule AS
/*
    Aggregates planned orders by supplier for schedule release transmission.
    This mimics the output of QAD 35.4.8 Supplier Shipping Schedule Export.
*/
SELECT
    po.Site,
    po.Supplier,
    po.SupplierName,
    po.ItemNumber,
    bc.ItemDescription,
    po.DueDateYear,
    po.DueDateWeek,
    po.PlannedOrderDueDate,
    po.PlannedOrderReleaseDate,
    SUM(po.GrossRequirement) AS TotalRequirement,
    SUM(po.PlannedOrderQty) AS TotalPlannedQty,
    po.StandardPack,
    po.TransportDays,
    
    -- Cumulative quantity for supplier schedules
    SUM(SUM(po.PlannedOrderQty)) OVER (
        PARTITION BY po.Site, po.Supplier, po.ItemNumber 
        ORDER BY po.DueDateYear, po.DueDateWeek
    ) AS CumulativePlannedQty,
    
    MAX(po.PlanRunTimestamp) AS PlanRunTimestamp
    
FROM dbo.ShadowMRP_PlannedOrders po
LEFT JOIN dbo.v_ShadowMRP_BOMClassification bc
    ON po.Site = bc.Site AND po.ItemNumber = bc.ItemNumber
WHERE po.ItemType = 'RM'  -- Only raw materials for suppliers
  AND po.Supplier IS NOT NULL
GROUP BY 
    po.Site,
    po.Supplier,
    po.SupplierName,
    po.ItemNumber,
    bc.ItemDescription,
    po.DueDateYear,
    po.DueDateWeek,
    po.PlannedOrderDueDate,
    po.PlannedOrderReleaseDate,
    po.StandardPack,
    po.TransportDays;
GO

PRINT 'All validation and reporting views created successfully.';
GO
