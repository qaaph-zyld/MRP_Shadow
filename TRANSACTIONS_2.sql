SELECT 
    [tr_site],
    [tr_prod_line],
    [tr_part],
	[tr_loc],
	[tr_userid],
    [tr_type],
    [tr_mtl_std],
    [tr_price],
    SUM([tr_qty_loc]) AS SumQtyLoc
FROM [QADEE2798].[dbo].[tr_hist]
WHERE [tr_type] IN ('iss-unp','rct-po','iss-scrp','iss-wo','rct-tr','iss-tr')
	and [tr_prod_line] in ('m_RM','S_RM','R_RM') and [tr_loc] in ('wip','wh')
GROUP BY 
    [tr_site],
    [tr_prod_line],
    [tr_part],
    [tr_type],
	[tr_loc],
	[tr_userid],
    [tr_mtl_std],
    [tr_price]
ORDER BY 
    [tr_site],
    [tr_prod_line],
    [tr_part],
    [tr_type],
	[tr_loc],
	[tr_userid];