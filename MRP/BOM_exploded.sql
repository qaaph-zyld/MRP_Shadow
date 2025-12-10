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

SFG_Identification AS (
    SELECT * FROM CombinedPS
    WHERE ps_par IN (SELECT ItemNumber FROM CustomerItems)
),

BOMHierarchy AS (
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
        END AS [Structure_Type],
        0 AS LEVEL
    FROM CombinedPS
    
    UNION ALL
    
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
        END AS [Structure_Type],
        h.LEVEL + 1
    FROM CombinedPS m
    INNER JOIN BOMHierarchy h
        ON m.ps_par = h.component
        AND m.[Plant] = h.[Plant]
    WHERE LEVEL < 10
)

SELECT 
    h.root_parent AS [Parent_Item],
    h.current_parent AS [ps_par],
    h.component AS [ps_comp],
    h.ps_qty_per AS [Quantity_Per],
    h.ps_rmks
FROM BOMHierarchy h
WHERE h.root_parent IN (SELECT ItemNumber FROM CustomerItems)
AND h.[Structure_Type] = 'RM'
ORDER BY 
    h.[Plant],
    h.root_parent