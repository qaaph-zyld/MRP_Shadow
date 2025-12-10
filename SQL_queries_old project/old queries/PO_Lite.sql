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
        [QADEE].[dbo].[pod_det] pd  
        JOIN [QADEE].[dbo].[po_mstr] pm ON pd.[pod_nbr] = pm.[po_nbr]  
    WHERE  
        pd.[pod_end_eff[1]]] = '2049-12-31 00:00:00'  and pd.[pod_status] is null
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
        pd.[pod_end_eff[1]]] = '2049-12-31 00:00:00' and pd.[pod_status] is null
)
SELECT 
    pod_po_site,
    pod__chr08,
    po_vend,
    pod_nbr,
    pod_line,
    pod_part,
    [pod_cum_qty[1]]],
    pod_ord_mult,
    pod_translt_days,
    [pod_start_eff[1]]],
    [pod_curr_rlse_id[1]]]
FROM PodData;