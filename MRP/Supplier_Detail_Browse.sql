WITH CustomerItems AS (
    SELECT DISTINCT [sod_part] AS ItemNumber 
    FROM [QADEE2798].[dbo].[sod_det] 
),

CombinedPS AS (    
    SELECT 
        '2798' AS [Plant],
        ps_par,
        ps_comp,
        ps_qty_per,
        ps_rmks
    FROM [QADEE2798].[dbo].[ps_mstr]
    WHERE [ps_end] IS NULL
),

BOMHierarchy AS (
    SELECT 
        ps_par AS root_parent,
        ps_par AS current_parent,
        ps_comp AS component,
        [Plant],
        ps_qty_per,
        ps_rmks,
        CASE 
            WHEN EXISTS (SELECT 1 FROM CombinedPS ps2 WHERE ps2.ps_par = CombinedPS.ps_comp) THEN 'SFG'
            ELSE 'RM'
        END AS [Structure_Type],
        0 AS LEVEL
    FROM CombinedPS
    WHERE ps_par IN (SELECT ItemNumber FROM CustomerItems)
    
    UNION ALL
    
    SELECT 
        h.root_parent,
        m.ps_par AS current_parent,
        m.ps_comp AS component,
        h.[Plant],
        m.ps_qty_per,
        m.ps_rmks,
        CASE 
            WHEN EXISTS (SELECT 1 FROM CombinedPS ps2 WHERE ps2.ps_par = m.ps_comp) THEN 'SFG'
            ELSE 'RM'
        END AS [Structure_Type],
        h.LEVEL + 1
    FROM CombinedPS m
    INNER JOIN BOMHierarchy h
        ON m.ps_par = h.component
        AND m.[Plant] = h.[Plant]
    WHERE LEVEL < 10
),

BOM_RM AS (
    SELECT DISTINCT
        component AS ps_comp,
        ps_rmks
    FROM BOMHierarchy
    WHERE Structure_Type = 'RM'
)

SELECT DISTINCT
    po.[po_vend] as [Supplier],
    [pod_sd_pat] as [Ship Delivery Pattern],
    [pod_translt_days] as [PO Transport Days],
    [pod_firm_days] as [Firm Days],
    [pod_ord_mult]  as [Order Multiple],
    po.[po__chr09] as [Supplier Email],
    [pod_nbr] as [Purchase Order],
    [pod__chr08] as [PO Line Planner],
    po.[po_eff_strt] as [PO Line Start Eff],
    [pod_plan_weeks] as [Planned Weeks],
    [pod_curr_rlse_id[1]]] as [PO Release ID],
    [pod_line] as [Purchase Order Line],
    [pod_sftylt_days] as [PO Safety Days],
    [pod_part] as [Item Number],
    [pod_cum_qty[1]]] as [PO Cum Required],
    [pod_qty_rcvd] as [Cum Received],
    [pod_cum_date[1]]] as [PO Cum Date],
    brm.ps_comp,
    brm.ps_rmks
FROM [QADEE2798].[dbo].[pod_det]
JOIN [QADEE2798].[dbo].[po_mstr] po
    ON [pod_nbr] = po.[po_nbr]
INNER JOIN BOM_RM brm
    ON [pod_part] = brm.ps_comp  -- Join on RM component
WHERE [pod_status] IS NULL
  AND [pod_end_eff[1]]] > GETDATE()
ORDER BY [Item Number];