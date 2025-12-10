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
    [pt_dsgn_grp],
    CASE 
        WHEN ps_par.[ps_par] IS NOT NULL THEN 'Yes' 
        ELSE 'No' 
    END AS [Is_Parent],
    CASE 
        WHEN ps_comp.[ps_comp] IS NOT NULL THEN 'Yes' 
        ELSE 'No' 
    END AS [Is_Child],
    CASE 
        WHEN ps_par.[ps_par] IS NOT NULL AND ps_comp.[ps_comp] IS NOT NULL THEN 'SFG' -- Both Parent and Child
        WHEN ps_par.[ps_par] IS NULL AND ps_comp.[ps_comp] IS NOT NULL THEN 'RM'     -- Only Child
        WHEN ps_par.[ps_par] IS NOT NULL AND ps_comp.[ps_comp] IS NULL THEN 'FG'     -- Only Parent
        ELSE NULL -- Default case (should not occur based on your conditions)
    END AS [BOM Status]
FROM [QADEE2798].[dbo].[pt_mstr]
LEFT JOIN (
    SELECT DISTINCT [ps_par] 
    FROM [QADEE2798].[dbo].[ps_mstr]
    UNION ALL
    SELECT DISTINCT [ps_par] 
    FROM [QADEE2798].[dbo].[ps_mstr]
) ps_par ON [pt_part] = ps_par.[ps_par]
LEFT JOIN (
    SELECT DISTINCT [ps_comp] 
    FROM [QADEE2798].[dbo].[ps_mstr]
    UNION ALL
    SELECT DISTINCT [ps_comp] 
    FROM [QADEE2798].[dbo].[ps_mstr]
) ps_comp ON [pt_part] = ps_comp.[ps_comp]
WHERE [pt_part_type] NOT IN ('xc', 'rc')  -- Filter out 'xc' and 'rc'

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
    [pt_dsgn_grp],
    CASE 
        WHEN ps_par.[ps_par] IS NOT NULL THEN 'Yes' 
        ELSE 'No' 
    END AS [Is_Parent],
    CASE 
        WHEN ps_comp.[ps_comp] IS NOT NULL THEN 'Yes' 
        ELSE 'No' 
    END AS [Is_Child],
    CASE 
        WHEN ps_par.[ps_par] IS NOT NULL AND ps_comp.[ps_comp] IS NOT NULL THEN 'SFG' -- Both Parent and Child
        WHEN ps_par.[ps_par] IS NULL AND ps_comp.[ps_comp] IS NOT NULL THEN 'RM'     -- Only Child
        WHEN ps_par.[ps_par] IS NOT NULL AND ps_comp.[ps_comp] IS NULL THEN 'FG'     -- Only Parent
        ELSE NULL -- Default case (should not occur based on your conditions)
    END AS [BOM Status]
FROM [QADEE2798].[dbo].[pt_mstr]
LEFT JOIN (
    SELECT DISTINCT [ps_par] 
    FROM [QADEE2798].[dbo].[ps_mstr]
    UNION ALL
    SELECT DISTINCT [ps_par] 
    FROM [QADEE2798].[dbo].[ps_mstr]
) ps_par ON [pt_part] = ps_par.[ps_par]
LEFT JOIN (
    SELECT DISTINCT [ps_comp] 
    FROM [QADEE2798].[dbo].[ps_mstr]
    UNION ALL
    SELECT DISTINCT [ps_comp] 
    FROM [QADEE2798].[dbo].[ps_mstr]
) ps_comp ON [pt_part] = ps_comp.[ps_comp]
WHERE [pt_part_type] NOT IN ('xc', 'rc');  -- Filter out 'xc' and 'rc'