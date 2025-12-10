SELECT 
    a.[ser_part],
    b.[xxwezoned_area_id],
    COUNT(a.[ser_serial_id]) AS Serial_Count,
    SUM(a.[ser_qty_avail]) AS Total_Qty_Avail
FROM 
    [QADEE2798].[dbo].[ser_active_picked] a
LEFT JOIN 
    [QADEE2798].[dbo].[xxwezoned_det] b ON a.[ser_loc] = b.[xxwezoned_loc]
GROUP BY 
    a.[ser_part], 
    b.[xxwezoned_area_id]
ORDER BY 
    a.[ser_part], 
    b.[xxwezoned_area_id];