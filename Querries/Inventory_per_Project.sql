/*
Inventory Per Project Report (2798 Only)
----------------------------------------
Provides a summarized view of inventory data grouped by project, plant, and other key dimensions.
Derived from Item_Master_WIP_minimum logic, cleaned for single-plant (2798) operation.

Purpose:
- Analyze inventory distribution across different projects
- Track WIP and warehouse quantities by project and product category
- Identify high-value inventory areas for optimization
*/

WITH CombinedParts AS (
    SELECT 
        [pt_part],
        [pt_site],
        [pt_added]
    FROM [QADEE2798].[dbo].[pt_mstr]
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
            '2798' AS [Plant],  
            [ps_comp] AS [Item Number],  
            NULL AS [Parent],
            'Yes' AS [Child],
            NULL AS [SFG]
        FROM [QADEE2798].[dbo].[ps_mstr]  
        WHERE [ps_end] IS NULL

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
        [QADEE2798].[dbo].[in_mstr]
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
),

CurrentWeekInfo AS (
    SELECT 
        DATEPART(YEAR, GETDATE()) AS CurrentYear,
        DATEPART(WEEK, GETDATE()) AS CurrentWeek
),

WeeklyISS_WO AS (
    SELECT
        d.tr_part,
        d.tr_site,
        DATEPART(YEAR, d.tr_effdate) AS YearNumber,
        DATEPART(WEEK, d.tr_effdate) AS WeekNumber,
        cw.CurrentYear,
        cw.CurrentWeek,
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

DistinctPartSites AS (
    SELECT DISTINCT
        tr_part,
        tr_site
    FROM WeeklyISS_WO
),

WeeklyAverages AS (
    SELECT
        dps.tr_part,
        dps.tr_site,
        ISNULL((SELECT AVG(Daily_Qty)*(-1) FROM WeeklyISS_WO w 
                WHERE w.tr_part = dps.tr_part AND w.tr_site = dps.tr_site AND w.WeeksAgo = 1), 0) AS [avg_ISS-WO_CW_-1],
        ISNULL((SELECT AVG(Daily_Qty)*(-1) FROM WeeklyISS_WO w 
                WHERE w.tr_part = dps.tr_part AND w.tr_site = dps.tr_site AND w.WeeksAgo = 2), 0) AS [avg_ISS-WO_CW_-2],
        ISNULL((SELECT AVG(Daily_Qty)*(-1) FROM WeeklyISS_WO w 
                WHERE w.tr_part = dps.tr_part AND w.tr_site = dps.tr_site AND w.WeeksAgo = 3), 0) AS [avg_ISS-WO_CW_-3],
        ISNULL((SELECT AVG(Daily_Qty)*(-1) FROM WeeklyISS_WO w 
                WHERE w.tr_part = dps.tr_part AND w.tr_site = dps.tr_site AND w.WeeksAgo = 4), 0) AS [avg_ISS-WO_CW_-4]
    FROM DistinctPartSites dps
),

WIPMinimumData AS (
    SELECT
        wa.tr_part,
        wa.tr_site,
        wa.[avg_ISS-WO_CW_-1],
        wa.[avg_ISS-WO_CW_-2],
        wa.[avg_ISS-WO_CW_-3],
        wa.[avg_ISS-WO_CW_-4],
        (wa.[avg_ISS-WO_CW_-1] + wa.[avg_ISS-WO_CW_-2] + 
         wa.[avg_ISS-WO_CW_-3] + wa.[avg_ISS-WO_CW_-4]) / 4 * 3 AS [WIP_minimum],
        (wa.[avg_ISS-WO_CW_-1] + wa.[avg_ISS-WO_CW_-2] + 
         wa.[avg_ISS-WO_CW_-3] + wa.[avg_ISS-WO_CW_-4]) / 4 * 7 AS [WIP_maximum]
    FROM WeeklyAverages wa
)

-- Main query that groups and summarizes inventory data by project
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
    BOMStatusCTE b ON cp.[pt_site] = b.[Plant] AND cp.[pt_part] = b.[Item Number]
LEFT JOIN
    ItemCosts ic ON cp.[pt_site] = ic.[sct_site] AND cp.[pt_part] = ic.[sct_part]
LEFT JOIN
    ItemDetails id ON cp.[pt_site] = id.[pt_site] AND cp.[pt_part] = id.[pt_part]
LEFT JOIN
    InventoryInfo ii ON cp.[pt_site] = ii.[in_site] AND cp.[pt_part] = ii.[in_part]
LEFT JOIN
    InventoryByArea ia ON cp.[pt_site] = ia.[Plant] AND cp.[pt_part] = ia.[Item Number]
LEFT JOIN
    WIPMinimumData wip ON cp.[pt_part] = wip.[tr_part] AND cp.[pt_site] = wip.[tr_site]
WHERE
    ii.[Total Inv] > 0  -- Only include items with inventory (Inventory check = yes)
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
    id.[Item Description]
ORDER BY 
    [Plant], 
    [Project], 
    [FG/SFG/RM];
