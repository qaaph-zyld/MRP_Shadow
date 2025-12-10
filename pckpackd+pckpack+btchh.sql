WITH CurrentMonthData AS (
    SELECT 
        CAST(pm.[pckpack_date] AS DATE) AS [pckpack_date],
        CONVERT(VARCHAR(8), CAST(pm.[pckpack_date] AS TIME), 108) AS [btchh_time],
        pd.[pckpackd_hu],
        pd.[pckpackd_pi],
        pd.[pckpackd_ifs],
        pd.[pckpackd_qty_pack],
		pd.[pckpackd_qty_act],
        pm.[pckpack_set],
        pm.[pckpack_customer],
        pm.[pckpack_workshop],
        pm.[pckpack_btch_nbr],
        bh.[btchh_ws_name],
        bh.[btchh_qty] AS [batch_total_qty],
        bh.[btchh_date] AS [btchh_full_date],
        CONVERT(VARCHAR(8), CAST(bh.[btchh_date] AS TIME), 108) AS [btchh_time_only]
    FROM 
        [TCIS_MES2_265].[dbo].[pckpackd_det] pd
    JOIN 
        [TCIS_MES2_265].[dbo].[pckpack_mstr] pm ON pd.[pckpackd_hu] = pm.[pckpack_hu]
    LEFT JOIN 
        [TCIS_MES2_265].[dbo].[btchh_hist] bh ON pm.[pckpack_btch_nbr] = bh.[btchh_nbr]
    WHERE 
        YEAR(pm.[pckpack_date]) = YEAR(GETDATE())
        AND MONTH(pm.[pckpack_date]) = MONTH(GETDATE())
)
SELECT 
    [pckpackd_hu],
    [pckpackd_pi],
    [pckpackd_ifs],
    [pckpackd_qty_pack],
	[pckpackd_qty_act],
    [pckpack_set],
    [pckpack_customer],
    [pckpack_workshop],
    [pckpack_btch_nbr],
    [btchh_ws_name],
    [batch_total_qty]
FROM 
    CurrentMonthData
ORDER BY 
    [pckpack_btch_nbr], [pckpack_date];