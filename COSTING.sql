SELECT
    [sct_site],
    [sct_part],
    [sct_cst_tot],
    ([sct_mtl_tl] + [sct_mtl_ll]) AS [mat_cost],
    ([sct_cst_tot] - ([sct_mtl_tl] + [sct_mtl_ll])) AS [LBO]
FROM 
    [QADEE2798].[dbo].[sct_det]
WHERE 
    [sct_sim] = 'standard'

UNION ALL

SELECT
    [sct_site],
    [sct_part],
    [sct_cst_tot],
    ([sct_mtl_tl] + [sct_mtl_ll]) AS [mat_cost],
    ([sct_cst_tot] - ([sct_mtl_tl] + [sct_mtl_ll])) AS [LBO]
FROM 
    [QADEE2798].[dbo].[sct_det]
WHERE 
    [sct_sim] = 'standard';