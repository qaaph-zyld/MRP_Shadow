/*
WIP Overstock Analysis Report
----------------------------
This query identifies and analyzes items with WIP inventory outside the optimal range.
It is derived from the Item_Master_WIP_minimum.sql query.

Purpose:
- Identify items with WIP inventory exceeding maximum thresholds or below minimum thresholds
- Quantify the financial impact of WIP overstock or understock
- Support inventory optimization initiatives by highlighting key areas for adjustment

Usage:
- Use for targeted inventory reduction or replenishment initiatives
- Integrate with visualization tools for trend analysis and monitoring
- Support financial reporting on excess inventory carrying costs
*/

WITH CombinedParts AS (
    SELECT 
        [pt_part],
        [pt_site],
        [pt_added]
    FROM [QADEE2798].[dbo].[pt_mstr]
    WHERE [pt_part_type] NOT IN ('xc','rc')
    
    UNION ALL
    
    SELECT 
        [pt_part],
        [pt_site],
        [pt_added]
    FROM [QADEE].[dbo].[pt_mstr]
    WHERE [pt_part_type] NOT IN ('xc','rc')
),

BOMStatusCTE AS (
    SELECT 
        Plant,
        [Item Number],
        MAX(CASE WHEN [Parent] = 'Yes' THEN 'Yes' ELSE 'No' END) AS [Parent],
        MAX(CASE WHEN [Child] = 'Yes' THEN 'Yes' ELSE 'No' END) AS [Child],
        MAX(CASE WHEN [SFG] = 'Yes' THEN 'Yes' ELSE 'No' END) AS [SFG]
    FROM (
        -- Combined BOM data from both databases
        SELECT DISTINCT  
            '2674' AS [Plant],  
            [ps_par] AS [Item Number],  
            'Yes' AS [Parent],
            NULL AS [Child],
            NULL AS [SFG]
        FROM [QADEE].[dbo].[ps_mstr]  
        WHERE [ps_end] IS NULL

        UNION ALL  

        SELECT DISTINCT  
            '2798' AS [Plant],  
            [ps_par] AS [Item Number],  
            'Yes' AS [Parent],
            NULL AS [Child],
            NULL AS [SFG]
        FROM [QADEE2798].[dbo].[ps_mstr]  
        WHERE [ps_end] IS NULL

        UNION ALL

        SELECT DISTINCT  
            '2674' AS [Plant],  
            [ps_comp] AS [Item Number],  
            NULL AS [Parent],
            'Yes' AS [Child],
            NULL AS [SFG]
        FROM [QADEE].[dbo].[ps_mstr]  
        WHERE [ps_end] IS NULL

        UNION ALL  

        SELECT DISTINCT  
            '2798' AS [Plant],  
            [ps_comp] AS [Item Number],  
            NULL AS [Parent],
            'Yes' AS [Child],
            NULL AS [SFG]
        FROM [QADEE2798].[dbo].[ps_mstr]  
        WHERE [ps_end] IS NULL

        UNION ALL

        SELECT DISTINCT  
            '2674' AS [Plant],  
            [ps_comp] AS [Item Number],  
            NULL AS [Parent],
            NULL AS [Child],
            'Yes' AS [SFG]
        FROM [QADEE].[dbo].[ps_mstr]  
        WHERE [ps_end] IS NULL
        AND [ps_par] IN (
            SELECT DISTINCT [ps_comp]
            FROM [QADEE].[dbo].[ps_mstr]
            WHERE [ps_end] IS NULL
        )

        UNION ALL  

        SELECT DISTINCT  
            '2798' AS [Plant],  
            [ps_comp] AS [Item Number],  
            NULL AS [Parent],
            NULL AS [Child],
            'Yes' AS [SFG]
        FROM [QADEE2798].[dbo].[ps_mstr]  
        WHERE [ps_end] IS NULL
        AND [ps_par] IN (
            SELECT DISTINCT [ps_comp]
            FROM [QADEE2798].[dbo].[ps_mstr]
            WHERE [ps_end] IS NULL
        )
    ) AS BOMData
    GROUP BY Plant, [Item Number]
),

ItemCosts AS (
    SELECT 
        [sct_site],
        [sct_part],
        ([sct_mtl_tl] + [sct_mtl_ll]) AS [Material Cost],
        [sct_cst_tot] AS [Standard Cost],
        ([sct_cst_tot] - ([sct_mtl_tl] + [sct_mtl_ll])) AS [LBO]
    FROM [QADEE2798].[dbo].[sct_det]
    WHERE [sct_sim] = 'standard'
    
    UNION ALL
    
    SELECT 
        [sct_site],
        [sct_part],
        ([sct_mtl_tl] + [sct_mtl_ll]) AS [Material Cost],
        [sct_cst_tot] AS [Standard Cost],
        ([sct_cst_tot] - ([sct_mtl_tl] + [sct_mtl_ll])) AS [LBO]
    FROM [QADEE].[dbo].[sct_det]
    WHERE [sct_sim] = 'standard'
),

ItemDetails AS (
    SELECT 
        [pt_site], 
        [pt_part], 
        [pt_desc1] AS [Item Description], 
        [pt_desc2],
        [pt_prod_line] AS [Prod Line], 
        [pt_group] AS [Group], 
        [pt_part_type], 
        [pt_status] AS [Item Number Status],
        [pt_added] AS [Date added],
        [pt_abc] AS [ABC], 
        [pt_cyc_int], 
        [pt_sfty_stk] AS [Safety Stock], 
        [pt_sfty_time] AS [Safety Time], 
        [pt_buyer] AS [Item Planner], 
        [pt_vend] AS [Item Supplier], 
        [pt_routing] AS [Routing], 
        [pt_net_wt] AS [Net weight], 
        [pt_net_wt_um], 
        [pt__chr02] AS [Item Type], 
        [pt_dsgn_grp] AS [Project]
    FROM [QADEE2798].[dbo].[pt_mstr]
    
    UNION ALL
    
    SELECT 
        [pt_site], 
        [pt_part], 
        [pt_desc1] AS [Item Description], 
        [pt_desc2],
        [pt_prod_line] AS [Prod Line], 
        [pt_group] AS [Group], 
        [pt_part_type], 
        [pt_status] AS [Item Number Status],
        [pt_added] AS [Date added],
        [pt_abc] AS [ABC], 
        [pt_cyc_int], 
        [pt_sfty_stk] AS [Safety Stock], 
        [pt_sfty_time] AS [Safety Time], 
        [pt_buyer] AS [Item Planner], 
        [pt_vend] AS [Item Supplier], 
        [pt_routing] AS [Routing], 
        [pt_net_wt] AS [Net weight], 
        [pt_net_wt_um], 
        [pt__chr02] AS [Item Type], 
        [pt_dsgn_grp] AS [Project]
    FROM [QADEE].[dbo].[pt_mstr]
),

InventoryInfo AS (
    SELECT 
        [in_site],
        [in_part],
        [in_qty_oh] AS [Total Qty Nettable],
        [in_qty_nonet] AS [Total Qty Nonet],
        [in_qty_oh] + [in_qty_nonet] AS [Total Inv],
        [in_iss_date],
        DATEDIFF(DAY, [in_iss_date], GETDATE()) AS [Last_ISSUE],
        DATEDIFF(DAY, [in_rec_date], GETDATE()) AS [Last_REC],
        DATEDIFF(DAY, [in_cnt_date], GETDATE()) AS [Last_CC],
        CASE
            WHEN [in_iss_date] IS NULL THEN 'No transactions'
            WHEN DATEDIFF(MONTH, [in_iss_date], GETDATE()) > 12 THEN '12 months'
            WHEN DATEDIFF(MONTH, [in_iss_date], GETDATE()) > 6 THEN '6 months'
            WHEN DATEDIFF(MONTH, [in_iss_date], GETDATE()) > 3 THEN '3 months'
            ELSE 'Active'
        END AS [Obsolete]
    FROM 
        [QADEE].[dbo].[in_mstr]
    
    UNION ALL
    
    SELECT 
        [in_site],
        [in_part],
        [in_qty_oh] AS [Total Qty Nettable],
        [in_qty_nonet] AS [Total Qty Nonet],
        [in_qty_oh] + [in_qty_nonet] AS [Total Inv],
        [in_iss_date],
        DATEDIFF(DAY, [in_iss_date], GETDATE()) AS [Last_ISSUE],
        DATEDIFF(DAY, [in_rec_date], GETDATE()) AS [Last_REC],
        DATEDIFF(DAY, [in_cnt_date], GETDATE()) AS [Last_CC],
        CASE
            WHEN [in_iss_date] IS NULL THEN 'No transactions'
            WHEN DATEDIFF(MONTH, [in_iss_date], GETDATE()) > 12 THEN '12 months'
            WHEN DATEDIFF(MONTH, [in_iss_date], GETDATE()) > 6 THEN '6 months'
            WHEN DATEDIFF(MONTH, [in_iss_date], GETDATE()) > 3 THEN '3 months'
            ELSE 'Active'
        END AS [Obsolete]
    FROM 
        [QADEE2798].[dbo].[15]
),

InventoryByArea AS (
    SELECT
        ld.[ld_site] AS [Plant],
        ld.[ld_part] AS [Item Number],
        SUM(CASE WHEN xz.[xxwezoned_area_id] = 'WH' THEN ld.[ld_qty_oh] ELSE 0 END) AS [WH_Qty],
        SUM(CASE WHEN xz.[xxwezoned_area_id] = 'WIP' THEN ld.[ld_qty_oh] ELSE 0 END) AS [WIP_Qty],
        SUM(CASE WHEN xz.[xxwezoned_area_id] = 'EXLPICK' THEN ld.[ld_qty_oh] ELSE 0 END) AS [EXLPICK_Qty]
    FROM 
        [QADEE2798].[dbo].[ld_det] ld
    JOIN 
        [QADEE2798].[dbo].[xxwezoned_det] xz
    ON 
        ld.[ld_loc] = xz.[xxwezoned_loc]
    GROUP BY
        ld.[ld_site],
        ld.[ld_part]
    
    UNION ALL
    
    SELECT
        ld.[ld_site] AS [Plant],
        ld.[ld_part] AS [Item Number],
        SUM(CASE WHEN xz.[xxwezoned_area_id] = 'WH' THEN ld.[ld_qty_oh] ELSE 0 END) AS [WH_Qty],
        SUM(CASE WHEN xz.[xxwezoned_area_id] = 'WIP' THEN ld.[ld_qty_oh] ELSE 0 END) AS [WIP_Qty],
        SUM(CASE WHEN xz.[xxwezoned_area_id] = 'EXLPICK' THEN ld.[ld_qty_oh] ELSE 0 END) AS [EXLPICK_Qty]
    FROM 
        [QADEE].[dbo].[ld_det] ld
    JOIN 
        [QADEE].[dbo].[xxwezoned_det] xz
    ON 
        ld.[ld_loc] = xz.[xxwezoned_loc]
    GROUP BY
        ld.[ld_site],
        ld.[ld_part]
),

-- WIP Minimum and Maximum Data CTEs
DailyISS_WO AS (
    SELECT
        tr_part,
        tr_site,
        tr_effdate,
        SUM(tr_qty_loc) AS Daily_Qty
    FROM [QADEE2798].[dbo].[tr_hist]
    WHERE tr_type = 'iss-wo'
      AND tr_effdate >= DATEADD(WEEK, -4, GETDATE())
    GROUP BY
        tr_part,
        tr_site,
        tr_effdate
    
    UNION ALL
    
    SELECT
        tr_part,
        tr_site,
        tr_effdate,
        SUM(tr_qty_loc) AS Daily_Qty
    FROM [QADEE].[dbo].[tr_hist]
    WHERE tr_type = 'iss-wo'
      AND tr_effdate >= DATEADD(WEEK, -4, GETDATE())
    GROUP BY
        tr_part,
        tr_site,
        tr_effdate
),

-- Get the current week number and year
CurrentWeekInfo AS (
    SELECT 
        DATEPART(YEAR, GETDATE()) AS CurrentYear,
        DATEPART(WEEK, GETDATE()) AS CurrentWeek
),

-- Weekly ISS-WO data with relative week calculations (last 4 weeks only)
WeeklyISS_WO AS (
    SELECT
        d.tr_part,
        d.tr_site,
        DATEPART(YEAR, d.tr_effdate) AS YearNumber,
        DATEPART(WEEK, d.tr_effdate) AS WeekNumber,
        cw.CurrentYear,
        cw.CurrentWeek,
        -- Calculate relative week position
        CASE
            WHEN DATEPART(YEAR, d.tr_effdate) = cw.CurrentYear THEN
                cw.CurrentWeek - DATEPART(WEEK, d.tr_effdate)
            ELSE
                cw.CurrentWeek + (52 - DATEPART(WEEK, d.tr_effdate))
        END AS WeeksAgo,
        d.Daily_Qty
    FROM DailyISS_WO d
    CROSS JOIN CurrentWeekInfo cw
    WHERE d.tr_effdate >= DATEADD(WEEK, -4, GETDATE())
),

-- Get distinct part/site combinations
DistinctPartSites AS (
    SELECT DISTINCT
        tr_part,
        tr_site
    FROM WeeklyISS_WO
),

-- Calculate weekly averages for each part/site
WeeklyAverages AS (
    SELECT
        dps.tr_part,
        dps.tr_site,
        -- Average daily iss-wo for previous week (Week -1)
        ISNULL((
            SELECT AVG(Daily_Qty)*(-1)
            FROM WeeklyISS_WO w
            WHERE w.tr_part = dps.tr_part
              AND w.tr_site = dps.tr_site
              AND w.WeeksAgo = 1
        ), 0) AS [avg_ISS-WO_CW_-1],
        
        -- Average daily iss-wo for 2 weeks ago (Week -2)
        ISNULL((
            SELECT AVG(Daily_Qty)*(-1)
            FROM WeeklyISS_WO w
            WHERE w.tr_part = dps.tr_part
              AND w.tr_site = dps.tr_site
              AND w.WeeksAgo = 2
        ), 0) AS [avg_ISS-WO_CW_-2],
        
        -- Average daily iss-wo for 3 weeks ago (Week -3)
        ISNULL((
            SELECT AVG(Daily_Qty)*(-1)
            FROM WeeklyISS_WO w
            WHERE w.tr_part = dps.tr_part
              AND w.tr_site = dps.tr_site
              AND w.WeeksAgo = 3
        ), 0) AS [avg_ISS-WO_CW_-3],
        
        -- Average daily iss-wo for 4 weeks ago (Week -4)
        ISNULL((
            SELECT AVG(Daily_Qty)*(-1)
            FROM WeeklyISS_WO w
            WHERE w.tr_part = dps.tr_part
              AND w.tr_site = dps.tr_site
              AND w.WeeksAgo = 4
        ), 0) AS [avg_ISS-WO_CW_-4]
    FROM DistinctPartSites dps
),

-- Final result set with WIP_minimum and WIP_maximum calculation
WIPMinimumData AS (
    SELECT
        wa.tr_part,
        wa.tr_site,
        wa.[avg_ISS-WO_CW_-1],
        wa.[avg_ISS-WO_CW_-2],
        wa.[avg_ISS-WO_CW_-3],
        wa.[avg_ISS-WO_CW_-4],
        -- Calculate WIP_minimum as 3x average of last 4 weeks
        (wa.[avg_ISS-WO_CW_-1] + wa.[avg_ISS-WO_CW_-2] + 
         wa.[avg_ISS-WO_CW_-3] + wa.[avg_ISS-WO_CW_-4]) / 4 * 3 AS [WIP_minimum],
        -- Calculate WIP_maximum as 7x average of last 4 weeks
        (wa.[avg_ISS-WO_CW_-1] + wa.[avg_ISS-WO_CW_-2] + 
         wa.[avg_ISS-WO_CW_-3] + wa.[avg_ISS-WO_CW_-4]) / 4 * 7 AS [WIP_maximum]
    FROM WeeklyAverages wa
)

-- Main query that identifies and summarizes items with WIP inventory outside optimal range
SELECT
    cp.[pt_site] AS [Plant],
    ISNULL(id.[Project], 'No Project') AS [Project],
    CASE
        WHEN ISNULL(b.[SFG], 'No') = 'Yes' THEN 'SFG'
        WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'Yes' THEN 'FG'
        WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'No' AND ISNULL(b.[Child], 'No') = 'Yes' THEN 'RM'
        ELSE 'No BOM'
    END AS [FG/SFG/RM],
    id.[Prod Line],
    id.[Group],
    cp.[pt_part] AS [Item Number],
    ic.[Standard Cost],
    ic.[Material Cost],
    id.[Item Description],
    -- WIP analysis columns
    wip.[WIP_minimum],
    wip.[WIP_maximum],
    CASE 
        WHEN ia.[WIP_Qty] > wip.[WIP_maximum] THEN 
            ia.[WIP_Qty] - wip.[WIP_maximum]
        WHEN ia.[WIP_Qty] < wip.[WIP_minimum] THEN
            ia.[WIP_Qty] - wip.[WIP_minimum]
        ELSE NULL
    END AS [WIP_overstock],
    CASE 
        WHEN ia.[WIP_Qty] > wip.[WIP_maximum] THEN 
            (ia.[WIP_Qty] - wip.[WIP_maximum]) * ic.[Standard Cost]
        WHEN ia.[WIP_Qty] < wip.[WIP_minimum] THEN
            (ia.[WIP_Qty] - wip.[WIP_minimum]) * ic.[Standard Cost]
        ELSE 0
    END AS [WIP_overstock_Value],
    -- ISS-WO weekly averages
    wip.[avg_ISS-WO_CW_-1],
    wip.[avg_ISS-WO_CW_-2],
    wip.[avg_ISS-WO_CW_-3],
    wip.[avg_ISS-WO_CW_-4],
    -- Summarized quantities
    SUM(ia.[WH_Qty]) AS [WH_Qty],
    SUM(ia.[WIP_Qty]) AS [WIP_Qty],
    SUM(ia.[EXLPICK_Qty]) AS [EXLPICK_Qty],
    -- Summarized values
    SUM(ia.[WH_Qty] * ic.[Standard Cost]) AS [WH_Value],
    SUM(ia.[WIP_Qty] * ic.[Standard Cost]) AS [WIP_Value],
    SUM(ia.[EXLPICK_Qty] * ic.[Standard Cost]) AS [EXLPICK_Value],
    SUM(ii.[Total Inv] * ic.[Standard Cost]) AS [Total COGS]
FROM 
    CombinedParts cp
LEFT JOIN 
    BOMStatusCTE b
ON 
    cp.[pt_site] = b.[Plant] 
    AND cp.[pt_part] = b.[Item Number]
LEFT JOIN
    ItemCosts ic
ON
    cp.[pt_site] = ic.[sct_site]
    AND cp.[pt_part] = ic.[sct_part]
LEFT JOIN
    ItemDetails id
ON
    cp.[pt_site] = id.[pt_site]
    AND cp.[pt_part] = id.[pt_part]
LEFT JOIN
    InventoryInfo ii
ON
    cp.[pt_site] = ii.[in_site]
    AND cp.[pt_part] = ii.[in_part]
LEFT JOIN
    InventoryByArea ia
ON
    cp.[pt_site] = ia.[Plant]
    AND cp.[pt_part] = ia.[Item Number]
LEFT JOIN
    WIPMinimumData wip
ON
    cp.[pt_part] = wip.[tr_part]
    AND cp.[pt_site] = wip.[tr_site]
WHERE
    -- Filter for items with WIP inventory outside optimal range
    (ia.[WIP_Qty] > wip.[WIP_maximum] OR ia.[WIP_Qty] < wip.[WIP_minimum])
    AND wip.[WIP_minimum] IS NOT NULL  -- Ensure we have WIP minimum data
    AND ia.[WIP_Qty] IS NOT NULL       -- Ensure we have WIP quantity data
    AND ii.[Total Inv] > 0             -- Only include items with inventory
GROUP BY
    cp.[pt_site],
    ISNULL(id.[Project], 'No Project'),
    CASE
        WHEN ISNULL(b.[SFG], 'No') = 'Yes' THEN 'SFG'
        WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'Yes' THEN 'FG'
        WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'No' AND ISNULL(b.[Child], 'No') = 'Yes' THEN 'RM'
        ELSE 'No BOM'
    END,
    id.[Prod Line],
    id.[Group],
    cp.[pt_part],
    ic.[Standard Cost],
    ic.[Material Cost],
    id.[Item Description],
    wip.[WIP_minimum],
    wip.[WIP_maximum],
    CASE 
        WHEN ia.[WIP_Qty] > wip.[WIP_maximum] THEN 
            ia.[WIP_Qty] - wip.[WIP_maximum]
        WHEN ia.[WIP_Qty] < wip.[WIP_minimum] THEN
            ia.[WIP_Qty] - wip.[WIP_minimum]
        ELSE NULL
    END,
    CASE 
        WHEN ia.[WIP_Qty] > wip.[WIP_maximum] THEN 
            (ia.[WIP_Qty] - wip.[WIP_maximum]) * ic.[Standard Cost]
        WHEN ia.[WIP_Qty] < wip.[WIP_minimum] THEN
            (ia.[WIP_Qty] - wip.[WIP_minimum]) * ic.[Standard Cost]
        ELSE 0
    END,
    wip.[avg_ISS-WO_CW_-1],
    wip.[avg_ISS-WO_CW_-2],
    wip.[avg_ISS-WO_CW_-3],
    wip.[avg_ISS-WO_CW_-4],
    ia.[WIP_Qty]
ORDER BY 
    ABS(CASE 
        WHEN ia.[WIP_Qty] > wip.[WIP_maximum] THEN 
            (ia.[WIP_Qty] - wip.[WIP_maximum]) * ic.[Standard Cost]
        WHEN ia.[WIP_Qty] < wip.[WIP_minimum] THEN
            (ia.[WIP_Qty] - wip.[WIP_minimum]) * ic.[Standard Cost]
        ELSE 0
    END) DESC,  -- Order by absolute financial impact (highest first)
    [Plant], 
    [Project], 
    [FG/SFG/RM];
