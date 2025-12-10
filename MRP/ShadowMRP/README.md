# Shadow MRP Pipeline

## Overview

A SQL-based "shadow" MRP system that computes planned orders from customer demand, BOM explosion, inventory, and PO parameters. Runs entirely in SQL Server and can be refreshed on-demand whenever EDI/customer schedules change.

## Quick Start

### 1. Deploy the Pipeline

Run the master script in SSMS:

```sql
-- Execute in QADEE2798 database context
:r "C:\Users\ajelacn\OneDrive - Adient\Documents\SQL Server Management Studio\MRP\ShadowMRP\99_Master_Execute.sql"
```

Or open `99_Master_Execute.sql` and execute it.

### 2. Refresh Planned Orders

After any EDI/demand change, run:

```sql
EXEC dbo.usp_Rebuild_ShadowMRP_PlannedOrders;
```

### 3. View Results

**Ready-to-confirm schedule releases:**
```sql
SELECT * FROM dbo.v_ShadowMRP_ScheduleReleases 
WHERE ReleaseUrgency IN ('RELEASE NOW', 'RELEASE THIS WEEK')
ORDER BY Supplier, ItemNumber, DueDateWeek;
```

**Supplier schedules (for EDI transmission):**
```sql
SELECT * FROM dbo.v_ShadowMRP_SupplierSchedule 
ORDER BY Supplier, ItemNumber, DueDateWeek;
```

**Executive summary:**
```sql
SELECT * FROM dbo.v_ShadowMRP_Summary 
ORDER BY ItemType, DemandBucketType;
```

---

## File Structure

| File | Purpose |
|------|---------|
| `00_Create_PlannedOrders_Table.sql` | Target table schema |
| `01_Supporting_Views.sql` | Input views (demand, inventory, PO params) |
| `02_Rebuild_Procedure.sql` | Main MRP netting logic procedure |
| `03_Validation_Views.sql` | Validation and reporting views |
| `99_Master_Execute.sql` | **Single script to deploy everything** |

---

## Output Views

| View | Description |
|------|-------------|
| `v_ShadowMRP_ScheduleReleases` | Planned orders with release urgency flags |
| `v_ShadowMRP_SupplierSchedule` | Aggregated by supplier for schedule transmission |
| `v_ShadowMRP_Summary` | Totals by item type and time bucket |
| `v_ShadowMRP_ValidationVsQAD` | Compare against `mrp_det` (when available) |

---

## MRP Logic Summary

For each item/week:

1. **Gross Requirement** = BOM-exploded customer demand
2. **Scheduled Receipts** = Open PO quantities due in period
3. **Projected Available** = On-hand + Cumulative receipts - Cumulative demand
4. **Net Requirement** = Safety Stock - Projected Available (if negative)
5. **Planned Order Qty** = Net Requirement rounded up to Standard Pack

---

## Key Parameters Used

| Parameter | Source | Description |
|-----------|--------|-------------|
| `SafetyStock` | `pt_mstr.pt_sfty_stk` | Minimum stock level target |
| `StandardPack` | `pod_det.pod_ord_mult` | Order quantity multiple |
| `TransportDays` | `pod_det.pod_translt_days` | Lead time for release date |
| `Supplier` | `pod_det` → `po_mstr.po_vend` | Primary supplier per item |

---

## Validation Against QAD MRP

Once `mrp_det` is available:

```sql
-- Show mismatches between shadow and official MRP
SELECT * FROM dbo.v_ShadowMRP_ValidationVsQAD
WHERE ValidationStatus = 'MISMATCH'
ORDER BY ABS(Variance_PlannedQty) DESC;
```

---

## Next Steps After Verification

1. **Tune parameters** – Adjust safety stock, lot sizes based on validation results
2. **Add WO supply** – Include open work orders in scheduled receipts
3. **Add time fences** – Implement firm horizon (no changes inside X days)
4. **Automate refresh** – SQL Agent job triggered by EDI arrival
5. **Export to suppliers** – Generate EDI 830/862 from `v_ShadowMRP_SupplierSchedule`
6. **Dashboard** – Power BI connected to summary views

---

## Troubleshooting

**No data in planned orders?**
- Check `v_ShadowMRP_ComponentDemand` has demand rows
- Verify schedules exist in `active_schd_det` with future dates
- Confirm items have active BOM in `ps_mstr`

**Incorrect quantities?**
- Compare `v_ShadowMRP_Inventory` to QAD stock
- Check BOM `ps_qty_per` values
- Verify PO parameters in `v_ShadowMRP_POParams`

---

## Complete Pipeline Files

### Core MRP Query
| File | Purpose |
|------|---------|
| `04_ShadowMRP_ReadOnly_Query.sql` | Read-only MRP calculation (26-week horizon) |
| `05_Output_Validation_Checklist.md` | Manual validation checklist |

### Supplier Schedule Comparison
| File | Purpose |
|------|---------|
| `06_Active_Supplier_Schedules.sql` | Extract current supplier releases from QAD |
| `07_Compare_MRP_vs_SupplierSchedules.ps1` | Monthly aggregation & comparison |

### Parameter Validation & Sync
| File | Purpose |
|------|---------|
| `08_Parameter_Validation.sql` | Compare QAD vs IBT.csv parameters |
| `09_Anomaly_Detection.sql` | Periodic data quality scans |
| `IBT.csv` | Master transport parameter reference |

### Insight Generation
| File | Purpose |
|------|---------|
| `10_MRP_Insight_Engine.ps1` | Generate actionable insights & priorities |
| `Run_Full_Analysis.ps1` | **Master script to run entire pipeline** |

---

## Quick Start: Full Analysis

```powershell
cd "C:\Users\ajelacn\OneDrive - Adient\Documents\SQL Server Management Studio"
powershell -ExecutionPolicy Bypass -File "MRP\ShadowMRP\Run_Full_Analysis.ps1"
```

This will:
1. Run Shadow MRP query → `output\output.csv`
2. Run Supplier Schedules query → `output\output_supplier_releases.csv`
3. Compare MRP vs Supplier → `output\output_mrp_vs_supplier.csv`
4. Generate insights → `output\output_mrp_insights.csv`
5. Generate summary → `output\output_mrp_summary.csv`

---

## Output Files

| File | Description |
|------|-------------|
| `output.csv` | Shadow MRP planned orders by week |
| `output_supplier_releases.csv` | Active supplier schedule lines |
| `output_mrp_vs_supplier.csv` | Monthly comparison with status |
| `output_mrp_insights.csv` | Detailed insights with recommendations |
| `output_mrp_summary.csv` | Priority summary for review |
| `output_anomalies.csv` | Data quality issues detected |

---

## Insight Categories

| Category | Meaning | Action |
|----------|---------|--------|
| `UNDER_PLANNED` | MRP < Supplier Schedule | Check demand source, BOM, horizon |
| `MRP_BLIND_SPOT` | Supplier has schedule, MRP has nothing | Check if item is in BOM, PO active |
| `POTENTIAL_OVERSTOCK` | MRP plans more than supplier expects | Verify demand is real |
| `ALIGNED` | MRP ≈ Supplier Schedule | No action needed |
| `NO_ACTIVITY` | No demand in either system | Monitor only |

---

## Priority Levels

| Priority | Action Timeline |
|----------|-----------------|
| `Critical` | Immediate review (today) |
| `High` | Review within 1 week |
| `Medium` | Review within 2 weeks |
| `Low/OK` | Monitor only |

---

## Parameter Validation Workflow

1. **Load IBT.csv** to `#IBT_Master` temp table in SSMS
2. **Run** `08_Parameter_Validation.sql`
3. **Review** discrepancies between QAD and IBT
4. **Update** QAD parameters or IBT.csv as needed
5. **Re-run** full analysis to verify alignment

---

## Anomaly Detection

Run `09_Anomaly_Detection.sql` weekly to catch:
- Duplicate active PO lines for same item
- Items with demand but no PO line
- Invalid standard pack or transport days
- Stale releases on closed PO lines
- Orphaned schedules
- Excessive safety stock

---

## Version History

| Date | Change |
|------|--------|
| 2025-12-04 | Added parameter validation, anomaly detection, insight engine |
| 2025-12-03 | Added supplier comparison system |
| 2025-12-02 | Extended horizon to 26 weeks |
| 2025-11-30 | Initial version - core pipeline |
