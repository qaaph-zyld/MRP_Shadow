-- Item Parameters (2798 only)
SELECT [pt_site], [pt_part], [pt_desc1], [pt_desc2], [pt_prod_line], [pt_group], 
       [pt_part_type], [pt_status], [pt_abc], [pt_cyc_int], [pt_sfty_stk], [pt_sfty_time], 
       [pt_buyer], [pt_vend], [pt_routing], [pt_net_wt], [pt_net_wt_um], [pt__chr02], [pt_dsgn_grp]
FROM [QADEE2798].[dbo].[pt_mstr]
WHERE [pt_part_type] NOT IN ('xc', 'rc');