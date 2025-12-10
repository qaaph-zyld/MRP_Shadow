WITH CombinedSerActivePicked AS (
    SELECT    [ser_serial_id],
          [ser_stage],   
		  [ser_pack_code],
          [ser_site],  
          [ser_loc],  
          [ser_part],   
          [ser_qty_avail]
    FROM [QADEE2798].[dbo].[ser_active_picked]  
),
CombinedXxwezonedDet AS (
    SELECT [xxwezoned_warehouse_id],
           [xxwezoned_area_id],
           [xxwezoned_loc]
    FROM [QADEE2798].[dbo].[xxwezoned_det]
)
SELECT 
    cser.*,
    cxxw.[xxwezoned_area_id]
FROM CombinedSerActivePicked cser
LEFT JOIN CombinedXxwezonedDet cxxw
ON cser.ser_site = cxxw.xxwezoned_warehouse_id
AND cser.ser_loc = cxxw.xxwezoned_loc;