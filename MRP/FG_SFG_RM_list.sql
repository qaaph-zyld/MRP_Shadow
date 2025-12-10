-- ==================================================
-- Production BOM Classification Query
-- Hierarchical Priority: SFG > FG > PACK > RM
-- ==================================================

WITH CustomerItems AS (
    SELECT DISTINCT [sod_part] AS ItemNumber 
    FROM [QADEE2798].[dbo].[sod_det] 
),
CombinedPS AS (    
    SELECT 
        '2798' AS [Plant],
        ps_par,
        ps_comp,
        ps_qty_per,
        ps_rmks
    FROM [QADEE2798].[dbo].[ps_mstr]
    WHERE [ps_end] IS NULL
),
BOMHierarchy AS (
    -- Level 1: Direct customer items
    SELECT 
        ps_par AS root_parent,
        ps_par AS current_parent,
        ps_comp AS component,
        [Plant],
        ps_qty_per,
        ps_rmks,
        CASE 
            WHEN EXISTS (SELECT 1 FROM CombinedPS ps2 WHERE ps2.ps_par = CombinedPS.ps_comp) THEN 'SFG'
            ELSE 'RM'
        END AS [Structure_Type]
    FROM CombinedPS
    WHERE ps_par IN (SELECT ItemNumber FROM CustomerItems)
    
    UNION ALL
    
    -- Recursive levels: Components of components
    SELECT 
        h.root_parent,
        m.ps_par AS current_parent,
        m.ps_comp AS component,
        h.[Plant],
        m.ps_qty_per,
        m.ps_rmks,
        CASE 
            WHEN EXISTS (SELECT 1 FROM CombinedPS ps2 WHERE ps2.ps_par = m.ps_comp) THEN 'SFG'
            ELSE 'RM'
        END AS [Structure_Type]
    FROM CombinedPS m
    INNER JOIN BOMHierarchy h
        ON m.ps_par = h.component
        AND m.[Plant] = h.[Plant]
),
-- Classification with SFG priority override
ItemClassificationPriority AS (
    -- Priority 1: SFG (Semi-Finished Goods) - Highest Priority
    SELECT DISTINCT
        component AS ItemNumber,
        'SFG' AS ItemType,
        1 AS Priority
    FROM BOMHierarchy
    WHERE [Structure_Type] = 'SFG'
    
    UNION ALL
    
    -- Priority 2: FG (Finished Goods) - Lower than SFG
    SELECT DISTINCT 
        root_parent AS ItemNumber,
        'FG' AS ItemType,
        2 AS Priority
    FROM BOMHierarchy
    
    UNION ALL
    
    -- Priority 3: PACK (Packaging) - Component level
    SELECT DISTINCT
        component AS ItemNumber,
        'PACK' AS ItemType,
        3 AS Priority
    FROM BOMHierarchy
    WHERE ps_rmks = 'PACK'
    
    UNION ALL
    
    -- Priority 4: RM (Raw Materials) - Lowest Priority
    SELECT DISTINCT
        component AS ItemNumber,
        'RM' AS ItemType,
        4 AS Priority
    FROM BOMHierarchy
    WHERE ps_rmks = 'RM'
),
-- Deterministic classification using window function
RankedClassification AS (
    SELECT 
        ItemNumber,
        ItemType,
        Priority,
        ROW_NUMBER() OVER (
            PARTITION BY ItemNumber 
            ORDER BY Priority ASC, ItemType ASC
        ) AS classification_rank
    FROM ItemClassificationPriority
)
-- Final production output
SELECT 
    ItemNumber,
    ItemType
FROM RankedClassification
WHERE classification_rank = 1
ORDER BY 
    CASE ItemType
        WHEN 'SFG' THEN 1
        WHEN 'FG' THEN 2
        WHEN 'PACK' THEN 3
        WHEN 'RM' THEN 4
    END,
    ItemNumber
OPTION (MAXRECURSION 100);