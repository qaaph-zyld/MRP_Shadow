WITH pt_data AS (
    SELECT [pt_site], [pt_part], [pt_desc1], [pt_desc2], [pt_prod_line], [pt_group], 
           [pt_part_type], [pt_status], [pt_abc], [pt_cyc_int], [pt_sfty_stk], [pt_sfty_time], 
           [pt_buyer], [pt_vend], [pt_routing], [pt_net_wt], [pt_net_wt_um], [pt__chr02], [pt_dsgn_grp]
    FROM [QADEE2798].[dbo].[pt_mstr]
    UNION ALL
    SELECT [pt_site], [pt_part], [pt_desc1], [pt_desc2], [pt_prod_line], [pt_group], 
           [pt_part_type], [pt_status], [pt_abc], [pt_cyc_int], [pt_sfty_stk], [pt_sfty_time], 
           [pt_buyer], [pt_vend], [pt_routing], [pt_net_wt], [pt_net_wt_um], [pt__chr02], [pt_dsgn_grp]
    FROM [QADEE2798].[dbo].[pt_mstr]
),
ro_data AS (
    SELECT [ro_routing], [ro_op], [ro_desc], [ro_wkctr]
    FROM [QADEE2798].[dbo].[ro_det]
    WHERE [ro_end] IS NULL AND [ro_milestone] = 1
    UNION ALL
    SELECT [ro_routing], [ro_op], [ro_desc], [ro_wkctr]
    FROM [QADEE2798].[dbo].[ro_det]
    WHERE [ro_end] IS NULL AND [ro_milestone] = 1
),
SOD_Data AS (
    -- First part of the UNION ALL for sod_det
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
        [sod_cum_qty[1]]],  -- Keep column name unchanged
        [sod_cum_qty[2]]],  -- Keep column name unchanged
        [sod_cum_date[1]]],  -- Keep column name unchanged
        [sod_curr_rlse_id[1]]],  -- Keep column name unchanged
        [sod_curr_rlse_id[3]]],  -- Keep column name unchanged
        [sod_custref],
        [sod_unadjust_cum_qty]
    FROM 
        [QADEE2798].[dbo].[sod_det]
    WHERE 
        [sod_status] IS NULL 
        AND ([sod_end_eff[1]]] > CAST(GETDATE() AS DATE) OR [sod_end_eff[1]]] IS NULL)
        AND [sod_curr_rlse_id[1]]] IS NOT NULL
        AND [sod_prodline] <> 'N_FG'

    UNION ALL

    -- Second part of the UNION ALL for sod_det
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
        [sod_cum_qty[1]]],  -- Keep column name unchanged
        [sod_cum_qty[2]]],  -- Keep column name unchanged
        [sod_cum_date[1]]],  -- Keep column name unchanged
        [sod_curr_rlse_id[1]]],  -- Keep column name unchanged
        [sod_curr_rlse_id[3]]],  -- Keep column name unchanged
        [sod_custref],
        [sod_unadjust_cum_qty]
    FROM 
        [QADEE2798].[dbo].[sod_det]
    WHERE 
        [sod_status] IS NULL 
        AND ([sod_end_eff[1]]] > CAST(GETDATE() AS DATE) OR [sod_end_eff[1]]] IS NULL)
        AND [sod_curr_rlse_id[1]]] IS NOT NULL
),
SO_Data AS (
    -- First part of the UNION ALL for so_mstr
    SELECT 
        [so_nbr],
        [so_ship],
        [so_fob],
        [so_ship_date],
        [so_bol],
        [so_site]
    FROM 
        [QADEE2798].[dbo].[so_mstr]
    WHERE 
        [so_nbr] IN ('10006', '10026', '10027', '10028', 'LOZNICA')

    UNION ALL

    -- Second part of the UNION ALL for so_mstr
    SELECT 
        [so_nbr],
        [so_ship],
        [so_fob],
        [so_ship_date],
        [so_bol],
        [so_site]
    FROM 
        [QADEE2798].[dbo].[so_mstr]
    WHERE 
        [so_nbr] NOT IN ('SO10007', 'SO10009', 'SO10011', 'SO10012', 'SO10017')
),
PodData AS (
    SELECT  
        pd.[pod_po_site],  
        pd.[pod__chr08],  
        pm.[po_vend],  
        pd.[pod_nbr],  
        pd.[pod_line],  
        pd.[pod_part],  
        pd.[pod_cum_qty[1]]],  -- Keep column name unchanged
        pd.[pod_ord_mult],  
        pd.[pod_translt_days],
        pd.[pod_start_eff[1]]],  -- Keep column name unchanged
        pd.[pod_curr_rlse_id[1]]]  -- Keep column name unchanged
    FROM  
        [QADEE2798].[dbo].[pod_det] pd  
        JOIN [QADEE2798].[dbo].[po_mstr] pm ON pd.[pod_nbr] = pm.[po_nbr]  
    WHERE  
        pd.[pod_end_eff[1]]] = '2049-12-31 00:00:00'  
    UNION ALL  
    SELECT  
        pd.[pod_po_site],  
        pd.[pod__chr08],  
        pm.[po_vend],  
        pd.[pod_nbr],  
        pd.[pod_line],  
        pd.[pod_part],  
        pd.[pod_cum_qty[1]]],  -- Keep column name unchanged
        pd.[pod_ord_mult],  
        pd.[pod_translt_days],
        pd.[pod_start_eff[1]]],  -- Keep column name unchanged
        pd.[pod_curr_rlse_id[1]]]  -- Keep column name unchanged
    FROM  
        [QADEE2798].[dbo].[pod_det] pd  
        JOIN [QADEE2798].[dbo].[po_mstr] pm ON pd.[pod_nbr] = pm.[po_nbr]  
    WHERE  
        pd.[pod_end_eff[1]]] = '2049-12-31 00:00:00'
)
-- Perform the LEFT JOIN between pt_data, SOD_Data, SO_Data, and PodData
SELECT 
    p.[pt_site],
    p.[pt_part],
    p.[pt_desc1],
    p.[pt_desc2],
    p.[pt_prod_line],
    p.[pt_group],
    p.[pt_part_type],
    p.[pt_status],
    p.[pt_abc],
    p.[pt_cyc_int],
    p.[pt_sfty_stk],
    p.[pt_sfty_time],
    p.[pt_buyer],
    p.[pt_vend],
    p.[pt_routing],
    p.[pt_net_wt],
    p.[pt_net_wt_um],
    p.[pt__chr02],
    p.[pt_dsgn_grp],
    r.[ro_op],
    r.[ro_desc],
    r.[ro_wkctr],
    SOD.[sod_nbr],
    SOD.[sod_line],
    SOD.[sod_loc],
    SOD.[sod_std_cost],
    SOD.[sod_custpart],
    SOD.[sod_prodline],
    SOD.[sod_contr_id],
    SOD.[sod_cum_qty[1]]],  -- Keep column name unchanged
    SOD.[sod_cum_qty[2]]],  -- Keep column name unchanged
    SOD.[sod_cum_date[1]]],  -- Keep column name unchanged
    SOD.[sod_curr_rlse_id[1]]],  -- Keep column name unchanged
    SOD.[sod_curr_rlse_id[3]]],  -- Keep column name unchanged
    SOD.[sod_custref],
    SOD.[sod_unadjust_cum_qty],
    SO.[so_ship],
    SO.[so_fob],
    SO.[so_ship_date],
    SO.[so_bol],
    pd.[pod_po_site],
    pd.[pod__chr08],
    pd.[po_vend],
    pd.[pod_nbr],
    pd.[pod_line],
    pd.[pod_part],
    pd.[pod_cum_qty[1]]],  -- Keep column name unchanged
    pd.[pod_ord_mult],
    pd.[pod_translt_days],
    pd.[pod_start_eff[1]]],  -- Keep column name unchanged
    pd.[pod_curr_rlse_id[1]]]  -- Keep column name unchanged
FROM 
    pt_data p
LEFT JOIN 
    ro_data r ON p.[pt_routing] = r.[ro_routing]
LEFT JOIN 
    SOD_Data SOD ON p.[pt_site] = SOD.[sod_site] AND p.[pt_part] = SOD.[sod_part]
LEFT JOIN 
    SO_Data SO ON SOD.[sod_nbr] = SO.[so_nbr]
LEFT JOIN 
    PodData pd ON p.[pt_site] = pd.[pod_po_site] AND p.[pt_part] = pd.[pod_part];