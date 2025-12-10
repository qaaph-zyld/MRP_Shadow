-- Supplier Consistency Analysis Query
-- Identifies suppliers with inconsistent operational parameters

-- Phase 1: Temp table initialization
IF OBJECT_ID('tempdb..#ClassifiedItems') IS NOT NULL
    DROP TABLE #ClassifiedItems;

-- Phase 2: Hierarchical item classification
WITH 
CustomerItems AS (
    SELECT DISTINCT [sod_part] AS ItemNumber 
    FROM [QADEE2798].[dbo].[sod_det]
),
CombinedPS AS (
    SELECT [ps_par] AS ItemNumber
    FROM [QADEE2798].[dbo].[ps_mstr]
    WHERE [ps_end] IS NULL 
      AND [ps_par] IN (SELECT ItemNumber FROM CustomerItems)
    UNION
    SELECT [pt_part] AS ItemNumber
    FROM [QADEE2798].[dbo].[pt_mstr]
    WHERE [pt_status] = 'ACTIVE'
),
BOMHierarchy AS (
    SELECT 
        parent.[ps_par] AS parent,
        parent.[ps_comp] AS component,
        1 AS level
    FROM [QADEE2798].[dbo].[ps_mstr] parent
    INNER JOIN CombinedPS ON parent.[ps_par] = CombinedPS.ItemNumber
    WHERE parent.[ps_end] IS NULL
    
    UNION ALL
    
    SELECT 
        child.[ps_par] AS parent,
        child.[ps_comp] AS component,
        h.level + 1
    FROM [QADEE2798].[dbo].[ps_mstr] child
    INNER JOIN BOMHierarchy h ON child.[ps_par] = h.component
    WHERE child.[ps_end] IS NULL
),
ClassifiedItems AS (
    SELECT ItemNumber FROM CustomerItems
    UNION
    SELECT component AS ItemNumber FROM BOMHierarchy
)
SELECT ItemNumber 
INTO #ClassifiedItems
FROM ClassifiedItems;

-- Phase 3: Primary supplier consistency analysis
SELECT 
    s.[Supplier],
    ad.[ad_sort] AS [Supplier_Sort_Name],
    ad.[ad_name] AS [Supplier_Name],
    s.sd_pat_count,
    s.translt_count,
    s.planner_count,
    s.weeks_count,
    CASE 
        WHEN s.sd_pat_count > 1 THEN 'Multiple Patterns' 
        ELSE 'Consistent' 
    END AS [Ship_Delivery_Pattern_Status],
    CASE 
        WHEN s.translt_count > 1 THEN 'Multiple Days' 
        ELSE 'Consistent' 
    END AS [PO_Transport_Days_Status],
    CASE 
        WHEN s.planner_count > 1 THEN 'Multiple Planners' 
        ELSE 'Consistent' 
    END AS [PO_Line_Planner_Status],
    CASE 
        WHEN s.weeks_count > 1 THEN 'Multiple Weeks' 
        ELSE 'Consistent' 
    END AS [Planned_Weeks_Status]
FROM (
    SELECT 
        po.[po_vend] AS [Supplier],
        COUNT(DISTINCT [pod_sd_pat]) AS sd_pat_count,
        COUNT(DISTINCT [pod_translt_days]) AS translt_count,
        COUNT(DISTINCT [pod__chr08]) AS planner_count,
        COUNT(DISTINCT [pod_plan_weeks]) AS weeks_count
    FROM [QADEE2798].[dbo].[pod_det] pod
    INNER JOIN #ClassifiedItems ci ON pod.[pod_part] = ci.ItemNumber
    JOIN [QADEE2798].[dbo].[po_mstr] po ON pod.[pod_nbr] = po.[po_nbr]
    WHERE [pod_status] IS NULL 
      AND [pod_end_eff[1]]] > GETDATE()
    GROUP BY po.[po_vend]
) s
JOIN [QADEE2798].[dbo].[ad_mstr] ad ON s.[Supplier] = ad.[ad_addr]
ORDER BY s.[Supplier];

-- Phase 4: Cleanup
DROP TABLE #ClassifiedItems;