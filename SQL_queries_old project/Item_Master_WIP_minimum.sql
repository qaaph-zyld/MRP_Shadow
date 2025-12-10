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
ParentCTE AS (
    SELECT DISTINCT  
        '2674' AS [Plant],  
        [ps_par] AS [Item Number],  
        'Yes' AS [Parent]
    FROM   
        [QADEE].[dbo].[ps_mstr]  
    WHERE   
        [ps_end] IS NULL

    UNION ALL  

    SELECT DISTINCT  
        '2798' AS [Plant],  
        [ps_par] AS [Item Number],  
        'Yes' AS [Parent]
    FROM   
        [QADEE2798].[dbo].[ps_mstr]  
    WHERE   
        [ps_end] IS NULL
),
ChildCTE AS (
    SELECT DISTINCT  
        '2674' AS [Plant],  
        [ps_comp] AS [Item Number],  
        'Yes' AS [Child]
    FROM   
        [QADEE].[dbo].[ps_mstr]  
    WHERE   
        [ps_end] IS NULL  

    UNION ALL  

    SELECT DISTINCT  
        '2798' AS [Plant],  
        [ps_comp] AS [Item Number],  
        'Yes' AS [Child]
    FROM   
        [QADEE2798].[dbo].[ps_mstr]  
    WHERE   
        [ps_end] IS NULL  
),
BOMStatusCTE AS (
    SELECT 
        COALESCE(p.[Plant], c.[Plant]) AS [Plant],  
        COALESCE(p.[Item Number], c.[Item Number]) AS [Item Number],  
        ISNULL(p.[Parent], 'No') AS [Parent],  
        ISNULL(c.[Child], 'No') AS [Child],  
        CASE 
            WHEN p.[Parent] = 'Yes' AND c.[Child] = 'Yes' THEN 'Yes' 
            ELSE 'No' 
        END AS [SFG]
    FROM 
        ParentCTE p
    FULL OUTER JOIN 
        ChildCTE c
    ON 
        p.[Plant] = c.[Plant] 
        AND p.[Item Number] = c.[Item Number]
),
PsOpCTE AS (
    SELECT DISTINCT
        '2674' AS [Plant],
        [ps_par] AS [Item Number],
        [ps_op] AS [Operation]
    FROM
        [QADEE].[dbo].[ps_mstr]
    WHERE
        [ps_end] IS NULL

    UNION ALL

    SELECT DISTINCT
        '2798' AS [Plant],
        [ps_par] AS [Item Number],
        [ps_op] AS [Operation]
    FROM
        [QADEE2798].[dbo].[ps_mstr]
    WHERE
        [ps_end] IS NULL
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
ItemCosts AS (
    SELECT
        [sct_site],
        [sct_part],
        [sct_cst_tot] AS [Standard Cost],
        ([sct_mtl_tl] + [sct_mtl_ll]) AS [Material Cost],
        ([sct_cst_tot] - ([sct_mtl_tl] + [sct_mtl_ll])) AS [LBO]
    FROM 
        [QADEE2798].[dbo].[sct_det]
    WHERE 
        [sct_sim] = 'standard'
    
    UNION
    
    SELECT
        [sct_site],
        [sct_part],
        [sct_cst_tot] AS [Standard Cost],
        ([sct_mtl_tl] + [sct_mtl_ll]) AS [Material Cost],
        ([sct_cst_tot] - ([sct_mtl_tl] + [sct_mtl_ll])) AS [LBO]
    FROM 
        [QADEE].[dbo].[sct_det]
    WHERE 
        [sct_sim] = 'standard'
),
ItemDetails AS (
    SELECT 
        [pt_site], 
        [pt_part], 
        [pt_desc1] AS [Item Description], 
        [pt_desc2] AS [pt_desc2], 
        [pt_prod_line] AS [Prod Line], 
        [pt_group] AS [Group], 
        [pt_part_type] AS [pt_part_type], 
        [pt_status] AS [Item Number Status],
        [pt_added] AS [Date added],
        [pt_abc] AS [ABC], 
        [pt_cyc_int] AS [pt_cyc_int], 
        [pt_sfty_stk] AS [Safety Stock], 
        [pt_sfty_time] AS [Safety Time], 
        [pt_buyer] AS [Item Planner], 
        [pt_vend] AS [Item Supplier], 
        [pt_routing] AS [Routing], 
        [pt_net_wt] AS [Net weight], 
        [pt_net_wt_um] AS [pt_net_wt_um], 
        [pt__chr02] AS [Item Type], 
        [pt_dsgn_grp] AS [Project]
    FROM [QADEE2798].[dbo].[pt_mstr]
    
    UNION
    
    SELECT 
        [pt_site], 
        [pt_part], 
        [pt_desc1] AS [Item Description], 
        [pt_desc2] AS [pt_desc2], 
        [pt_prod_line] AS [Prod Line], 
        [pt_group] AS [Group], 
        [pt_part_type] AS [pt_part_type], 
        [pt_status] AS [Item Number Status],
        [pt_added] AS [Date added],
        [pt_abc] AS [ABC], 
        [pt_cyc_int] AS [pt_cyc_int], 
        [pt_sfty_stk] AS [Safety Stock], 
        [pt_sfty_time] AS [Safety Time], 
        [pt_buyer] AS [Item Planner], 
        [pt_vend] AS [Item Supplier], 
        [pt_routing] AS [Routing], 
        [pt_net_wt] AS [Net weight], 
        [pt_net_wt_um] AS [pt_net_wt_um], 
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
            WHEN DATEDIFF(MONTH, [in_iss_date], GETDATE()) > 12 THEN 'yes' 
            ELSE 'no' 
        END AS [12_months],
        CASE 
            WHEN DATEDIFF(MONTH, [in_iss_date], GETDATE()) > 6 THEN 'yes' 
            ELSE 'no' 
        END AS [6_months],
        CASE 
            WHEN DATEDIFF(MONTH, [in_iss_date], GETDATE()) > 3 THEN 'yes' 
            ELSE 'no' 
        END AS [3_months],
        CASE
            WHEN [in_iss_date] IS NULL THEN 'No transactions'
            WHEN DATEDIFF(MONTH, [in_iss_date], GETDATE()) > 12 THEN '12 months'
            WHEN DATEDIFF(MONTH, [in_iss_date], GETDATE()) > 6 THEN '6 months'
            WHEN DATEDIFF(MONTH, [in_iss_date], GETDATE()) > 3 THEN '3 months'
            ELSE 'Active'
        END AS [Obsolete]
    FROM 
        [QADEE].[dbo].[in_mstr]
    
    UNION
    
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
            WHEN DATEDIFF(MONTH, [in_iss_date], GETDATE()) > 12 THEN 'yes' 
            ELSE 'no' 
        END AS [12_months],
        CASE 
            WHEN DATEDIFF(MONTH, [in_iss_date], GETDATE()) > 6 THEN 'yes' 
            ELSE 'no' 
        END AS [6_months],
        CASE 
            WHEN DATEDIFF(MONTH, [in_iss_date], GETDATE()) > 3 THEN 'yes' 
            ELSE 'no' 
        END AS [3_months],
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
-- Add WIP Minimum data from ISS-WO_WIP_Minimum.sql
-- First identify all distinct part/site combinations from both databases
DistinctPartSites AS (
    SELECT DISTINCT tr_part, tr_site
    FROM (
        SELECT tr_part, tr_site FROM [QADEE2798].[dbo].[tr_hist]
        WHERE tr_type = 'iss-wo'
          AND tr_effdate >= DATEADD(WEEK, -4, GETDATE())
        
        UNION
        
        SELECT tr_part, tr_site FROM [QADEE].[dbo].[tr_hist]
        WHERE tr_type = 'iss-wo'
          AND tr_effdate >= DATEADD(WEEK, -4, GETDATE())
    ) AS CombinedSources
),

-- Daily ISS-WO data (last 4 weeks only)
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

-- Final result set with WIP_minimum calculation
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
        (wa.[avg_ISS-WO_CW_-1] + wa.[avg_ISS-WO_CW_-2] + 
         wa.[avg_ISS-WO_CW_-3] + wa.[avg_ISS-WO_CW_-4]) / 4 * 7 AS [WIP_maximum]
    FROM WeeklyAverages wa
)

SELECT 
    cp.[pt_part] AS [Item Number],
    cp.[pt_site] AS [Plant],
    CASE WHEN COUNT(*) OVER (PARTITION BY cp.pt_part) > 1 
         THEN 'yes' 
         ELSE NULL 
    END AS [Item both plants],
    
    -- Columns from the second query
    ic.[Standard Cost],
    ic.[Material Cost],
    ic.[LBO],
    id.[Item Description], 
    id.[pt_desc2], 
    id.[Prod Line], 
    id.[Group], 
    id.[pt_part_type], 
    id.[Item Number Status],
    id.[Date added],
    id.[ABC], 
    id.[pt_cyc_int], 
    id.[Safety Stock], 
    id.[Safety Time], 
    id.[Item Planner], 
    id.[Item Supplier], 
    id.[Routing], 
    id.[Net weight], 
    id.[pt_net_wt_um], 
    id.[Item Type], 
    id.[Project],
    
    CASE
        WHEN ISNULL(b.[SFG], 'No') = 'Yes' THEN 'SFG'
        WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'Yes' THEN 'FG'
        WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'No' AND ISNULL(b.[Child], 'No') = 'Yes' THEN 'RM'
        ELSE 'No BOM'
    END AS [FG/SFG/RM],
    
    psop.[Operation],
    ii.[Total Qty Nettable],
    ii.[Total Qty Nonet],
    ii.[Total Inv],
    ii.[Last_ISSUE],
    ii.[Last_REC],
    ii.[Last_CC],
    ii.[Obsolete],
    
    (ii.[Total Inv] * ic.[Material Cost]) AS [Total CMAT],
    (ii.[Total Inv] * ic.[Standard Cost]) AS [Total COGS],
    CASE 
        WHEN DATEDIFF(DAY, cp.[pt_added], GETDATE()) < 30 THEN 'New' 
        ELSE NULL 
    END AS [New],
    
    ia.[WH_Qty],
    ia.[WIP_Qty],
    ia.[EXLPICK_Qty],
    ia.[WH_Qty] * ic.[Standard Cost] AS [WH_Value],
    ia.[WIP_Qty] * ic.[Standard Cost] AS [WIP_Value],
    ia.[EXLPICK_Qty] * ic.[Standard Cost] AS [EXLPICK_Value],
    
    -- New columns as requested
    CASE 
        WHEN ii.[Total Inv] <> 0 THEN 'Yes' 
        ELSE 'No' 
    END AS [Inventory Check],
    
    CASE 
        WHEN ic.[Standard Cost] = 0 AND CASE
            WHEN ISNULL(b.[SFG], 'No') = 'Yes' THEN 'SFG'
            WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'Yes' THEN 'FG'
            WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'No' AND ISNULL(b.[Child], 'No') = 'Yes' THEN 'RM'
            ELSE 'No BOM'
        END <> 'No BOM' THEN 'Yes'
        ELSE NULL
    END AS [No Cost - in BOM],
    
    CASE 
        WHEN id.[Prod Line] = '0000' AND CASE
            WHEN ISNULL(b.[SFG], 'No') = 'Yes' THEN 'SFG'
            WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'Yes' THEN 'FG'
            WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'No' AND ISNULL(b.[Child], 'No') = 'Yes' THEN 'RM'
            ELSE 'No BOM'
        END <> 'No BOM' THEN 'Yes'
        ELSE NULL
    END AS [No Prod Line - in BOM],
    
    CASE 
        WHEN id.[Group] = 'F000' AND CASE
            WHEN ISNULL(b.[SFG], 'No') = 'Yes' THEN 'SFG'
            WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'Yes' THEN 'FG'
            WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'No' AND ISNULL(b.[Child], 'No') = 'Yes' THEN 'RM'
            ELSE 'No BOM'
        END <> 'No BOM' THEN 'Yes'
        ELSE NULL
    END AS [No Group - in BOM],
    
    CASE 
        WHEN id.[Item Number Status] = 'EPIC' AND CASE
            WHEN ISNULL(b.[SFG], 'No') = 'Yes' THEN 'SFG'
            WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'Yes' THEN 'FG'
            WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'No' AND ISNULL(b.[Child], 'No') = 'Yes' THEN 'RM'
            ELSE 'No BOM'
        END <> 'No BOM' THEN 'Yes'
        ELSE NULL
    END AS [EPIC- in BOM],
    
    CASE 
        WHEN id.[Group] = 'LTH KIT' OR CASE
            WHEN ISNULL(b.[SFG], 'No') = 'Yes' THEN 'SFG'
            WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'Yes' THEN 'FG'
            WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'No' AND ISNULL(b.[Child], 'No') = 'Yes' THEN 'RM'
            ELSE 'No BOM'
        END IN ('SFG', 'FG') THEN 'A'
        WHEN id.[Group] = 'COMP' THEN 'B'
        WHEN id.[Group] IN ('Thread', 'Rolls') THEN 'C'
        ELSE 'D'
    END AS [ABC_per_group],
    
    CASE 
        WHEN id.[Routing] IS NULL AND CASE
            WHEN ISNULL(b.[SFG], 'No') = 'Yes' THEN 'SFG'
            WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'Yes' THEN 'FG'
            WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'No' AND ISNULL(b.[Child], 'No') = 'Yes' THEN 'RM'
            ELSE 'No BOM'
        END <> 'No BOM' THEN 'Yes'
        ELSE NULL
    END AS [Routing Missing],
    
    CASE 
        WHEN id.[Project] IS NULL AND CASE
            WHEN ISNULL(b.[SFG], 'No') = 'Yes' THEN 'SFG'
            WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'Yes' THEN 'FG'
            WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'No' AND ISNULL(b.[Child], 'No') = 'Yes' THEN 'RM'
            ELSE 'No BOM'
        END <> 'No BOM' THEN 'Yes'
        ELSE NULL
    END AS [Project missing],
    
    CASE 
        WHEN COUNT(cp.[pt_part]) OVER (PARTITION BY cp.[pt_part], psop.[Operation]) > 1 
             AND (CASE WHEN COUNT(*) OVER (PARTITION BY cp.pt_part) > 1 
                  THEN 'yes' 
                  ELSE NULL 
                  END) IS NULL THEN 'Yes'
        ELSE NULL
    END AS [Operation check],
    
    CASE 
        WHEN id.[pt_cyc_int] - ii.[Last_CC] < 5 THEN 'Yes'
        ELSE NULL
    END AS [Cycle Count Due],
    
    CASE 
        WHEN ii.[Last_ISSUE] > 90 AND ii.[Last_ISSUE] < 180 THEN 'Yes'
        ELSE NULL
    END AS [Slow-moving Warning],
    
    CASE 
        WHEN id.[Item Type] <> CASE
            WHEN ISNULL(b.[SFG], 'No') = 'Yes' THEN 'SFG'
            WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'Yes' THEN 'FG'
            WHEN ISNULL(b.[SFG], 'No') = 'No' AND ISNULL(b.[Parent], 'No') = 'No' AND ISNULL(b.[Child], 'No') = 'Yes' THEN 'RM'
            ELSE 'No BOM'
        END THEN 'Yes'
        ELSE NULL
    END AS [Item Type Error],
    
    -- Add columns from ISS-WO_WIP_Minimum.sql
    wip.[avg_ISS-WO_CW_-1],
    wip.[avg_ISS-WO_CW_-2],
    wip.[avg_ISS-WO_CW_-3],
    wip.[avg_ISS-WO_CW_-4],
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
    wip.[WIP_minimum]
    
FROM 
    CombinedParts cp
LEFT JOIN 
    BOMStatusCTE b
ON 
    cp.[pt_site] = b.[Plant] 
    AND cp.[pt_part] = b.[Item Number]
LEFT JOIN 
    PsOpCTE psop
ON
    cp.[pt_site] = psop.[Plant]
    AND cp.[pt_part] = psop.[Item Number]
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
ORDER BY 
    cp.[pt_site], cp.[pt_part];
