WITH ParentItems AS (
    -- Identify all parent items (where tr_type = 'RCT-WO') in 2798 only
    SELECT DISTINCT
        tr_part AS parent_item,
        tr_lot,
        tr_site
    FROM [QADEE2798].[dbo].[tr_hist]
    WHERE tr_type = 'RCT-WO'
)

SELECT 
    [tr_part],
    [tr_type],
    [tr_loc],
    [tr_loc_begin],
    [tr_nbr],
    [tr_so_job],
    [tr_addr],
    [tr_lot],
    [tr_qty_loc],
    [tr_userid],
    [tr_effdate],
    [tr_prod_line],
    [tr_site],
    [tr_ref],
    [tr_program],
    [tr_wod_op],
    [tr_trnbr],
    YEAR([tr_effdate]) AS [Year],
    DATEPART(month, [tr_effdate]) AS [month],
    DATEPART(week, [tr_effdate]) AS [week],
    -- Parent item resolved via RCT-WO lot for 2798
    (SELECT TOP 1 pi.parent_item 
     FROM ParentItems pi 
     WHERE pi.[tr_lot] = [tr_hist].[tr_lot] 
       AND pi.[tr_site] = [tr_hist].[tr_site]) AS [Parent Item],
    -- Fiscal Year (FY) based on October year boundary
    'FY' + 
    CASE 
        WHEN MONTH([tr_effdate]) >= 10 THEN CAST(YEAR([tr_effdate]) + 1 AS VARCHAR(4))
        ELSE CAST(YEAR([tr_effdate]) AS VARCHAR(4))
    END AS [FY],
    -- Shift logic for plant 2798 only
    CASE
        WHEN [tr_site] = '2798' THEN
            CASE
                WHEN CAST(DATEADD(second, ISNULL([tr_time], 0), '1900-01-01') AS time) >= '06:01:00' 
                     AND CAST(DATEADD(second, ISNULL([tr_time], 0), '1900-01-01') AS time) < '14:05:00' THEN '1st'
                ELSE '2nd'
            END
        ELSE NULL
    END AS [shift]
FROM [QADEE2798].[dbo].[tr_hist]
WHERE [tr_type] NOT IN ('cst-adj','cyc-cnt','iss-chl','rct-chl','cyc-err','ord-so','cum-rres','rct-adj','cum-radj','cum-sadj','iss-tr','rct-tr')
ORDER BY [tr_trnbr];
;