WITH ParentItems AS (
    -- Identify all parent items (where tr_type = 'RCT-WO')
    SELECT DISTINCT
        tr_part AS parent_item,
        tr_lot,
        tr_site
    FROM [QADEE2798].[dbo].[tr_hist]
    WHERE tr_type = 'RCT-WO'
)
SELECT 
    YEAR(th.[tr_effdate]) AS [Year],  -- Extract year from [tr_effdate]
    MONTH(th.[tr_effdate]) AS [Month], -- Extract month from [tr_effdate]
    th.[tr_site],
    th.[tr_type],
    th.[tr_part],
    th.[tr_mtl_std],
    -- Group by the LBO calculation (sum of labor, burden, overhead)
    (th.[tr_lbr_std] + th.[tr_bdn_std] + th.[tr_ovh_std]) AS [LBO],
    -- Calculate [Standard cost] as the sum of [LBO] and [tr_mtl_std]
    (th.[tr_lbr_std] + th.[tr_bdn_std] + th.[tr_ovh_std] + th.[tr_mtl_std]) AS [Standard cost],
    -- Add [Parent Item] column for rows with corresponding [tr_lot]
    pi.parent_item AS [Parent Item],
    -- Include [tr_loc] for 'ISS-TR' and 'RCT-TR' transactions
    CASE 
        WHEN th.[tr_type] IN ('iss-tr', 'rct-tr') THEN th.[tr_loc]
        ELSE NULL
    END AS [Location],
    -- Add [User] column: [tr_userid] for 'iss-wo' and 'rct-wo', NULL for others
    CASE 
        WHEN th.[tr_type] IN ('iss-wo', 'rct-wo') THEN th.[tr_userid]
        ELSE NULL
    END AS [User],
    -- Add Fiscal Year [FY] column
    'FY' + 
    CASE 
        WHEN MONTH(th.[tr_effdate]) >= 10 THEN CAST(YEAR(th.[tr_effdate]) + 1 AS VARCHAR)
        ELSE CAST(YEAR(th.[tr_effdate]) AS VARCHAR)
    END AS [FY],
    -- Aggregations
    SUM(th.[tr_qty_loc]) AS [Total_Qty],
    SUM(th.[tr_mtl_std] * th.[tr_qty_loc]) AS [Total_CMAT],
    SUM((th.[tr_lbr_std] + th.[tr_bdn_std] + th.[tr_ovh_std] + th.[tr_mtl_std]) * th.[tr_qty_loc]) AS [Total_COGS]
FROM 
    [QADEE2798].[dbo].[tr_hist] th
LEFT JOIN 
    ParentItems pi
    ON th.[tr_lot] = pi.[tr_lot]  -- Join on [tr_lot]
    AND th.[tr_site] = pi.[tr_site]  -- Also join on [tr_site] to ensure correct matching
WHERE 
    (
        th.[tr_type] IN ('iss-wo','rct-wo','iss-unp','iss-scrp','iss-so','rct-po','cyc-rcnt')
        OR 
        (th.[tr_type] IN ('iss-tr', 'rct-tr') AND th.[tr_loc] IN ('WIP', 'PROD'))
    )
GROUP BY 
    YEAR(th.[tr_effdate]),  -- Group by year
    MONTH(th.[tr_effdate]), -- Group by month
    th.[tr_site],
    th.[tr_type],
    th.[tr_part],
    th.[tr_mtl_std],
    -- Include the LBO calculation in GROUP BY (SQL Server requires the full expression)
    (th.[tr_lbr_std] + th.[tr_bdn_std] + th.[tr_ovh_std]),
    -- Include [Parent Item] in GROUP BY
    pi.parent_item,
    -- Include [tr_loc] in GROUP BY for 'ISS-TR' and 'RCT-TR' transactions
    CASE 
        WHEN th.[tr_type] IN ('iss-tr', 'rct-tr') THEN th.[tr_loc]
        ELSE NULL
    END,
    -- Include [User] in GROUP BY
    CASE 
        WHEN th.[tr_type] IN ('iss-wo', 'rct-wo') THEN th.[tr_userid]
        ELSE NULL
    END,
    -- Include [FY] in GROUP BY
    'FY' + 
    CASE 
        WHEN MONTH(th.[tr_effdate]) >= 10 THEN CAST(YEAR(th.[tr_effdate]) + 1 AS VARCHAR)
        ELSE CAST(YEAR(th.[tr_effdate]) AS VARCHAR)
    END
HAVING 
    SUM(th.[tr_qty_loc]) <> 0  -- Exclude rows where [Total_Qty] is 0
ORDER BY 
    [Year], [Month], [Parent Item];  -- Sort by Year, Month, and Parent Item