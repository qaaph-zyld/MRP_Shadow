WITH ParentItems AS (
    -- Identify all parent items (where tr_type = 'RCT-WO')
    SELECT DISTINCT
        tr_part AS parent_item,
        tr_lot,
        tr_site
    FROM [QADEE2798].[dbo].[tr_hist]
    WHERE tr_type = 'RCT-WO'
    
    UNION ALL
    
    SELECT DISTINCT
        tr_part AS parent_item,
        tr_lot,
        tr_site
    FROM [QADEE].[dbo].[tr_hist]
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
    
    -- Added columns
    YEAR([tr_effdate]) AS [Year],  -- Extract year from [tr_effdate]
    DATEPART(month, [tr_effdate]) AS [month],
    DATEPART(week, [tr_effdate]) AS [week],
    -- Add [Parent Item] column for rows with corresponding [tr_lot]
    (SELECT TOP 1 pi.parent_item FROM ParentItems pi 
     WHERE pi.[tr_lot] = [tr_hist].[tr_lot] AND pi.[tr_site] = [tr_hist].[tr_site]) AS [Parent Item],
    -- Add Fiscal Year [FY] column
    'FY' + 
    CASE 
        WHEN MONTH([tr_effdate]) >= 10 THEN CAST(YEAR([tr_effdate]) + 1 AS VARCHAR)
        ELSE CAST(YEAR([tr_effdate]) AS VARCHAR)
    END AS [FY],
    CASE
        WHEN [tr_site] = '2674' THEN
            CASE
                WHEN CAST(DATEADD(second, ISNULL([tr_time], 0), '1900-01-01') AS time) >= '06:01:00' 
                     AND CAST(DATEADD(second, ISNULL([tr_time], 0), '1900-01-01') AS time) < '14:00:00' THEN '1st'
                WHEN CAST(DATEADD(second, ISNULL([tr_time], 0), '1900-01-01') AS time) >= '14:01:00' 
                     AND CAST(DATEADD(second, ISNULL([tr_time], 0), '1900-01-01') AS time) < '22:00:00' THEN '2nd'
                ELSE '3rd'
            END
        WHEN [tr_site] = '2798' THEN
            CASE
                WHEN CAST(DATEADD(second, ISNULL([tr_time], 0), '1900-01-01') AS time) >= '06:01:00' 
                     AND CAST(DATEADD(second, ISNULL([tr_time], 0), '1900-01-01') AS time) < '14:05:00' THEN '1st'
                ELSE '2nd'
            END
    END AS [shift]
FROM [QADEE2798].[dbo].[tr_hist]
WHERE [tr_type] NOT IN ('cst-adj','cyc-cnt','iss-chl','rct-chl','cyc-err','ord-so','cum-rres','rct-adj','cum-radj','cum-sadj','iss-tr','rct-tr')

UNION ALL

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
  
    -- Added columns
    YEAR([tr_effdate]) AS [Year],  -- Extract year from [tr_effdate]
    DATEPART(month, [tr_effdate]) AS [month],
    DATEPART(week, [tr_effdate]) AS [week],
    -- Add [Parent Item] column for rows with corresponding [tr_lot]
    (SELECT TOP 1 pi.parent_item FROM ParentItems pi 
     WHERE pi.[tr_lot] = [tr_hist].[tr_lot] AND pi.[tr_site] = [tr_hist].[tr_site]) AS [Parent Item],
    -- Add Fiscal Year [FY] column
    'FY' + 
    CASE 
        WHEN MONTH([tr_effdate]) >= 10 THEN CAST(YEAR([tr_effdate]) + 1 AS VARCHAR)
        ELSE CAST(YEAR([tr_effdate]) AS VARCHAR)
    END AS [FY],
    CASE
        WHEN [tr_site] = '2674' THEN
            CASE
                WHEN CAST(DATEADD(second, ISNULL([tr_time], 0), '1900-01-01') AS time) >= '06:01:00' 
                     AND CAST(DATEADD(second, ISNULL([tr_time], 0), '1900-01-01') AS time) < '14:00:00' THEN '1st'
                WHEN CAST(DATEADD(second, ISNULL([tr_time], 0), '1900-01-01') AS time) >= '14:01:00' 
                     AND CAST(DATEADD(second, ISNULL([tr_time], 0), '1900-01-01') AS time) < '22:00:00' THEN '2nd'
                ELSE '3rd'
            END
        WHEN [tr_site] = '2798' THEN
            CASE
                WHEN CAST(DATEADD(second, ISNULL([tr_time], 0), '1900-01-01') AS time) >= '06:01:00' 
                     AND CAST(DATEADD(second, ISNULL([tr_time], 0), '1900-01-01') AS time) < '14:05:00' THEN '1st'
                ELSE '2nd'
            END
    END AS [shift]
FROM [QADEE].[dbo].[tr_hist]
WHERE [tr_type] NOT IN ('cst-adj','cyc-cnt','iss-chl','rct-chl','cyc-err','ord-so','cum-rres','rct-adj','cum-radj','cum-sadj','iss-tr','rct-tr')

-- Apply ORDER BY to the combined result set
ORDER BY [tr_trnbr];