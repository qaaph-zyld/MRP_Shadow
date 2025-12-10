/*
MRP Pegging & Days of Supply (STUB)
-----------------------------------

This is a placeholder query for MRP pegging / Days of Supply.

ASSUMPTIONS (to be validated on Monday):
- Table: [QADEE2798].[dbo].[mrp_det]
- One row per requirement/supply line per discrete due date.
- Expected columns (names ARE GUESSES, replace with real ones):
    md_item         -- Item Number
    md_site         -- Site / Plant
    md_order_type   -- e.g. PO / WO / SA / Forecast
    md_order_nbr    -- Order number
    md_order_line   -- Order line
    md_due_date     -- Discrete due date
    md_discr_qty    -- Discrete quantity (MRP bucket)

Replace column names, filters and joins once mrp_det is available.
*/

WITH MRP_Source AS (
    SELECT
        md_item       AS [Item Number],   -- TODO: replace md_item with real column
        md_site       AS [Site],          -- TODO
        md_order_type AS [Order Type],    -- TODO
        md_order_nbr  AS [Order Number],  -- TODO
        md_order_line AS [Order Line],    -- TODO
        md_due_date   AS [Due Date],      -- TODO
        md_discr_qty  AS [Discrete Qty]   -- TODO
    FROM [QADEE2798].[dbo].[mrp_det] md
    -- TODO: adjust column names and WHERE conditions to match real mrp_det definition
),
Bucketed AS (
    -- Aggregate discrete qty by ISO year/week per item/site/order
    SELECT
        [Item Number],
        [Site],
        [Order Type],
        [Order Number],
        [Order Line],
        DATEPART(YEAR, [Due Date]) AS [Year],
        DATEPART(WEEK, [Due Date]) AS [Week],
        SUM([Discrete Qty])        AS [Week Qty]
    FROM MRP_Source
    GROUP BY 
        [Item Number],[Site],[Order Type],[Order Number],[Order Line],
        DATEPART(YEAR, [Due Date]), DATEPART(WEEK, [Due Date])
),
Aggregated AS (
    -- Collapse to one row per item/site with simple buckets
    SELECT
        [Item Number],
        [Site],
        SUM(CASE 
                WHEN [Year] < YEAR(GETDATE()) 
                  OR ([Year] = YEAR(GETDATE()) AND [Week] < DATEPART(WEEK, GETDATE()))
                THEN [Week Qty] ELSE 0 END) AS [Past_Due],
        SUM(CASE 
                WHEN [Year] = YEAR(GETDATE()) 
                 AND [Week] = DATEPART(WEEK, GETDATE())
                THEN [Week Qty] ELSE 0 END) AS [Current_Week],
        SUM(CASE 
                WHEN [Year] = YEAR(GETDATE()) 
                 AND [Week] = DATEPART(WEEK, GETDATE()) + 1
                THEN [Week Qty] ELSE 0 END) AS [Week_1],
        SUM(CASE 
                WHEN [Year] = YEAR(GETDATE()) 
                 AND [Week] = DATEPART(WEEK, GETDATE()) + 2
                THEN [Week Qty] ELSE 0 END) AS [Week_2],
        SUM(CASE 
                WHEN [Year] = YEAR(GETDATE()) 
                 AND [Week] = DATEPART(WEEK, GETDATE()) + 3
                THEN [Week Qty] ELSE 0 END) AS [Week_3],
        SUM(CASE 
                WHEN [Year] = YEAR(GETDATE()) 
                 AND [Week] = DATEPART(WEEK, GETDATE()) + 4
                THEN [Week Qty] ELSE 0 END) AS [Week_4],
        SUM(CASE 
                WHEN [Year] > YEAR(GETDATE()) 
                  OR ([Year] = YEAR(GETDATE()) AND [Week] > DATEPART(WEEK, GETDATE()) + 4)
                THEN [Week Qty] ELSE 0 END) AS [Future_Demand]
    FROM Bucketed
    GROUP BY [Item Number],[Site]
),
Inventory AS (
    -- Very simple inventory view for DOS
    SELECT
        in_part AS [Item Number],
        in_site AS [Site],
        in_qty_oh AS [MRP Qty]
    FROM [QADEE2798].[dbo].[15]
),
DOS AS (
    -- Rough Days/Weeks of Supply approximation based on weeks 1-4
    SELECT
        a.[Item Number],
        a.[Site],
        a.[Past_Due],
        a.[Current_Week],
        a.[Week_1],
        a.[Week_2],
        a.[Week_3],
        a.[Week_4],
        a.[Future_Demand],
        i.[MRP Qty],
        (a.[Week_1] + a.[Week_2] + a.[Week_3] + a.[Week_4]) AS [Weeks_1_4_Total],
        CASE 
            WHEN (a.[Week_1] + a.[Week_2] + a.[Week_3] + a.[Week_4]) = 0 THEN NULL
            ELSE CAST(ISNULL(i.[MRP Qty],0) * 4.0 / NULLIF(a.[Week_1] + a.[Week_2] + a.[Week_3] + a.[Week_4],0) AS DECIMAL(18,2))
        END AS [Weeks_of_Supply]
    FROM Aggregated a
    LEFT JOIN Inventory i
      ON a.[Item Number] = i.[Item Number]
     AND a.[Site]        = i.[Site]
)
SELECT 
    [Item Number],
    [Site],
    [Past_Due],
    [Current_Week],
    [Week_1],
    [Week_2],
    [Week_3],
    [Week_4],
    [Future_Demand],
    [MRP Qty],
    [Weeks_1_4_Total],
    [Weeks_of_Supply]
FROM DOS
ORDER BY [Item Number],[Site];
