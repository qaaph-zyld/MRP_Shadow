SELECT 
    '2674' AS [Plant],
    [ps_par],  
    [ps_comp],  
    [ps_qty_per],  
    [ps_op]
FROM 
    [QADEE].[dbo].[ps_mstr]
WHERE 
    [ps_end] is null  -- Apply the filter condition

UNION ALL

SELECT 
    '2798' AS [Plant],
    [ps_par],  
    [ps_comp],  
    [ps_qty_per],  
    [ps_op]

FROM 
    [QADEE2798].[dbo].[ps_mstr]
WHERE 
    [ps_end] is null;  -- Apply the filter condition