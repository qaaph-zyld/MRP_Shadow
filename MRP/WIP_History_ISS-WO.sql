-- WIP Minimum Calculation Query (Separate Module)
-- Purpose: Calculate WIP minimum/maximum thresholds based on 4-week consumption history

WITH DailyISS_WO AS (
    SELECT
        tr_part,
        tr_site,
        tr_effdate,
        SUM(ABS(tr_qty_loc)) AS Daily_Qty
    FROM [QADEE2798].[dbo].[tr_hist]
    WHERE tr_type = 'iss-wo'
      AND tr_effdate >= DATEADD(WEEK, -4, GETDATE())
    GROUP BY
        tr_part,
        tr_site,
        tr_effdate
),
WeeklyTotals AS (
    SELECT
        tr_part,
        tr_site,
        DATEPART(YEAR, tr_effdate) AS Year,
        DATEPART(WEEK, tr_effdate) AS WeekNum,
        SUM(Daily_Qty) AS WeeklyTotal
    FROM DailyISS_WO
    GROUP BY
        tr_part,
        tr_site,
        DATEPART(YEAR, tr_effdate),
        DATEPART(WEEK, tr_effdate)
),
WeeklyPivot AS (
    SELECT 
        tr_part,
        tr_site,
        ISNULL([Week1], 0) AS [total_ISS-WO_CW_-1],
        ISNULL([Week2], 0) AS [total_ISS-WO_CW_-2],
        ISNULL([Week3], 0) AS [total_ISS-WO_CW_-3],
        ISNULL([Week4], 0) AS [total_ISS-WO_CW_-4]
    FROM (
        SELECT 
            wt.tr_part,
            wt.tr_site,
            'Week' + CAST(DENSE_RANK() OVER (
                PARTITION BY wt.tr_part, wt.tr_site 
                ORDER BY wt.Year DESC, wt.WeekNum DESC
            ) AS VARCHAR) AS WeekLabel,
            wt.WeeklyTotal
        FROM WeeklyTotals wt
    ) AS Source
    PIVOT (
        SUM(WeeklyTotal)
        FOR WeekLabel IN ([Week1], [Week2], [Week3], [Week4])
    ) AS PivotTable
)
SELECT
    tr_part AS [Item Number],
    tr_site AS [Plant],
    [total_ISS-WO_CW_-1] AS [Week_1_Consumption],
    [total_ISS-WO_CW_-2] AS [Week_2_Consumption],
    [total_ISS-WO_CW_-3] AS [Week_3_Consumption],
    [total_ISS-WO_CW_-4] AS [Week_4_Consumption],
    -- Calculate average weekly consumption
    ([total_ISS-WO_CW_-1] + [total_ISS-WO_CW_-2] + 
     [total_ISS-WO_CW_-3] + [total_ISS-WO_CW_-4]) / 4.0 AS [Average_Weekly_Consumption],
    -- Calculate WIP minimum (3 weeks of average consumption)
    CASE 
        WHEN ([total_ISS-WO_CW_-1] + [total_ISS-WO_CW_-2] + 
             [total_ISS-WO_CW_-3] + [total_ISS-WO_CW_-4]) / 4.0 * 3 < 0 
        THEN 0 
        ELSE CAST(ROUND(([total_ISS-WO_CW_-1] + [total_ISS-WO_CW_-2] + 
             [total_ISS-WO_CW_-3] + [total_ISS-WO_CW_-4]) / 4.0 * 3, 0) AS INT) 
    END AS [WIP_minimum],
    -- Calculate WIP maximum (7 weeks of average consumption)
    CASE 
        WHEN ([total_ISS-WO_CW_-1] + [total_ISS-WO_CW_-2] + 
             [total_ISS-WO_CW_-3] + [total_ISS-WO_CW_-4]) / 4.0 * 7 < 0 
        THEN 0 
        ELSE CAST(ROUND(([total_ISS-WO_CW_-1] + [total_ISS-WO_CW_-2] + 
             [total_ISS-WO_CW_-3] + [total_ISS-WO_CW_-4]) / 4.0 * 7, 0) AS INT) 
    END AS [WIP_maximum],
    -- Calculate total 4-week consumption
    ([total_ISS-WO_CW_-1] + [total_ISS-WO_CW_-2] + 
     [total_ISS-WO_CW_-3] + [total_ISS-WO_CW_-4]) AS [Total_4Week_Consumption],
    -- Flag items with no consumption
    CASE 
        WHEN ([total_ISS-WO_CW_-1] + [total_ISS-WO_CW_-2] + 
             [total_ISS-WO_CW_-3] + [total_ISS-WO_CW_-4]) = 0 
        THEN 'No Consumption' 
        ELSE 'Active' 
    END AS [Consumption_Status]
FROM WeeklyPivot
ORDER BY tr_site, tr_part;