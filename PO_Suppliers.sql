WITH PodData AS (
    SELECT  
        pd.[pod_po_site],  
        pd.[pod__chr08],  
        pm.[po_vend],  
        pd.[pod_nbr],  
        pd.[pod_line],  
        pd.[pod_part],  
        pd.[pod_cum_qty[1]]],  
        pd.[pod_ord_mult],  
        pd.[pod_translt_days],
        pd.[pod_start_eff[1]]],
		pd.[pod_curr_rlse_id[1]]]
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
        pd.[pod_cum_qty[1]]],  
        pd.[pod_ord_mult],  
        pd.[pod_translt_days],
        pd.[pod_start_eff[1]]],
		pd.[pod_curr_rlse_id[1]]]
    FROM  
        [QADEE2798].[dbo].[pod_det] pd  
        JOIN [QADEE2798].[dbo].[po_mstr] pm ON pd.[pod_nbr] = pm.[po_nbr]  
    WHERE  
        pd.[pod_end_eff[1]]] = '2049-12-31 00:00:00'
)
SELECT
    p.[pod_po_site],
    p.[pod__chr08],
    p.[po_vend],
    p.[pod_nbr],
    p.[pod_line],
    p.[pod_part],
    p.[pod_cum_qty[1]]],
    p.[pod_ord_mult],
    p.[pod_translt_days],
    p.[pod_start_eff[1]]],
    pt.[pt_desc1],
    pt.[pt_desc2],
    pt.[pt_prod_line],
    pt.[pt_group],
    pt.[pt_part_type],
    pt.[pt_status],
    pt.[pt_abc],
    pt.[pt_cyc_int],
    pt.[pt_sfty_stk],
    pt.[pt_sfty_time],
    pt.[pt_buyer],
    pt.[pt_vend],
    pt.[pt_routing],
    pt.[pt_net_wt],
    pt.[pt_net_wt_um],
    pt.[pt__chr02],
    pt.[pt_dsgn_grp]
FROM
    PodData p
    LEFT JOIN (
        SELECT  
            [pt_site],
            [pt_part],
            [pt_desc1],
            [pt_desc2],
            [pt_prod_line],
            [pt_group],
            [pt_part_type],
            [pt_status],
            [pt_abc],
            [pt_cyc_int],
            [pt_sfty_stk],
            [pt_sfty_time],
            [pt_buyer],
            [pt_vend],
            [pt_routing],
            [pt_net_wt],
            [pt_net_wt_um],
            [pt__chr02],
            [pt_dsgn_grp]
        FROM [QADEE2798].[dbo].[pt_mstr]
        UNION ALL
        SELECT  
            [pt_site], 
            [pt_part],
            [pt_desc1],
            [pt_desc2],
            [pt_prod_line],
            [pt_group],
            [pt_part_type],
            [pt_status],
            [pt_abc],
            [pt_cyc_int],
            [pt_sfty_stk],
            [pt_sfty_time],
            [pt_buyer],
            [pt_vend],
            [pt_routing],
            [pt_net_wt],
            [pt_net_wt_um],
            [pt__chr02],
            [pt_dsgn_grp]
        FROM [QADEE2798].[dbo].[pt_mstr]
    ) pt ON p.[pod_po_site] = pt.[pt_site] AND p.[pod_part] = pt.[pt_part];