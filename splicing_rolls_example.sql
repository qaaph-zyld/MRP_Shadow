SELECT
    xz.[xxwezoned_site],
    ld.[ld_part],
    ld.[ld_qty_oh],
    xz.[xxwezoned_area_id],
    CAST(i.[in_iss_date] AS DATE) AS last_iss_date,
    CAST(i.[in_rec_date] AS DATE) AS last_rec_date,
    CAST(i.[in_cnt_date] AS DATE) AS last_count_date,
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
    pt.[pt_dsgn_grp],
    sc.total_cost,
    sc.mat_cost,
    sc.lbo_cost,
    ISNULL(sc.total_cost, 0) * ISNULL(ld.ld_qty_oh, 0) AS [COGS],
    ISNULL(sc.mat_cost, 0) * ISNULL(ld.ld_qty_oh, 0) AS [CMAT]
FROM [QADEE2798].[dbo].[ld_det] ld
LEFT JOIN [QADEE2798].[dbo].[xxwezoned_det] xz
    ON ld.[ld_loc] = xz.[xxwezoned_loc]
LEFT JOIN [QADEE2798].[dbo].[15] i
    ON ld.[ld_part] = i.[in_part]
LEFT JOIN [QADEE2798].[dbo].[pt_mstr] pt
    ON xz.[xxwezoned_site] = pt.[pt_site]
    AND ld.[ld_part] = pt.[pt_part]
    AND pt.[pt_part_type] NOT IN ('xc', 'rc')
LEFT JOIN (
    SELECT
        sct_part,
        sct_site,
        ISNULL(sct_cst_tot, 0) AS total_cost,
        ISNULL(sct_mtl_tl, 0) + ISNULL(sct_mtl_ll, 0) AS mat_cost,
        ISNULL(sct_cst_tot, 0) - (ISNULL(sct_mtl_tl, 0) + ISNULL(sct_mtl_ll, 0)) AS lbo_cost
    FROM [QADEE2798].[dbo].[sct_det]
    WHERE [sct_sim] = 'Standard'
) sc
    ON sc.sct_part = ld.ld_part
    AND sc.sct_site = xz.xxwezoned_site
WHERE [ld_qty_oh] <> 0
AND pt.[pt_part] = '4827784-180030_TR'  -- Filter by pt_part

UNION ALL

SELECT
    xz.[xxwezoned_site],
    ld.[ld_part],
    ld.[ld_qty_oh],
    xz.[xxwezoned_area_id],
    CAST(i.[in_iss_date] AS DATE) AS last_iss_date,
    CAST(i.[in_rec_date] AS DATE) AS last_rec_date,
    CAST(i.[in_cnt_date] AS DATE) AS last_count_date,
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
    pt.[pt_dsgn_grp],
    sc.total_cost,
    sc.mat_cost,
    sc.lbo_cost,
    ISNULL(sc.total_cost, 0) * ISNULL(ld.ld_qty_oh, 0) AS [COGS],
    ISNULL(sc.mat_cost, 0) * ISNULL(ld.ld_qty_oh, 0) AS [CMAT]
FROM [QADEE2798].[dbo].[ld_det] ld
LEFT JOIN [QADEE2798].[dbo].[xxwezoned_det] xz
    ON ld.[ld_loc] = xz.[xxwezoned_loc]
LEFT JOIN [QADEE2798].[dbo].[in_mstr] i
    ON ld.[ld_part] = i.[in_part]
LEFT JOIN [QADEE2798].[dbo].[pt_mstr] pt
    ON xz.[xxwezoned_site] = pt.[pt_site]
    AND ld.[ld_part] = pt.[pt_part]
    AND pt.[pt_part_type] NOT IN ('xc', 'rc')
LEFT JOIN (
    SELECT
        sct_part,
        sct_site,
        ISNULL(sct_cst_tot, 0) AS total_cost,
        ISNULL(sct_mtl_tl, 0) + ISNULL(sct_mtl_ll, 0) AS mat_cost,
        ISNULL(sct_cst_tot, 0) - (ISNULL(sct_mtl_tl, 0) + ISNULL(sct_mtl_ll, 0)) AS lbo_cost
    FROM [QADEE2798].[dbo].[sct_det]
    WHERE [sct_sim] = 'Standard'
) sc
    ON sc.sct_part = ld.ld_part
    AND sc.sct_site = xz.xxwezoned_site
WHERE [ld_qty_oh] <> 0
AND pt.[pt_part] = '4827784-180030_TR';  -- Filter by pt_part