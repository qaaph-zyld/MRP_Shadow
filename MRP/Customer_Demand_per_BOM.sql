-- Component Explosion Query: Customer Items to Raw Material Requirements
-- Integrates schedule data with BOM hierarchy for component-level demand calculation

WITH SCH_Data AS (
    SELECT
        m.[sch_nbr],
        m.[sch_line],
        m.[sch_rlse_id],
        DATEPART(WEEK, d.[schd_date]) AS [WeekNumber],
        SUM(d.[schd_discr_qty]) AS [TotalDiscrQty],
        m.[sch_pcr_qty],
        m.[sch_pcs_date],
        m.[sch_lr_asn[1]]],
        m.[sch_lr_qty[1]]],
        m.[sch_lr_cum_qty[1]]],
        DATEPART(YEAR, d.[schd_date]) AS [Year],
        MIN(DATEADD(DAY, 1 - DATEPART(WEEKDAY, d.[schd_date]), CAST(d.[schd_date] AS DATE))) AS [WeekStartDate]
    FROM 
        [QADEE2798].[dbo].[sch_mstr] m
    INNER JOIN 
        [QADEE2798].[dbo].[active_schd_det] d
        ON m.[sch_nbr] = d.[schd_nbr]
        AND m.[sch_line] = d.[schd_line]
        AND m.[sch_rlse_id] = d.[schd_rlse_id]
    WHERE 
        m.[sch_eff_end] IS NULL 
        AND m.[sch_pcr_qty] > 0
    GROUP BY
        m.[sch_nbr], m.[sch_line], m.[sch_rlse_id],
        m.[sch_pcr_qty], m.[sch_pcs_date], m.[sch_lr_asn[1]]],
        m.[sch_lr_qty[1]]], m.[sch_lr_cum_qty[1]]],
        DATEPART(WEEK, d.[schd_date]),
        DATEPART(YEAR, d.[schd_date])
),

SOD_Data AS (
    SELECT 
        [sod_nbr],
        [sod_line],
        [sod_part],
        [sod_loc],
        [sod_std_cost],
        [sod_custpart],
        [sod_site],
        [sod_prodline],
        [sod_contr_id],
        [sod_cum_qty[1]]] AS sod_cum_qty_1,
        [sod_cum_date[1]]] AS sod_cum_date_1,
        [sod_curr_rlse_id[1]]] AS sod_curr_rlse_id_1,
        [sod_custref],
        [sod_unadjust_cum_qty]
    FROM [QADEE2798].[dbo].[sod_det]
    WHERE [sod_status] IS NULL 
      AND ([sod_end_eff[1]]] > CAST(GETDATE() AS DATE) OR [sod_end_eff[1]]] IS NULL)
      AND [sod_curr_rlse_id[1]]] IS NOT NULL
),

SO_Data AS (
    SELECT 
        [so_nbr],
        CAST([so_ship] AS VARCHAR(255)) AS so_ship,
        [so_fob],
        [so_ship_date],
        [so_bol],
        [so_site]
    FROM [QADEE2798].[dbo].[so_mstr]
),

SOD_SO_Joined AS (
    SELECT 
        SOD.*,
        SO.[so_ship],
        SO.[so_ship_date]
    FROM SOD_Data SOD
    LEFT JOIN SO_Data SO
        ON SOD.[sod_nbr] = SO.[so_nbr]
),

-- Base schedule data with customer items
BaseScheduleData AS (
    SELECT
        SOD.[sod_part] AS [Item_Number],
        SCH.[WeekNumber] AS [WeekNumber],
        CAST(SCH.[TotalDiscrQty] AS INT) AS [EDI_Qty],
        DATENAME(MONTH, SCH.[WeekStartDate]) AS [Month],
        SCH.[Year] AS [Year],
        CASE WHEN SCH.[WeekStartDate] < DATEADD(WEEK, DATEDIFF(WEEK, 0, GETDATE()), 0) 
             THEN 'Past' 
             ELSE '' 
        END AS [Past_Due]
    FROM SCH_Data SCH
    INNER JOIN SOD_SO_Joined SOD
        ON SCH.[sch_nbr] = SOD.[sod_nbr]
        AND SCH.[sch_line] = SOD.[sod_line]
),

-- Customer items identification
CustomerItems AS (
    SELECT DISTINCT [sod_part] AS ItemNumber 
    FROM [QADEE2798].[dbo].[sod_det] 
),

-- Combined product structure
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

-- BOM hierarchy with recursive CTE
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
    WHERE h.LEVEL < 10
),

-- Component mapping for customer items
ComponentMapping AS (
    SELECT 
        h.root_parent AS [Parent_Item],
        h.component AS [ps_comp],
        h.ps_qty_per AS [Quantity_Per]
    FROM BOMHierarchy h
    WHERE h.root_parent IN (SELECT ItemNumber FROM CustomerItems)
    AND h.[Structure_Type] = 'RM'
)

-- Final result: Component explosion with quantity calculation
SELECT 
    CM.ps_comp AS [Item_Number],
    (CM.Quantity_Per * BSD.EDI_Qty) AS [Quantity_Per_EDI],
    BSD.Year,
    BSD.Month,
    BSD.WeekNumber,
    BSD.Past_Due
FROM BaseScheduleData BSD
INNER JOIN ComponentMapping CM
    ON BSD.Item_Number = CM.Parent_Item
ORDER BY 
    BSD.Year,
    BSD.WeekNumber,
    CM.ps_comp;