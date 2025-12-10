SELECT [tr_site],
 [tr_lot],
    [tr_type],
	[tr_part],
    [tr_nbr],
    [tr_addr],
	[tr_qty_loc],
    [tr_mtl_std],
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

    [tr_effdate] ='2025-08-02'
		UNION ALL

		SELECT 
		[tr_site],
[tr_lot],
    [tr_type],
	[tr_part],
    [tr_nbr],
    [tr_addr],
	[tr_qty_loc],
    [tr_mtl_std],
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
 [tr_effdate] ='2025-08-02'
ORDER BY 
    [tr_site],[tr_lot],[tr_part];