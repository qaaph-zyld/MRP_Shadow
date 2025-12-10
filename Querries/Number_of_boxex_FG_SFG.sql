SELECT 
    h.serh_trans_date AS Date,
    CASE 
        -- Logic updated: time is in seconds (0-86400). 14 hours = 50400 seconds.
        WHEN h.serh_trans_time < 50400 THEN '1st'
        ELSE '2nd'
    END AS Shift,
    h.serh_part AS [Item Number],
    COUNT(h.serh_serial_id) AS [count of serial id],
    p.pt__chr02 AS [Item Type],
    p.pt_desc1 AS [Description],
    p.pt_prod_line AS [Prod Line],
    p.pt_group AS [Group],
    p.pt_dsgn_grp AS [Project]
    
    

FROM [QADEE2798].[dbo].[serh_hist] h
LEFT JOIN [QADEE2798].[dbo].[pt_mstr] p ON h.serh_part = p.pt_part
WHERE h.serh_trans_type = 'pck-bld' 
    AND h.serh_stage = 'active'
    AND p.pt_prod_line LIKE '%_FG' -- Filter for Prod Lines containing "_FG"
    AND h.serh_trans_date >= DATEADD(month, -12, GETDATE()) -- Filter for the last 12 months
GROUP BY 
    h.serh_trans_date,
    -- Logic updated here as well to match the SELECT clause
    CASE 
        WHEN h.serh_trans_time < 50400 THEN '1st'
        ELSE '2nd'
    END,
    h.serh_part,
    p.pt__chr02,
    p.pt_desc1,
    p.pt_prod_line,
    p.pt_group,
    p.pt_dsgn_grp
  
ORDER BY 
    h.serh_trans_date,
    Shift,
    h.serh_part;