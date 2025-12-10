WITH PodData AS (
    -- This CTE gathers all the necessary PO and item data.
    -- Note the correction of column names like [pod_cum_qty[1]] (removed an extra ']')
    SELECT  
        pd.[pod_po_site] AS [Plant],  
        pd.[pod__chr08] AS [PO Item buyer],  
        pm.[po_vend] AS [PO Supplier],  
        pd.[pod_nbr] AS [PO Number],  
        pd.[pod_line] AS [PO Line],  
        pd.[pod_part] AS [Item Number],  
        pd.[pod_cum_qty[1]]] AS [Received Qty],  
        pd.[pod_ord_mult] AS [Standard Pack],  
        pd.[pod_translt_days] AS [Transport Days],
        pd.[pod_start_eff[1]]] AS [Start Effective Date],
        pd.[pod_curr_rlse_id[1]]] AS [PO Release ID],
        pd.[pod_end_eff[1]]] AS [End Effective Date]
    FROM  
        [QADEE2798].[dbo].[pod_det] pd  
        JOIN [QADEE2798].[dbo].[po_mstr] pm ON pd.[pod_nbr] = pm.[po_nbr]
),
-- Calculate active item counts by plant for the duplicate check
ActiveItemCounts AS (
    SELECT 
        [Plant],
        [Item Number],
        COUNT(*) AS ActiveItemCount
    FROM 
        PodData
    WHERE
        [End Effective Date] > GETDATE() -- Only count active items
    GROUP BY 
        [Plant], 
        [Item Number]
),
-- Identify suppliers present in both plants
DualSuppliers AS (
    SELECT 
        [PO Supplier]
    FROM 
        PodData
    GROUP BY 
        [PO Supplier]
    HAVING 
        COUNT(DISTINCT [Plant]) > 1
),
-- Identify suppliers with inconsistent transport days
TransportDaysCheck AS (
    SELECT
        [PO Supplier],
        CASE 
            WHEN COUNT(DISTINCT [Transport Days]) > 1 THEN 'NOK'
            ELSE NULL
        END AS HasInconsistentTransportDays
    FROM
        PodData
    GROUP BY
        [PO Supplier]
)
-- Main query: Joins PO data with schedule data and applies all checks
SELECT 
    -- Columns from the PO query (with 'Plant' removed as requested)
    pd.[PO Item buyer],
    pd.[PO Supplier],
    ad.[ad_name] AS [Supplier Name],
    pd.[PO Number],
    pd.[PO Line],
    pd.[Item Number],
    pd.[Received Qty],
    pd.[Standard Pack],
    pd.[Transport Days],
    pd.[Start Effective Date],
    pd.[PO Release ID],
    -- Status and check columns
    CASE 
        WHEN pd.[End Effective Date] > GETDATE() THEN 'Active'
        ELSE 'Closed'
    END AS [Active/Closed],
    CASE 
        WHEN aic.ActiveItemCount > 1 AND pd.[End Effective Date] > GETDATE() THEN 'Yes'
        ELSE NULL
    END AS [Duplicate PO Line],
    CASE 
        WHEN ds.[PO Supplier] IS NOT NULL THEN 'Yes'
        ELSE NULL
    END AS [Dual Supplier],
    tdc.HasInconsistentTransportDays AS [Transport Days Check],
    CASE 
        WHEN pd.[End Effective Date] < GETDATE() AND pd.[PO Release ID] IS NOT NULL THEN 'Yes'
        ELSE NULL
    END AS [Inactive_Release_Check],
    
    -- Columns from the schedule query
    sch.[schd_rlse_id] AS [Schedule Release ID],
    sch.[schd_date] AS [Schedule release Date],
    sch.[schd_discr_qty] AS [Schedule Qty],
    sch.[schd_fc_qual],
    sch.[schd_interval],
    sch.[schd_cum_qty] AS [Schedule Cum Qty],
    sch.[schd__chr02],
    sch.[schd__dte02],
    sch.[schd_upd_qty]

FROM 
    PodData pd
-- Join to the schedule table on PO and Line, and filter out zero quantities
LEFT JOIN 
    [QADEE2798].[dbo].[act_sup_schedules] sch ON pd.[PO Number] = sch.[schd_nbr] AND pd.[PO Line] = sch.[schd_line] AND sch.[schd_discr_qty] <> 0
-- Other LEFT JOINs for checks and additional data
LEFT JOIN 
    [QADEE2798].[dbo].[ad_mstr] ad ON pd.[PO Supplier] = ad.[ad_addr]
LEFT JOIN 
    ActiveItemCounts aic ON pd.[Plant] = aic.[Plant] AND pd.[Item Number] = aic.[Item Number]
LEFT JOIN 
    DualSuppliers ds ON pd.[PO Supplier] = ds.[PO Supplier]
LEFT JOIN
    TransportDaysCheck tdc ON pd.[PO Supplier] = tdc.[PO Supplier]
ORDER BY 
    pd.[PO Number], 
    pd.[PO Line];