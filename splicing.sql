WITH SplitBatches AS (
    SELECT 
        CAST([ROLE_END] AS DATE) AS ROLL_CUT_DATE,
        CONVERT(VARCHAR(8), CAST([ROLE_END] AS TIME), 108) AS ROLL_CUT_TIME,
        [ROLE_SERIALNUMBER],
        [ROLE_PARTNUMBER],
        [ROLE_CONSUMPTION],
        CAST([ROLE_BATCH] AS NVARCHAR(MAX)) AS ROLE_BATCH,
        CAST(CHARINDEX(' ', [ROLE_BATCH] + ' ') AS INT) AS SpacePos,
        CAST(SUBSTRING([ROLE_BATCH], 1, CHARINDEX(' ', [ROLE_BATCH] + ' ') - 1) AS NVARCHAR(MAX)) AS FirstBatch,
        CAST(STUFF([ROLE_BATCH], 1, CHARINDEX(' ', [ROLE_BATCH] + ' '), '') AS NVARCHAR(MAX)) AS RemainingBatches,
        CASE WHEN CHARINDEX('TEST', [ROLE_BATCH]) > 0 THEN 1 ELSE 0 END AS IsTest
    FROM [Splicing_265].[dbo].[TRole]
    WHERE YEAR([ROLE_START]) = YEAR(GETDATE())
      AND MONTH([ROLE_START]) = MONTH(GETDATE())

    UNION ALL

    SELECT 
        ROLL_CUT_DATE,
        ROLL_CUT_TIME,
        [ROLE_SERIALNUMBER],
        [ROLE_PARTNUMBER],
        [ROLE_CONSUMPTION],
        CAST(RemainingBatches AS NVARCHAR(MAX)),
        CAST(CHARINDEX(' ', RemainingBatches + ' ') AS INT) AS SpacePos,
        CAST(SUBSTRING(RemainingBatches, 1, CHARINDEX(' ', RemainingBatches + ' ') - 1) AS NVARCHAR(MAX)) AS FirstBatch,
        CAST(STUFF(RemainingBatches, 1, CHARINDEX(' ', RemainingBatches + ' '), '') AS NVARCHAR(MAX)) AS RemainingBatches,
        IsTest
    FROM SplitBatches
    WHERE RemainingBatches > '' AND IsTest = 0
)
SELECT 
    ROLL_CUT_DATE,
    ROLL_CUT_TIME,
    CASE WHEN IsTest = 1 THEN ROLE_BATCH ELSE FirstBatch END AS ROLE_BATCH,
    [ROLE_SERIALNUMBER],
    [ROLE_PARTNUMBER],
    [ROLE_CONSUMPTION]
FROM SplitBatches
ORDER BY 
    ROLL_CUT_DATE,
    ROLL_CUT_TIME,
    ROLE_BATCH,
    [ROLE_SERIALNUMBER];