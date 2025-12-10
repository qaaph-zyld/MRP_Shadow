-- Distinct supplier information
WITH 
CustomerItems AS (
    SELECT DISTINCT [sod_part] AS ItemNumber 
    FROM [QADEE2798].[dbo].[sod_det] 
),
CombinedPS AS (
    SELECT [ps_par] AS ItemNumber
    FROM [QADEE2798].[dbo].[ps_mstr]
    WHERE [ps_end] IS NULL AND [ps_par] IN (SELECT ItemNumber FROM CustomerItems)
    UNION
    SELECT [pt_part] AS ItemNumber
    FROM [QADEE2798].[dbo].[pt_mstr]
    WHERE [pt_status] = 'ACTIVE'
),
BOMHierarchy AS (
    SELECT 
        parent.[ps_par] AS parent,
        parent.[ps_comp] AS component,
        1 AS level
    FROM [QADEE2798].[dbo].[ps_mstr] parent
    INNER JOIN CombinedPS ON parent.[ps_par] = CombinedPS.ItemNumber
    WHERE parent.[ps_end] IS NULL
    
    UNION ALL
    
    SELECT 
        child.[ps_par] AS parent,
        child.[ps_comp] AS component,
        h.level + 1
    FROM [QADEE2798].[dbo].[ps_mstr] child
    INNER JOIN BOMHierarchy h ON child.[ps_par] = h.component
    WHERE child.[ps_end] IS NULL
),
classified_items AS (
    SELECT ItemNumber FROM CustomerItems
    UNION
    SELECT component AS ItemNumber FROM BOMHierarchy
)

SELECT DISTINCT
    po.[po_vend] as [Supplier],
    ad.[ad_sort] as [Supplier Sort Name],
    ad.[ad_name] as [Supplier Name],
    ad.[ad_line1] as [Supplier Address],
    ad.[ad_city] as [City],
    ad.[ad_country] as [Country],
    pod.[pod_sd_pat] as [Ship Delivery Pattern],
    pod.[pod_translt_days] as [PO Transport Days],
    pod.[pod_firm_days] as [Firm Days],
    po.[po__chr09] as [Supplier Email],
    pod.[pod_nbr] as [Purchase Order],
    pod.[pod__chr08] as [PO Line Planner],
    pod.[pod_plan_weeks] as [Planned Weeks]
FROM [QADEE2798].[dbo].[pod_det] pod
INNER JOIN classified_items ci ON pod.[pod_part] = ci.ItemNumber
JOIN [QADEE2798].[dbo].[po_mstr] po ON pod.[pod_nbr] = po.[po_nbr]
JOIN [QADEE2798].[dbo].[ad_mstr] ad ON po.[po_vend] = ad.[ad_addr]
WHERE pod.[pod_status] IS NULL AND pod.[pod_end_eff[1]]] > GETDATE()
ORDER BY [Supplier]
