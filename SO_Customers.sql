WITH SodData AS (
    SELECT
        [sod_nbr],
        [sod_line],
        [sod_part],
        [sod_qty_ship],
        [sod_site],
        [sod_prodline],
        [sod_contr_id],
        [sod_cum_qty[1]]],
        [sod_cum_qty[2]]],
        [sod_cum_date[2]]],
        [sod_curr_rlse_id[1]]],
        [sod_curr_rlse_id[3]]]
    FROM [QADEE2798].[dbo].[sod_det]
    WHERE [sod_status] IS NULL
    UNION ALL
    SELECT
        [sod_nbr],
        [sod_line],
        [sod_part],
        [sod_qty_ship],
        [sod_site],
        [sod_prodline],
        [sod_contr_id],
        [sod_cum_qty[1]]],
        [sod_cum_qty[2]]],
        [sod_cum_date[2]]],
        [sod_curr_rlse_id[1]]],
        [sod_curr_rlse_id[3]]]
    FROM [QADEE2798].[dbo].[sod_det]
    WHERE [sod_status] IS NULL
),
SoData AS (
    SELECT
        [so_nbr],
        [so_ship],
        [so_fob],
        [so_ship_date],
        [so_bol]
    FROM [QADEE2798].[dbo].[so_mstr]
    UNION ALL
    SELECT
        [so_nbr],
        [so_ship],
        [so_fob],
        [so_ship_date],
        [so_bol]
    FROM [QADEE2798].[dbo].[so_mstr]
)
SELECT
    s.[sod_nbr],
    s.[sod_line],
    s.[sod_part],
    s.[sod_qty_ship],
    s.[sod_site],
    s.[sod_prodline],
    s.[sod_contr_id],
    s.[sod_cum_qty[1]]],
    s.[sod_cum_qty[2]]],
    s.[sod_cum_date[2]]],
    s.[sod_curr_rlse_id[1]]],
    s.[sod_curr_rlse_id[3]]],
    so.[so_ship],
    so.[so_fob],
    so.[so_ship_date],
    so.[so_bol]
FROM
    SodData s
    LEFT JOIN SoData so ON s.[sod_nbr] = so.[so_nbr];