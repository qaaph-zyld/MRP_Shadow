WITH PartInventory AS (
    SELECT 
        CAST(pt.pt_part AS VARCHAR(50)) AS pt_part,
        pt.pt_desc1,
        pt.pt_prod_line,
        pt.pt__chr02,
        pt.pt_dsgn_grp,
        sd.sct_cst_tot,
        (sd.sct_mtl_tl + sd.sct_mtl_ll) AS MaterialCost,
        so.so_nbr,
        so.so_ship,
        sod.sod_line,
        ind.in_iss_date,
        ind.in_rec_date,
        ind.in_cnt_date,
        ISNULL(ldx.WH_Qty, 0) AS WH_Qty,
        ISNULL(ldx.WIP_Qty, 0) AS WIP_Qty,
        ISNULL(ldx.EXLPICK_Qty, 0) AS EXLPICK_Qty,
        ISNULL(ldx.WH_Qty, 0) + ISNULL(ldx.WIP_Qty, 0) + ISNULL(ldx.EXLPICK_Qty, 0) AS total_qty_avail,
        ISNULL(sd.sct_cst_tot * (ISNULL(ldx.WH_Qty, 0) + ISNULL(ldx.WIP_Qty, 0) + ISNULL(ldx.EXLPICK_Qty, 0)), 0) AS Total_COGS,
        ISNULL(sd.sct_cst_tot * ISNULL(ldx.WH_Qty, 0), 0) AS WH_COGS,
        ISNULL(sd.sct_cst_tot * ISNULL(ldx.WIP_Qty, 0), 0) AS WIP_COGS,
        ISNULL(sd.sct_cst_tot * ISNULL(ldx.EXLPICK_Qty, 0), 0) AS EXLPICK_COGS
    FROM 
        [QADEE2798].[dbo].[pt_mstr] pt
    LEFT JOIN 
        [QADEE2798].[dbo].[sct_det] sd 
        ON pt.pt_part = sd.sct_part 
        AND sd.sct_sim = 'Standard'
    LEFT JOIN 
        [QADEE2798].[dbo].[so_mstr] so
        ON pt.pt_part = so.so_part
    LEFT JOIN 
        [QADEE2798].[dbo].[sod_det] sod
        ON so.so_nbr = sod.sod_nbr
    LEFT JOIN 
        [QADEE2798].[dbo].[in_det] ind
        ON pt.pt_part = ind.in_part
    LEFT JOIN (
        SELECT 
            ld.ld_part,
            SUM(CASE WHEN xz.xxwezoned_area_id = 'WH' THEN ld.ld_qty_oh ELSE 0 END) AS WH_Qty,
            SUM(CASE WHEN xz.xxwezoned_area_id = 'WIP' THEN ld.ld_qty_oh ELSE 0 END) AS WIP_Qty,
            SUM(CASE WHEN xz.xxwezoned_area_id = 'EXLPICK' THEN ld.ld_qty_oh ELSE 0 END) AS EXLPICK_Qty
        FROM 
            [QADEE2798].[dbo].[ld_det] ld
        LEFT JOIN 
            [QADEE2798].[dbo].[xxwezoned_det] xz 
            ON ld.ld_loc = xz.xxwezoned_loc
        GROUP BY 
            ld.ld_part
    ) ldx ON pt.pt_part = ldx.ld_part
    WHERE 
        pt.pt_part_type NOT IN ('xc', 'rc')
)
SELECT 
    pt_part,
    pt_desc1,
    pt_prod_line,
    pt__chr02,
    pt_dsgn_grp,
    sct_cst_tot,
    MaterialCost,
    so_nbr,
    so_ship,
    sod_line,
    in_iss_date,
    in_rec_date,
    in_cnt_date,
    WH_Qty,
    WIP_Qty,
    EXLPICK_Qty,
    total_qty_avail,
    Total_COGS,
    WH_COGS,
    WIP_COGS,
    EXLPICK_COGS
FROM PartInventory
ORDER BY Total_COGS DESC