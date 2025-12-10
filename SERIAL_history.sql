SELECT
    [serh_trans_type],
    [serh_serial_id],
    [serh_site],
    [serh_loc],
    [serh_part],
    [serh_qty_chg],
    [serh_stage],
    [serh_pack_code],
    CONVERT(varchar, serh_trans_date, 23) AS serh_trans_date,
    LEFT(CONVERT(varchar, CAST(DATEADD(second, ISNULL(serh_trans_time, 0), '1900-01-01') AS time), 108), 5) AS serh_trans_time,
    [serh_user1],
    [serh_master_id],
    [serh_master_stage]
FROM [QADEE2798].[dbo].[serh_hist]
WHERE serh_trans_date >= DATEADD(month, DATEDIFF(month, 0, GETDATE()), 0)
  AND serh_trans_date < DATEADD(month, DATEDIFF(month, 0, GETDATE()) + 1, 0)
  AND [serh_stage] NOT IN ('new', 'pending')
   AND [serh_trans_type] IN ('pck-bld','pck-rct')
  AND serh_trans_date IS NOT NULL
UNION ALL
SELECT
    [serh_trans_type],
    [serh_serial_id],
    [serh_site],
    [serh_loc],
    [serh_part],
    [serh_qty_chg],
    [serh_stage],
    [serh_pack_code],
    CONVERT(varchar, serh_trans_date, 23) AS serh_trans_date,
    LEFT(CONVERT(varchar, CAST(DATEADD(second, ISNULL(serh_trans_time, 0), '1900-01-01') AS time), 108), 5) AS serh_trans_time,
    [serh_user1],
    [serh_master_id],
    [serh_master_stage]
FROM [QADEE2798].[dbo].[serh_hist]
WHERE serh_trans_date >= DATEADD(month, DATEDIFF(month, 0, GETDATE()), 0)
  AND serh_trans_date < DATEADD(month, DATEDIFF(month, 0, GETDATE()) + 1, 0)
  AND [serh_stage] NOT IN ('new', 'pending')
   AND [serh_trans_type] IN ('pck-bld','pck-rct')
  AND serh_trans_date IS NOT NULL
ORDER BY [serh_serial_id], [serh_trans_date];