WITH CombinationCounts AS (
    SELECT
        [serh_part],
        [serh_qty_chg],
        COUNT(*) AS combination_count
    FROM [QADEE2798].[dbo].[serh_hist]
    WHERE 
        [serh_stage] NOT IN ('new', 'pending')
        AND [serh_trans_type] IN ('pck-bld', 'pck-rct')
        AND serh_trans_date IS NOT NULL
    GROUP BY [serh_part], [serh_qty_chg]
),
RankedCombinations AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY [serh_part]
            ORDER BY 
                combination_count DESC,
                [serh_qty_chg] DESC  -- Explicit tie-breaker
        ) AS rank
    FROM CombinationCounts
)
SELECT
    [serh_part] as [Item Number],
    [serh_qty_chg] as [Qty per pack],
    combination_count,
    CASE WHEN rank = 1 THEN 1 ELSE 0 END AS is_standard
FROM RankedCombinations
ORDER BY [serh_part], [serh_qty_chg] DESC;