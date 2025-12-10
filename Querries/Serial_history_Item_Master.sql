WITH CTE AS (
    SELECT
        CAST([serh_master_id] AS VARCHAR(30)) AS [serh_master_id], -- Cast to VARCHAR
        [serh_part],
        [serh_site],
        COALESCE(
            [serh_part],
            (SELECT TOP 1 [serh_part] 
             FROM [QADEE2798].[dbo].[serh_hist] AS lookup_part 
             WHERE lookup_part.[serh_master_id] = main.[serh_master_id] 
               AND lookup_part.[serh_part] IS NOT NULL)
        ) AS [Item Number],
        COALESCE(
            [serh_site],
            (SELECT TOP 1 [serh_site] 
             FROM [QADEE2798].[dbo].[serh_hist] AS lookup_site 
             WHERE lookup_site.[serh_master_id] = main.[serh_master_id] 
               AND lookup_site.[serh_site] IS NOT NULL)
        ) AS [Plant],
        [serh_trans_type],
        [serh_qty_chg]
    FROM [QADEE2798].[dbo].[serh_hist] AS main
    WHERE 
        [serh_stage] NOT IN ('new', 'pending') 
        AND [serh_trans_type] <> 'pck-mov'
)
SELECT
    [serh_master_id],
    [Item Number],
    [Plant],
    SUM(CASE WHEN [serh_trans_type] = 'pck-bld' THEN [serh_qty_chg] ELSE 0 END) AS [pck-bld],
    SUM(CASE WHEN [serh_trans_type] = 'pck-rct' THEN [serh_qty_chg] ELSE 0 END) AS [pck-rct],
    SUM(CASE WHEN [serh_trans_type] = 'pck-rmv' THEN [serh_qty_chg] ELSE 0 END) AS [pck-rmv],
    SUM(CASE WHEN [serh_trans_type] = 'pck-dec' THEN [serh_qty_chg] ELSE 0 END) AS [pck-dec],
    SUM(CASE WHEN [serh_trans_type] = 'pck-iss' THEN [serh_qty_chg] ELSE 0 END) AS [pck-iss],
    MAX(CASE WHEN ([serh_trans_type] = 'pck-chs' AND [serh_qty_chg] = 0) THEN 'Picked' ELSE null END) AS [Picked]
FROM CTE
GROUP BY
    [serh_master_id],
    [Item Number],
    [Plant]
HAVING
    NOT (SUM(CASE WHEN [serh_trans_type] = 'pck-bld' THEN [serh_qty_chg] ELSE 0 END) = 0
          AND SUM(CASE WHEN [serh_trans_type] = 'pck-rct' THEN [serh_qty_chg] ELSE 0 END) = 0
		            AND SUM(CASE WHEN [serh_trans_type] = 'pck-rmv' THEN [serh_qty_chg] ELSE 0 END) = 0
          AND SUM(CASE WHEN [serh_trans_type] = 'pck-dec' THEN [serh_qty_chg] ELSE 0 END) = -1
          AND SUM(CASE WHEN [serh_trans_type] = 'pck-iss' THEN [serh_qty_chg] ELSE 0 END) = 0)
ORDER BY
    [serh_master_id],
    [Item Number],
    [Plant];