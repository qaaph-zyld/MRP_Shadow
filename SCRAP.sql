WITH cov_data AS (
    SELECT 
        cov_btch_nbr, 
        cov_ws_code, 
        cov_counter, 
        cov_planned_qty
    FROM 
        [TCIS_MES2_265].[dbo].[cov_hist]
    WHERE 
        cov_btch_nbr IS NOT NULL
        AND cov_hu IS NOT NULL
        AND cov_counter IS NOT NULL
        AND cov_planned_qty IS NOT NULL
),
max_cov AS (
    SELECT 
        cov_btch_nbr, 
        cov_ws_code, 
        MAX(CAST(cov_counter AS INT)) AS max_counter
    FROM 
        cov_data
    GROUP BY 
        cov_btch_nbr, 
        cov_ws_code
),
selected_records AS (
    SELECT 
        cd.cov_btch_nbr, 
        cd.cov_ws_code, 
        cd.cov_counter, 
        cd.cov_planned_qty,
        CAST(cd.cov_planned_qty AS INT) - CAST(cd.cov_counter AS INT) AS scrap
    FROM 
        cov_data cd
    INNER JOIN max_cov mc
        ON cd.cov_btch_nbr = mc.cov_btch_nbr
        AND cd.cov_ws_code = mc.cov_ws_code
        AND CAST(cd.cov_counter AS INT) = mc.max_counter
)
SELECT DISTINCT
    sr.cov_ws_code,  -- Moved to the first column
    sr.cov_btch_nbr, 
    CAST(CAST(sr.cov_counter AS INT) AS VARCHAR(10)) AS cov_counter, 
    sr.cov_planned_qty,
    sr.scrap
FROM 
    selected_records sr
WHERE 
    sr.scrap <> 0
ORDER BY 
    sr.cov_ws_code;  -- Sorted by cov_ws_code