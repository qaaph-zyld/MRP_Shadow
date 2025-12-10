WITH ParentItems AS (
    -- First identify all parent items (where tr_type = 'RCT-WO')
    SELECT DISTINCT
        tr_part AS parent_item,
        tr_lot,
		tr_effdate
    FROM [QADEE2798].[dbo].[tr_hist]
    WHERE 
    [tr_type] IN ('RCT-WO', 'ISS-WO', 'ISS-UNP', 'CYC-RCNT', 'RCT-PO', 'ISS-PRV', 'ISS-SCRP', 'ISS-SO')
    AND tr_effdate >= '2024-10-01'
),

BaseData AS (
    -- Get all relevant transactions with calculated fields
    SELECT
        MONTH(CONVERT(date, tr_effdate)) AS [Month],
        h.tr_lot,
		h.tr_effdate,
        h.tr_part,
        h.tr_type,
        h.tr_prod_line,
        h.tr_mtl_std,
        h.tr_qty_chg,
        h.tr_mtl_std * h.tr_qty_chg AS amount
    FROM [QADEE2798].[dbo].[tr_hist] h
    WHERE 
    [tr_type] IN ('RCT-WO', 'ISS-WO', 'ISS-UNP', 'CYC-RCNT', 'RCT-PO', 'ISS-PRV', 'ISS-SCRP', 'ISS-SO')
    AND tr_effdate >= '2024-10-01'
)

SELECT 
    b.[Month],
    p.parent_item AS [Parent Item],
    b.tr_lot,
	b.tr_effdate,
    b.tr_part,
    b.tr_type,
    b.tr_prod_line,
    b.tr_mtl_std,
    SUM(-b.tr_qty_chg) AS total_qty_change,  -- Move - sign inside SUM
    SUM(-b.amount) AS total_amount  -- Move - sign inside SUM
FROM BaseData b
LEFT JOIN ParentItems p ON b.tr_lot = p.tr_lot
GROUP BY 
    b.[Month],
    p.parent_item,
    b.tr_lot,
	b.tr_effdate,
    b.tr_part,
    b.tr_type,
    b.tr_prod_line,
    b.tr_mtl_std
ORDER BY 
    b.[Month],
    p.parent_item,
    b.tr_lot;
