WITH pt_data AS (
    SELECT
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
        [pt_site],
        [pt_dsgn_grp]
    FROM [QADEE2798].[dbo].[pt_mstr]
    WHERE [pt_part_type] NOT IN ('xc', 'rc')

),
ld_data AS (
    SELECT
        xz.[xxwezoned_site],
        ld.[ld_part],
        ld.[ld_qty_oh],
        xz.[xxwezoned_area_id],
        CAST(i.[in_iss_date] AS DATE) AS last_iss_date,
        CAST(i.[in_rec_date] AS DATE) AS last_rec_date,
        CAST(i.[in_cnt_date] AS DATE) AS last_count_date
    FROM [QADEE2798].[dbo].[ld_det] ld
    LEFT JOIN [QADEE2798].[dbo].[xxwezoned_det] xz
        ON ld.[ld_loc] = xz.[xxwezoned_loc]
    LEFT JOIN [QADEE2798].[dbo].[15] i
        ON ld.[ld_part] = i.[in_part]
    WHERE [ld_qty_oh] <> 0
)

SELECT
    pt_data.pt_part,
    pt_data.pt_desc1,
    pt_data.pt_desc2,
    pt_data.pt_prod_line,
    pt_data.pt_group,
    pt_data.pt_part_type,
    pt_data.pt_status,
    pt_data.pt_abc,
    pt_data.pt_cyc_int,
    pt_data.pt_sfty_stk,
    pt_data.pt_sfty_time,
    pt_data.pt_buyer,
    pt_data.pt_vend,
    pt_data.pt_routing,
    pt_data.pt_net_wt,
    pt_data.pt_net_wt_um,
    pt_data.pt__chr02,
    pt_data.pt_site,
    pt_data.pt_dsgn_grp,
    ld_data.xxwezoned_area_id,
    ld_data.ld_qty_oh,
    ld_data.last_iss_date,
    ld_data.last_rec_date,
    ld_data.last_count_date
FROM pt_data
LEFT JOIN ld_data
    ON pt_data.pt_part = ld_data.ld_part
    AND pt_data.pt_site = ld_data.xxwezoned_site
ORDER BY ld_data.xxwezoned_site, ld_data.ld_part;