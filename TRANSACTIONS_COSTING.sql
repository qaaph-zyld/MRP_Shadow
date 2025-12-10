SELECT 
    [tr_part],
    [tr_type],
    [tr_nbr],
    [tr_so_job],
    [tr_addr],
    [tr_mtl_std],
    [tr_lbr_std],
    [tr_bdn_std],
    [tr_ovh_std],
    [tr_price],
    [tr_lot],
    [tr_qty_loc],
    [tr_site],
    [tr_wod_op],
    -- Calculate [LBO] as the sum of [tr_lbr_std], [tr_bdn_std], and [tr_ovh_std]
    ([tr_lbr_std] + [tr_bdn_std] + [tr_ovh_std]) AS [LBO],
    -- Calculate [Standard cost] as the sum of [LBO] and [tr_mtl_std]
    ([tr_lbr_std] + [tr_bdn_std] + [tr_ovh_std] + [tr_mtl_std]) AS [Standard cost],
    -- Calculate [CMAT] as [tr_mtl_std] multiplied by [tr_qty_loc]
    ([tr_mtl_std] * [tr_qty_loc]) AS [CMAT],
    -- Calculate [COGS] as [Standard cost] multiplied by [tr_qty_loc]
    (([tr_lbr_std] + [tr_bdn_std] + [tr_ovh_std] + [tr_mtl_std]) * [tr_qty_loc]) AS [COGS]
FROM 
    [QADEE2798].[dbo].[tr_hist]
WHERE 
    [tr_part] IN (
        '5284292', '5284260', '5284265', '5284266', 
        '5284263', '5284258', '5284262', '5284261', '5347174'
    )
ORDER BY 
    [tr_lot];