/*
Diamond / Schedule Variance Report (STUB)
----------------------------------------

This is a placeholder query for the diamond report / schedule variance.

ASSUMPTIONS (to be validated on Monday):
- Each time a new supplier release is sent/loaded, a snapshot of the full schedule is saved
  ONLY if it differs from the last saved version.
- Table: [QADEE2798].[dbo].[sa_release_hist] (NAME IS A GUESS)
- Expected columns (names ARE GUESSES, replace with real ones):
    sr_supplier       -- Supplier code
    sr_site           -- Site / Plant
    sr_item           -- Item Number
    sr_release_id     -- Release identifier (QAD schedule ID)
    sr_snapshot_ts    -- Snapshot timestamp
    sr_week           -- ISO week number of requirement
    sr_year           -- Year
    sr_qty            -- Required quantity for that week in that snapshot

Goal:
- For each supplier / item / week, compare the **latest** snapshot to the **previous** one
  and show the delta (increase/decrease), to support:
  - Customer & Supplier Diamond Report
  - Schedule Variance browses/reports.
*/

WITH ReleaseHistory AS (
    SELECT
        sr_supplier,
        sr_site,
        sr_item,
        sr_release_id,
        sr_snapshot_ts,
        sr_year,
        sr_week,
        sr_qty
    FROM [QADEE2798].[dbo].[sa_release_hist]
    -- TODO: adjust table/column names to the real release history structure
),
Ranked AS (
    SELECT
        sr_supplier,
        sr_site,
        sr_item,
        sr_year,
        sr_week,
        sr_release_id,
        sr_snapshot_ts,
        sr_qty,
        ROW_NUMBER() OVER (
            PARTITION BY sr_supplier, sr_site, sr_item, sr_year, sr_week
            ORDER BY sr_snapshot_ts DESC
        ) AS rn
    FROM ReleaseHistory
),
CurrentSnapshot AS (
    SELECT *
    FROM Ranked
    WHERE rn = 1
),
PreviousSnapshot AS (
    SELECT *
    FROM Ranked
    WHERE rn = 2
)
SELECT
    c.sr_supplier      AS [Supplier],
    c.sr_site          AS [Site],
    c.sr_item          AS [Item Number],
    c.sr_year          AS [Year],
    c.sr_week          AS [Week],
    c.sr_qty           AS [Current Qty],
    p.sr_qty           AS [Previous Qty],
    (c.sr_qty - ISNULL(p.sr_qty,0)) AS [Delta Qty],
    CASE 
        WHEN p.sr_qty IS NULL THEN 'New'
        WHEN c.sr_qty = p.sr_qty THEN 'Unchanged'
        WHEN c.sr_qty > p.sr_qty THEN 'Increase'
        WHEN c.sr_qty < p.sr_qty THEN 'Decrease'
        ELSE 'Unknown'
    END AS [Change Flag],
    c.sr_release_id    AS [Current Release ID],
    p.sr_release_id    AS [Previous Release ID],
    c.sr_snapshot_ts   AS [Current Snapshot TS],
    p.sr_snapshot_ts   AS [Previous Snapshot TS]
FROM CurrentSnapshot c
LEFT JOIN PreviousSnapshot p
  ON  c.sr_supplier = p.sr_supplier
  AND c.sr_site     = p.sr_site
  AND c.sr_item     = p.sr_item
  AND c.sr_year     = p.sr_year
  AND c.sr_week     = p.sr_week
ORDER BY
    c.sr_supplier,
    c.sr_site,
    c.sr_item,
    c.sr_year,
    c.sr_week;
