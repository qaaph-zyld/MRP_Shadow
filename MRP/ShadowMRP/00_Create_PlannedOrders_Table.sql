/*
================================================================================
SHADOW MRP - PLANNED ORDERS TABLE
================================================================================
Purpose:
  Stores computed planned order releases for all items, refreshed on each run.
  This is the core output of the shadow MRP pipeline.

Usage:
  Run this script once to create the table structure.
  The rebuild procedure will TRUNCATE and repopulate on each execution.

Validation:
  Compare against [mrp_det] or 23.18 export to verify accuracy.
================================================================================
*/

-- Drop if exists for clean rebuild during development
IF OBJECT_ID('dbo.ShadowMRP_PlannedOrders', 'U') IS NOT NULL
    DROP TABLE dbo.ShadowMRP_PlannedOrders;
GO

CREATE TABLE dbo.ShadowMRP_PlannedOrders (
    -- Primary key
    PlannedOrderID          INT IDENTITY(1,1) PRIMARY KEY,
    
    -- Item identification
    Site                    VARCHAR(10)     NOT NULL,
    ItemNumber              VARCHAR(50)     NOT NULL,
    ItemType                VARCHAR(10)     NULL,       -- FG/SFG/RM/No BOM
    
    -- Supplier (for RM items)
    Supplier                VARCHAR(50)     NULL,
    SupplierName            VARCHAR(100)    NULL,
    
    -- Time bucket
    DueDateYear             INT             NOT NULL,
    DueDateWeek             INT             NOT NULL,
    PlannedOrderDueDate     DATE            NOT NULL,   -- Monday of due week
    PlannedOrderReleaseDate DATE            NULL,       -- Due - TransportDays
    DemandBucketType        VARCHAR(20)     NOT NULL,   -- Past_Due, Current_Week, Week_1..8, Future
    
    -- Quantities
    GrossRequirement        DECIMAL(18,4)   NOT NULL DEFAULT 0,
    ScheduledReceipts       DECIMAL(18,4)   NOT NULL DEFAULT 0,  -- Open PO/WO qty
    ProjectedOnHandBefore   DECIMAL(18,4)   NOT NULL DEFAULT 0,
    NetRequirement          DECIMAL(18,4)   NOT NULL DEFAULT 0,
    PlannedOrderQty         DECIMAL(18,4)   NOT NULL DEFAULT 0,
    ProjectedOnHandAfter    DECIMAL(18,4)   NOT NULL DEFAULT 0,
    
    -- Planning parameters used
    SafetyStock             DECIMAL(18,4)   NULL,
    StandardPack            DECIMAL(18,4)   NULL,
    TransportDays           INT             NULL,
    
    -- Metadata
    PlanRunTimestamp        DATETIME2       NOT NULL,
    SourceFlag              VARCHAR(50)     NULL        -- e.g. 'BOM_Explosion', 'Direct_Demand'
);
GO

-- Indexes for common queries
CREATE NONCLUSTERED INDEX IX_ShadowMRP_Site_Item 
    ON dbo.ShadowMRP_PlannedOrders (Site, ItemNumber);

CREATE NONCLUSTERED INDEX IX_ShadowMRP_DueWeek 
    ON dbo.ShadowMRP_PlannedOrders (DueDateYear, DueDateWeek);

CREATE NONCLUSTERED INDEX IX_ShadowMRP_Supplier 
    ON dbo.ShadowMRP_PlannedOrders (Supplier) 
    WHERE Supplier IS NOT NULL;

CREATE NONCLUSTERED INDEX IX_ShadowMRP_ItemType 
    ON dbo.ShadowMRP_PlannedOrders (ItemType);
GO

PRINT 'ShadowMRP_PlannedOrders table created successfully.';
GO
