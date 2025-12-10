DECLARE @cols NVARCHAR(MAX),
        @query NVARCHAR(MAX);

-- Dynamically generate columns from distinct transaction dates
WITH DateRangeData AS (
    SELECT DISTINCT CONVERT(varchar, serh_trans_date, 23) AS serh_trans_date
    FROM (
        SELECT serh_trans_date 
        FROM [QADEE2798].[dbo].[serh_hist]
        WHERE serh_trans_date >= DATEADD(month, DATEDIFF(month, 0, GETDATE()), 0)
          AND serh_trans_date < DATEADD(month, DATEDIFF(month, 0, GETDATE()) + 1, 0)
          AND [serh_stage] NOT IN ('new', 'pending')
          AND [serh_trans_type] IN ('pck-bld')
        
        UNION
        
        SELECT serh_trans_date 
        FROM [QADEE].[dbo].[serh_hist]
        WHERE serh_trans_date >= DATEADD(month, DATEDIFF(month, 0, GETDATE()), 0)
          AND serh_trans_date < DATEADD(month, DATEDIFF(month, 0, GETDATE()) + 1, 0)
          AND [serh_stage] NOT IN ('new', 'pending')
          AND [serh_trans_type] IN ('pck-bld')
    ) AS SourceTable
)

-- Generate comma-separated list of columns
SELECT @cols = STUFF((
    SELECT ',' + QUOTENAME(serh_trans_date)
    FROM DateRangeData
    ORDER BY serh_trans_date
    FOR XML PATH(''), TYPE
).value('.', 'NVARCHAR(MAX)'), 1, 1, '');

-- Construct the dynamic SQL query
SET @query = N'
WITH pt_data AS (
    SELECT
        [pt_site],
        [pt_part],
        [pt_desc1],
        [pt_prod_line],
        [pt_group],
        [pt__chr02],
        [pt_dsgn_grp]
    FROM [QADEE2798].[dbo].[pt_mstr]
    UNION ALL
    SELECT
        [pt_site],
        [pt_part],
        [pt_desc1],
        [pt_prod_line],
        [pt_group],
        [pt__chr02],
        [pt_dsgn_grp]
    FROM [QADEE].[dbo].[pt_mstr]
),
serh_data AS (
    SELECT
        [serh_site],
        [serh_part],
        [serh_qty_chg],
        CONVERT(varchar, serh_trans_date, 23) AS serh_trans_date,
        CASE
            WHEN serh_site = ''2674'' THEN
                CASE
                    WHEN CAST(DATEADD(second, ISNULL(serh_trans_time, 0), ''1900-01-01'') AS time) >= ''06:01:00'' AND CAST(DATEADD(second, ISNULL(serh_trans_time, 0), ''1900-01-01'') AS time) < ''14:00:00'' THEN ''1st''
                    WHEN CAST(DATEADD(second, ISNULL(serh_trans_time, 0), ''1900-01-01'') AS time) >= ''14:01:00'' AND CAST(DATEADD(second, ISNULL(serh_trans_time, 0), ''1900-01-01'') AS time) < ''22:00:00'' THEN ''2nd''
                    WHEN CAST(DATEADD(second, ISNULL(serh_trans_time, 0), ''1900-01-01'') AS time) >= ''22:01:00'' OR CAST(DATEADD(second, ISNULL(serh_trans_time, 0), ''1900-01-01'') AS time) < ''06:00:00'' THEN ''3rd''
                END
            WHEN serh_site = ''2798'' THEN
                CASE
                    WHEN CAST(DATEADD(second, ISNULL(serh_trans_time, 0), ''1900-01-01'') AS time) >= ''06:01:00'' AND CAST(DATEADD(second, ISNULL(serh_trans_time, 0), ''1900-01-01'') AS time) < ''14:05:00'' THEN ''1st''
                    ELSE ''2nd''
                END
        END AS [shift],
        DATEPART(week, serh_trans_date) AS week,
        DATEPART(month, serh_trans_date) AS month
    FROM [QADEE2798].[dbo].[serh_hist]
    WHERE serh_trans_date >= DATEADD(month, DATEDIFF(month, 0, GETDATE()), 0)
      AND serh_trans_date < DATEADD(month, DATEDIFF(month, 0, GETDATE()) + 1, 0)
      AND [serh_stage] NOT IN (''new'', ''pending'')
      AND [serh_trans_type] IN (''pck-bld'')
      AND serh_trans_date IS NOT NULL
    UNION ALL
    SELECT
        [serh_site],
        [serh_part],
        [serh_qty_chg],
        CONVERT(varchar, serh_trans_date, 23) AS serh_trans_date,
        CASE
            WHEN serh_site = ''2674'' THEN
                CASE
                    WHEN CAST(DATEADD(second, ISNULL(serh_trans_time, 0), ''1900-01-01'') AS time) >= ''06:01:00'' AND CAST(DATEADD(second, ISNULL(serh_trans_time, 0), ''1900-01-01'') AS time) < ''14:00:00'' THEN ''1st''
                    WHEN CAST(DATEADD(second, ISNULL(serh_trans_time, 0), ''1900-01-01'') AS time) >= ''14:01:00'' AND CAST(DATEADD(second, ISNULL(serh_trans_time, 0), ''1900-01-01'') AS time) < ''22:00:00'' THEN ''2nd''
                    WHEN CAST(DATEADD(second, ISNULL(serh_trans_time, 0), ''1900-01-01'') AS time) >= ''22:01:00'' OR CAST(DATEADD(second, ISNULL(serh_trans_time, 0), ''1900-01-01'') AS time) < ''06:00:00'' THEN ''3rd''
                END
            WHEN serh_site = ''2798'' THEN
                CASE
                    WHEN CAST(DATEADD(second, ISNULL(serh_trans_time, 0), ''1900-01-01'') AS time) >= ''06:01:00'' AND CAST(DATEADD(second, ISNULL(serh_trans_time, 0), ''1900-01-01'') AS time) < ''14:05:00'' THEN ''1st''
                    ELSE ''2nd''
                END
        END AS [shift],
        DATEPART(week, serh_trans_date) AS week,
        DATEPART(month, serh_trans_date) AS month
    FROM [QADEE].[dbo].[serh_hist]
    WHERE serh_trans_date >= DATEADD(month, DATEDIFF(month, 0, GETDATE()), 0)
      AND serh_trans_date < DATEADD(month, DATEDIFF(month, 0, GETDATE()) + 1, 0)
      AND [serh_stage] NOT IN (''new'', ''pending'')
      AND [serh_trans_type] IN (''pck-bld'')
      AND serh_trans_date IS NOT NULL
),
CombinedData AS (
    SELECT
        sd.serh_site,
        pd.pt__chr02,
        pd.pt_dsgn_grp,
        pd.pt_prod_line,
        pd.pt_group,
        sd.serh_part,
        pd.pt_desc1,
        sd.month,
        sd.week,
        sd.shift,
        sd.serh_trans_date,
        sd.serh_qty_chg
    FROM serh_data sd
    LEFT JOIN pt_data pd
        ON sd.serh_site = pd.pt_site
        AND sd.serh_part = pd.pt_part
    WHERE pd.pt__chr02 IN (''FG'', ''SFG'')
)
SELECT 
    serh_site,
    pt__chr02,
    pt_dsgn_grp,
    pt_prod_line,
    pt_group,
    serh_part,
    pt_desc1,
    month,
    week,
    shift,
    ' + @cols + '
FROM (
    SELECT
        serh_site,
        pt__chr02,
        pt_dsgn_grp,
        pt_prod_line,
        pt_group,
        serh_part,
        pt_desc1,
        month,
        week,
        shift,
        serh_trans_date,
        serh_qty_chg
    FROM CombinedData
) AS SourceTable
PIVOT (
    SUM(serh_qty_chg)
    FOR serh_trans_date IN (' + @cols + ')
) AS PivotTable
ORDER BY 
    [serh_site],
    [month],
    [week],
    [pt__chr02],
    [pt_dsgn_grp],
    [pt_prod_line],
    [pt_group],
    [serh_part],
    [pt_desc1],
	[shift];';

-- Execute the dynamic SQL
EXEC sp_executesql @query;