# Shadow MRP Output Validation Checklist

Use this checklist to verify that the Shadow MRP query output is correct.

---

## 1. Structure Checks

| Check | Expected | How to Verify |
|-------|----------|---------------|
| **Column count** | 19 columns | Count headers in CSV |
| **Required columns present** | `Site, ItemNumber, ItemType, Supplier, SupplierName, DueDateYear, DueDateWeek, PlannedOrderDueDate, PlannedOrderReleaseDate, DemandBucketType, GrossRequirement, ScheduledReceipts, ProjectedOnHandBefore, NetRequirement, PlannedOrderQty, ProjectedOnHandAfter, SafetyStock, StandardPack, TransportDays` | Check header row |
| **No NULL key fields** | `Site`, `ItemNumber`, `DueDateYear`, `DueDateWeek` never NULL | Filter for blanks |

---

## 2. Uniqueness / Aggregation Checks

| Check | Expected | How to Verify |
|-------|----------|---------------|
| **One row per item/week** | Each `(Site, ItemNumber, DueDateYear, DueDateWeek)` appears at most once | `GROUP BY` count = 1 for all |
| **No duplicate Future rows** | Items in `Future` bucket should have distinct `DueDateWeek` values | Filter `DemandBucketType = 'Future'`, check for duplicates |

**PowerShell check:**
```powershell
# Count duplicates per item/year/week
Import-Csv output.csv | Group-Object Site, ItemNumber, DueDateYear, DueDateWeek | Where-Object { $_.Count -gt 1 } | Measure-Object
# Expected: Count = 0
```

---

## 3. Item Type Distribution

| Check | Expected | How to Verify |
|-------|----------|---------------|
| **FG items present** | > 0 rows with `ItemType = 'FG'` | Filter and count |
| **RM items present** | > 0 rows with `ItemType = 'RM'` | Filter and count |
| **SFG items present** | ≥ 0 rows (depends on BOM structure) | Filter and count |
| **No unexpected types** | Only `FG`, `SFG`, `RM`, `No BOM` | Distinct values check |

---

## 4. Demand Bucket Checks

| Check | Expected | How to Verify |
|-------|----------|---------------|
| **Valid bucket types** | Only: `Past_Due`, `Current_Week`, `Week_1`..`Week_8`, `Future` | Distinct values |
| **Past_Due dates** | `PlannedOrderDueDate < TODAY` | Filter and verify |
| **Current_Week dates** | `PlannedOrderDueDate` within current ISO week | Spot check |
| **Week_N ordering** | `Week_1` before `Week_2` before ... `Week_8` before `Future` | Sort by item, check sequence |

---

## 5. MRP Logic Checks (CRITICAL)

### 5.1 Projected On-Hand Continuity

| Check | Expected | How to Verify |
|-------|----------|---------------|
| **First period starts from inventory** | For each item, earliest week's `ProjectedOnHandBefore` = initial on-hand from `[15]` table | Compare to inventory snapshot |
| **Continuity across weeks** | `ProjectedOnHandAfter(week t)` = `ProjectedOnHandBefore(week t+1)` | For any item, verify adjacent rows |

**This is the most important check.** If `ProjectedOnHandBefore` of week 2 does NOT equal `ProjectedOnHandAfter` of week 1, the netting logic is broken.

**Manual spot-check for item X:**
```
Week 1: ProjectedOnHandAfter = 100,000
Week 2: ProjectedOnHandBefore should = 100,000
```

### 5.2 Net Requirement Calculation

| Check | Expected | How to Verify |
|-------|----------|---------------|
| **NetRequirement >= 0** | Never negative | Filter `NetRequirement < 0` → should be empty |
| **NetRequirement = 0 when stock sufficient** | If `ProjectedOnHandBefore + ScheduledReceipts - GrossRequirement >= SafetyStock`, then `NetRequirement = 0` | Spot check rows with `NetRequirement = 0` |
| **NetRequirement > 0 only when needed** | If end-of-week stock would fall below `SafetyStock`, then `NetRequirement = SafetyStock - (projected end stock)` | Spot check rows with `NetRequirement > 0` |

### 5.3 Planned Order Quantity

| Check | Expected | How to Verify |
|-------|----------|---------------|
| **PlannedOrderQty >= 0** | Never negative | Filter `PlannedOrderQty < 0` → should be empty |
| **PlannedOrderQty = 0 when NetRequirement = 0** | No planned order if no shortage | Filter where `NetRequirement = 0 AND PlannedOrderQty > 0` → should be empty |
| **PlannedOrderQty is multiple of StandardPack** | `PlannedOrderQty % StandardPack = 0` (when StandardPack > 1) | Filter where `StandardPack > 1`, check modulo |
| **PlannedOrderQty >= NetRequirement** | Rounded up to cover shortage | Filter where `PlannedOrderQty < NetRequirement AND NetRequirement > 0` → should be empty |

### 5.4 Projected On-Hand After

| Check | Expected | How to Verify |
|-------|----------|---------------|
| **Formula correct** | `ProjectedOnHandAfter = ProjectedOnHandBefore + ScheduledReceipts + PlannedOrderQty - GrossRequirement` | Recalculate for sample rows |
| **ProjectedOnHandAfter >= SafetyStock** | After planned order, stock should meet safety | Filter where `ProjectedOnHandAfter < SafetyStock AND PlannedOrderQty > 0` → should be empty |

---

## 6. Date Checks

| Check | Expected | How to Verify |
|-------|----------|---------------|
| **PlannedOrderReleaseDate <= PlannedOrderDueDate** | Release is before or equal to due | Filter where `PlannedOrderReleaseDate > PlannedOrderDueDate` → should be empty |
| **Lead time applied** | `PlannedOrderDueDate - PlannedOrderReleaseDate = TransportDays` | Spot check |

---

## 7. Quantity Sanity Checks

| Check | Expected | How to Verify |
|-------|----------|---------------|
| **GrossRequirement >= 0** | Never negative | Filter `GrossRequirement < 0` → should be empty |
| **ScheduledReceipts >= 0** | Never negative | Filter `ScheduledReceipts < 0` → should be empty |
| **No runaway planned orders** | `PlannedOrderQty` should not grow exponentially week-over-week for same item | Plot or eyeball Future weeks |
| **Reasonable magnitudes** | Quantities should be in expected range for the business | Spot check max values |

---

## 8. Sample Item Walk-Through

Pick one RM item with demand across multiple weeks and manually verify:

```
Item: [example: 108363-1M_C]
Initial Inventory: 462,000 (from [15] table)

Week    | GrossReq | SchedRcpt | ProjOHBefore | NetReq | PlannedOrd | ProjOHAfter
--------|----------|-----------|--------------|--------|------------|------------
Past_Due|   6,699  |     0     |   462,000    |   0    |     0      |  455,301
Week_1  |  24,881  |     0     |   455,301    |   0    |     0      |  430,420
Week_2  |  ...     |    ...    |   430,420    |  ...   |    ...     |   ...
...     |  ...     |    ...    |     ↓        |  ...   |    ...     |    ↓
Future  | 157,900  |     0     |   51,460     | 106,440| 106,440    |      0
Future+1| 157,900  |     0     |       0      | 157,900| 157,900    |      0
```

**Key verification:**
- `ProjOHAfter` of row N = `ProjOHBefore` of row N+1
- `PlannedOrderQty` only appears when `ProjOHBefore + SchedRcpt - GrossReq < SafetyStock`

---

## 9. Row Count Reasonableness

| Check | Expected | How to Verify |
|-------|----------|---------------|
| **Total rows** | Thousands to tens of thousands (not millions) | `wc -l` or row count |
| **Rows per item** | ~10-30 rows per item (one per week with demand) | `GROUP BY ItemNumber`, check max |

If row count is in the hundreds of thousands, aggregation may still be broken.

---

## 10. Quick PowerShell Validation Script

```powershell
$csv = Import-Csv "output.csv"

# 1. Row count
Write-Host "Total rows: $($csv.Count)"

# 2. Duplicates per item/week
$dupes = $csv | Group-Object Site, ItemNumber, DueDateYear, DueDateWeek | Where-Object { $_.Count -gt 1 }
Write-Host "Duplicate item/week combinations: $($dupes.Count)"

# 3. Item type distribution
$csv | Group-Object ItemType | Select-Object Name, Count | Format-Table

# 4. Negative quantities
$negGross = ($csv | Where-Object { [decimal]$_.GrossRequirement -lt 0 }).Count
$negPlan = ($csv | Where-Object { [decimal]$_.PlannedOrderQty -lt 0 }).Count
$negNet = ($csv | Where-Object { [decimal]$_.NetRequirement -lt 0 }).Count
Write-Host "Negative GrossRequirement: $negGross"
Write-Host "Negative PlannedOrderQty: $negPlan"
Write-Host "Negative NetRequirement: $negNet"

# 5. Continuity check (sample one item)
$item = $csv | Where-Object { $_.ItemNumber -eq "108363-1M_C" } | Sort-Object { [int]$_.DueDateYear }, { [int]$_.DueDateWeek }
$item | Select-Object DueDateYear, DueDateWeek, DemandBucketType, GrossRequirement, ProjectedOnHandBefore, PlannedOrderQty, ProjectedOnHandAfter | Format-Table
```

---

## Summary: Pass/Fail Criteria

| Category | Pass Condition |
|----------|----------------|
| **Structure** | All 19 columns present, no NULL keys |
| **Uniqueness** | Zero duplicate `(Site, ItemNumber, Year, Week)` rows |
| **Continuity** | `ProjectedOnHandAfter(t) = ProjectedOnHandBefore(t+1)` for all items |
| **Net Requirement** | Always >= 0, only > 0 when shortage exists |
| **Planned Orders** | Multiple of StandardPack, >= NetRequirement, brings stock to SafetyStock |
| **No Runaway** | PlannedOrderQty does not explode in Future weeks |
| **Row Count** | Reasonable (thousands, not hundreds of thousands) |

If all checks pass, the Shadow MRP output is valid.
