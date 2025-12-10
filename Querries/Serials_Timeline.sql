WITH ModifiedPackd AS (
    SELECT 
        SUBSTRING([pckpackd_hu], 2, LEN([pckpackd_hu])) AS pckpackd_hu, -- Remove the first character 'S'
        [pckpackd_qty_pack],
        [pckpackd_qty_act],
        ([pckpackd_qty_pack] - [pckpackd_qty_act]) AS scrap
    FROM 
        [TCIS_MES2_265].[dbo].[pckpackd_det]
    WHERE 
        [pckpackd_qty_act] IS NOT NULL 
        AND [pckpackd_qty_pack] IS NOT NULL 
        AND [pckpackd_qty_act] > 0
        AND ([pckpackd_qty_pack] - [pckpackd_qty_act]) <> 0
)
SELECT 
    CAST(i.ihu_date AS DATE) AS ihu_date_only,
    CASE 
        WHEN i.ihu_plant = '2798' THEN
            CASE 
                WHEN CONVERT(VARCHAR(8), CAST(i.ihu_date AS TIME), 108) BETWEEN '06:00:00' AND '14:00:00' THEN '1st'
                ELSE '2nd'
            END
        ELSE
            CASE 
                WHEN CONVERT(VARCHAR(8), CAST(i.ihu_date AS TIME), 108) BETWEEN '06:00:00' AND '14:00:00' THEN '1st'
                WHEN CONVERT(VARCHAR(8), CAST(i.ihu_date AS TIME), 108) BETWEEN '14:00:00' AND '22:00:00' THEN '2nd'
                ELSE '3rd'
            END
    END AS shift,
    b.ibck_qty,
    b.ibck_btch_nbr,
    b.ibck_hu,
    t.trbtch_prd_qty,
    t.trbtch_comp_ifs,
    t.trbtch_comp_qty,
    ws.ws_name,
    c.cust_name
FROM 
    [TCIS_MES2_265].[dbo].[ihu_mstr] i
INNER JOIN 
    [TCIS_MES2_265].[dbo].[ibck_mstr] b ON i.ihu_hu = b.ibck_hu
INNER JOIN 
    [TCIS_MES2_265].[dbo].[trbtch_mstr] t ON t.trbtch_nbr = b.ibck_btch_nbr
       AND t.trbtch_piid_name = i.ihu_piid_name
       AND t.trbtch_comp_ifs = b.ibck_mat
LEFT JOIN 
    [TCIS_MES2_265].[dbo].[ws_mstr] ws ON t.trbtch_workshop = ws.ws_code
LEFT JOIN (
    SELECT 
        cust_kanban,
        cust_name,
        cust_data1,
        ROW_NUMBER() OVER (PARTITION BY cust_kanban ORDER BY cust_name) AS rn
    FROM [TCIS_MES2_265].[dbo].[cust_mstr]
    WHERE cust_kanban IS NOT NULL
) c ON t.trbtch_customer = c.cust_kanban AND c.rn = 1 AND t.trbtch_customer IS NOT NULL
LEFT JOIN 
    ModifiedPackd p ON b.ibck_hu = p.pckpackd_hu
ORDER BY 
    i.ihu_btch_nbr, i.ihu_piid_name, i.ihu_hu;