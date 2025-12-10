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
        [sod_cum_qty[2]]] AS sod_cum_qty_2,
        [sod_cum_date[1]]] AS sod_cum_date_1,
        [sod_curr_rlse_id[1]]] AS sod_curr_rlse_id_1,
        [sod_curr_rlse_id[3]]] AS sod_curr_rlse_id_3,
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
)

SELECT
    SOD.[so_ship] AS [Ship-to],
    SCH.[sch_nbr] AS [SO],
    SCH.[sch_line] AS [SO Line],
    SOD.[sod_part] AS [Item Number],
    FORMAT(SCH.[sch_pcs_date], 'dd/MM/yyyy') AS [Prior Cum Date],
    CAST(SCH.[sch_pcr_qty] AS INT) AS [Prior Cum Req Qty],
    CAST(SOD.[sod_cum_qty_1] AS INT) AS [Cum Shipped],
    CAST(SCH.[sch_pcr_qty] - SOD.[sod_cum_qty_1] AS INT) AS [Past Due],
    SCH.[WeekNumber] AS [WeekNumber],
    CAST(SCH.[TotalDiscrQty] AS INT) AS [EDI_Qty],
    DATENAME(MONTH, SCH.[WeekStartDate]) AS [Month],
    SCH.[Year] AS [Year],
    -- Past Due flag: 'Past' if week is before current week, else blank
    CASE WHEN SCH.[WeekStartDate] < DATEADD(WEEK, DATEDIFF(WEEK, 0, GETDATE()), 0) 
         THEN 'Past' 
         ELSE '' 
    END AS [Past Due]
FROM SCH_Data SCH
INNER JOIN SOD_SO_Joined SOD
    ON SCH.[sch_nbr] = SOD.[sod_nbr]
    AND SCH.[sch_line] = SOD.[sod_line]
ORDER BY 
    SCH.[WeekNumber],
    SCH.[sch_line];