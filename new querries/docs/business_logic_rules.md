# Business Logic Rules & Canonical Queries

This document captures the key business rules implemented in the SQL queries in this workspace and how we choose *canonical* queries when there are overlaps.

---

## 1. Priority & versioning rules

- **Folder roles**
  - `Querries/`  enriched, business-facing logic.
  - `MRP/`  technical/MRP building blocks and some older variants.
  - Workspace root `.sql` files  legacy utilities and plant-specific views.
  - `new querries/`  *entrypoints* that point to canonical implementations using SQLCMD `:r`.

- **Versioning rule (when business logic differs)**
  - Newer queries always take precedence over older ones.
  - In practice, the **canonical query is the one referenced from `new querries/`**.
  - When two files implement the same concept (same columns / same purpose):
    - Prefer the richer / more recently maintained implementation (currently almost always the `Querries/` version).
    - Keep the other file as **legacy** or **specialized** but do **not** reference it from `new querries/`.

- **How to change logic going forward**
  - Update the *canonical source file* (usually under `Querries/`).
  - Keep the wrapper in `new querries/` unchanged so the entrypoint path stays stable.

Canonical entrypoints created so far:

- `new querries/Demand/Customer_Demand.sql`  wraps `Querries/Customer_Demand.sql`.
- `new querries/Demand/Customer_Demand_per_BOM.sql`  wraps `Querries/Customer_Demand_per_BOM.sql`.
- `new querries/BOM/BOM_exploded.sql`  wraps `Querries/BOM_exploded.sql`.
- `new querries/Item_Master/Item_Master.sql`  wraps `Querries/Item_Master.sql`.
- `new querries/Item_Master/Item_Master_all_no_xc_rc.sql`  wraps `Querries/Item_Master_all_no_xc_rc.sql` (MRP copy is legacy duplicate).
- `new querries/Item_Master/Item_Master_Inventory_2798.sql`  wraps `Querries/Item_Master_Inventory_2798.sql` (root copy is legacy).

---

## 2. Demand domain

**Canonical queries**

- `Customer_Demand` (canonical: `Querries/Customer_Demand.sql`).
- `Customer_Demand_per_BOM` (canonical: `Querries/Customer_Demand_per_BOM.sql`).

**Key business rules**

- **Calendar & week handling**
  - `SET DATEFIRST 1`  weeks start on **Monday** (ISO-like).
  - Past vs future demand is determined relative to `GETDATE()`.

- **Time buckets (item-level demand)**
  - `Past Due`  all schedule lines where `schd_date < CAST(GETDATE() AS DATE)`.
  - `Week 1`–`Week 8`  buckets based on `DATEDIFF(WEEK, GETDATE(), schd_date)`.
  - `Long Term`  `DATEDIFF(WEEK, GETDATE(), schd_date) >= 9`.

- **Demand aggregation**
  - For each item:
    - `Total Past Due`, `Week 1`..`Week 8`, `Total Long Term` are **sums of discrete schedule quantity** per bucket.

- **Inventory and coverage (item-level)**
  - Inventory source: `[QADEE2798].[dbo].[15]`.
  - `MRP Qty` = `in_qty_oh` (nettable on-hand).
  - `Non Nettable` = `in_qty_nonet`.
  - `Total Inv` = `in_qty_oh + in_qty_nonet`.
  - `NN %` = `Non Nettable * 100 / Total Inv` (0 when `Total Inv = 0`).
  - **Coverage bucket** is chosen by comparing `MRP Qty` with the cumulative demand across buckets in chronological order, returning the *first* bucket where inventory is insufficient (or `Total Long Term` if demand always exceeds inventory).

- **Pure demand vs inventory for parents (Customer_Demand)**
  - `ParentPureDemand` CTE subtracts `MRP Qty` from cumulative parent demand bucket-by-bucket.
  - Result is **never negative** (lower bound 0 in each bucket).

- **Demand explosion to components (Customer_Demand)**
  - Uses BOM hierarchy (`ps_mstr`) to propagate **pure parent demand** down to component demand by multiplying by `ps_qty_per`.
  - Component demand is then unioned with parent demand in `CombinedData`.

- **Demand explosion to components (Customer_Demand_per_BOM)**
  - Works over QADEE2798 (single-plant).
  - Buckets into `Past_Due`, `Current_Week`, `Week_1`..`Week_8`, `Future_Demand` by comparing schedule week/year with a `WeekReference` CTE (anchored on `GETDATE()`).
  - Filters out cancelled / inactive orders and BOM components that are null.

---

## 3. BOM domain

**Canonical query**

- `BOM_exploded` (canonical: `Querries/BOM_exploded.sql`).

**Key business rules**

- Source: `[QADEE2798].[dbo].[ps_mstr]` with `ps_end IS NULL`.
- `Plant` is fixed at `'2798'` (single-plant BOM in canonical version).
- **SFG vs RM identification**
  - SFG (`Structure_Type = 'SFG'`) when a component also appears as a `ps_par` somewhere else in the BOM.
  - Otherwise the structure type is `NULL` or treated as RM in filtered outputs.
- **Recursive traversal**
  - Recursive CTE `BOMHierarchy` walks from root parents down through components.
  - Maximum depth `LEVEL < 10` to avoid runaway recursion.
- **Output fields** (canonical BOM exploded view)
  - `Parent_Item` (root_parent)
  - `ps_par` (current parent on this level)
  - `ps_comp` (component)
  - `Quantity_Per` (ps_qty_per)
  - `ps_rmks`, `ps_op`, `Structure_Type`.

**Specialized BOM variants (not canonical but valid)**

- `MRP/BOM_exploded.sql`:
  - Restricts `root_parent` to **customer items** (from `sod_det`).
  - Filters to rows with `Structure_Type = 'RM'` (raw materials only).
  - Used as a more focused BOM for customer-driven RM requirements.

---

## 4. Item Master & Inventory domain

**Canonical queries**

- `Item_Master` (canonical: `Querries/Item_Master.sql`).
- `Item_Master_all_no_xc_rc` (canonical: `Querries/Item_Master_all_no_xc_rc.sql`).
- `Item_Master_Inventory_2798` (canonical: `Querries/Item_Master_Inventory_2798.sql`).

### 4.1 Item_Master (enriched 2798 view)

- **Item source**: `[QADEE2798].[dbo].[pt_mstr]`.
- Excludes `pt_part_type` in `('xc','rc')` in some supporting queries.
- **Item fields** include type, description, prod line, group, status, ABC, safety stock, buyer, routing, net weight normalized to kg, design group, project.
- **Inventory**
  - From `[QADEE2798].[dbo].[15]` (same as demand inventory source).
  - `MRP Qty`, `Non Nettable`, `Total Inv`, `NN %` as in Demand logic.
- **Standard cost and cost breakdown** (from `[sct_det]`, `sct_sim = 'standard'`):
  - `Standard Cost`, `CMAT` (material share), `LBO` (labor/overhead share), `Prod/Mfg` classification (`RM` vs `SFG/FG`).
- **BOM-based classification**
  - Uses `ps_mstr` to classify items per BOM as `FG`, `SFG`, `RM`, or `No BOM`.
  - Rule of precedence: FG (root_parent) > SFG (intermediate parent) > RM (pure component).
- **Transaction history & obsolescence**
  - `Last Issue` and `Last Receipt` are merged from `tr_hist` (QADEE2798) across `iss-wo`, `iss-so`, `rct-wo`, `rct-po`.
  - Categories: `active`, `3 months`, `6 months`, `obsolete`, `No transactions` depending on age in days.
- **Derived checks (data quality / governance)**
  - `Item Type Check`  mismatch between BOM type and master data item type.
  - `Inventory Check`  marks items with zero inventory.
  - `Inventory_BOM Check`  inventory present but not in BOM (excluding `Prod Line = 'OBS'`).
  - `Routing Check`, `Project Check`, `Prod Line Check`, `Group Check`, `Planner Check (BOM)`, `Supplier/Customer Check (BOM)`  ensure required attributes for BOM items.
  - `Supplier Check (PO)`, `Planner Check (PO)`, `SDP Check`, `Weeks Check`, `Months Check`, `Firm Days Check`, `Transport Days Check`  PO-related consistency rules for RM items.
  - `Unused` (Unused/Obsolete) flag  item has no BOM, no inventory, not new, and both last issue/receipt are `obsolete` or `No transactions`.
  - Multiple cost-based COGS / CMAT aggregations (`MRP COGS`, `Total Inv Cogs`, etc.).

### 4.2 Item_Master_all_no_xc_rc (2798 only, no xc/rc)

- Uses QADEE2798 `pt_mstr`, excluding `pt_part_type IN ('xc','rc')`.
- Adds BOM, cost, inventory, WIP, and data-quality flags for plant 2798.
- **BOM status**
  - Determines whether an item is Parent, Child, and/or SFG from `ps_mstr`.
  - Derives `FG/SFG/RM` classification.
- **Inventory**
  - Pulls from `[QADEE2798].[dbo].[15]`, with Obsolete bucket logic (Active / 3 / 6 / 12 months / No transactions).
- **WIP minimum / maximum & overstock**
  - Uses last 4 weeks of `iss-wo` from `tr_hist` to compute weekly totals.
  - `WIP_minimum` ~ avg 4 weeks * 3.
  - `WIP_maximum` ~ avg 4 weeks * 7.
  - WIP overstock and value compare `WIP_Qty` vs [WIP_minimum, WIP_maximum].

### 4.3 Item_Master_Inventory_2798 (plant 2798 only)

- Same ideas as `Item_Master_all_no_xc_rc` but restricted to plant 2798.
- Adds per-area inventory (`WH`, `WIP`, `EXLPICK`) and WIP overstock logic with corrections for negative WIP.

---

## 5. Cost & obsolescence domain

- **Standard Cost / CMAT / LBO**
  - `Standard Cost` = `sct_cst_tot`.
  - `CMAT` = `sct_mtl_tl + sct_mtl_ll` (material-related cost).
  - `LBO` = `Standard Cost - CMAT`.
- **Obsolete definitions** (appear across Item Master & Demand)
  - Based on months or days since last issue/receipt, with breakpoints at 3, 6, 12 months.
  - Some queries restrict `tr_effdate` to > 365 days ago when building history, so **Item Master demand view is intentionally focused on older history for obsolescence**.

---

## 6. Sites & warehouse areas

- **Plant / site**
  - `2798`  main plant DB: `QADEE2798` (all queries now use this single source).

- **Warehouse areas (xxwezoned_area_id)**
  - `WH`  main warehouse.
  - `WH-FG`, `WH-FG-E`  finished goods sub-areas.
  - `WIP`  work-in-progress.
  - `EXLPICK`  external pick locations.

These areas are used in multiple queries for:

- Per-area quantities and COGS (e.g. `COGS_WH`, `COGS_WH_FG`, `COGS_WIP`, etc.).
- WIP min/max and overstock calculations.

---

## 7. Canonical vs legacy mapping (so far)

- **Exact duplicates**
  - `MRP/Item_Master_all_no_xc_rc.sql` and `Querries/Item_Master_all_no_xc_rc.sql` are text-identical.
  - Canonical: `Querries/Item_Master_all_no_xc_rc.sql`.

- **Updated vs older variants**
  - `Querries/Item_Master_Inventory_2798.sql` is the latest/enriched version.
  - `Item_Master_Inventory_2798.sql` (root) is treated as **legacy**.

- **Different-but-related views** (kept side-by-side)
  - `MRP/Customer_Demand.sql` vs `Querries/Customer_Demand.sql`  different outputs (SO/ship-to vs item-level coverage).
  - `MRP/BOM_exploded.sql` vs `Querries/BOM_exploded.sql`  RM-only customer-BOM vs full BOM tree.

When adding new queries or refactoring, **add them to `new querries/` only when they should become canonical**.

---

## 8. Diagrams

See `graphs.md` in this folder for mermaid diagrams showing:
- Data source & domain dependencies
- Canonical vs legacy query mapping
- Domain hierarchy
- Query execution flow

---

## 9. Warning Columns & Filter Criteria

These warning columns are used for inventory governance and exception reporting. They enable automated filtering in Excel reports.

### 9.1 Item Master Warning Columns

| Column | Definition | Filter Use |
|--------|------------|------------|
| `[New]` | `DATEDIFF(DAY, pt_added, GETDATE()) < 30` → 'New', else NULL | Recently added items |
| `[Inventory Check]` | `Total Inv <> 0` → 'Yes', else 'No' | Items with/without inventory |
| `[No Cost - in BOM]` | `Standard Cost = 0` AND `FG/SFG/RM <> 'No BOM'` → 'Yes' | Zero-cost items in BOM |
| `[No Prod Line - in BOM]` | `Prod Line = '0000'` AND `FG/SFG/RM <> 'No BOM'` → 'Yes' | Missing prod line |
| `[No Group - in BOM]` | `Group = 'F000'` AND `FG/SFG/RM <> 'No BOM'` → 'Yes' | Missing group |
| `[EPIC- in BOM]` | `Item Number Status = 'EPIC'` AND `FG/SFG/RM <> 'No BOM'` → 'Yes' | EPIC items in BOM |
| `[Routing Missing]` | `Routing IS NULL` AND `FG/SFG/RM <> 'No BOM'` → 'Yes' | Missing routing |
| `[Project missing]` | `Project IS NULL` AND `FG/SFG/RM <> 'No BOM'` → 'Yes' | Missing project |
| `[Cycle Count Due]` | `pt_cyc_int - Last_CC < 5` → 'Yes' | Due for cycle count |
| `[Slow-moving Warning]` | `90 < Last_ISSUE < 180` → 'Yes' | Items with limited activity |
| `[Item Type Error]` | `Item Type <> FG/SFG/RM` → 'Yes' | Type mismatch |
| `[Operation check]` | Item has multiple operations but is in single plant → 'Yes' | Operation discrepancy |

### 9.2 WIP Analysis Columns

| Column | Calculation | Purpose |
|--------|-------------|---------|
| `[WIP_minimum]` | `AVG(last 4 weeks ISS-WO) × 3` | Minimum WIP inventory level |
| `[WIP_maximum]` | `AVG(last 4 weeks ISS-WO) × 7` | Maximum WIP inventory level |
| `[WIP_overstock]` | If `WIP_Qty > WIP_maximum`: `WIP_Qty - WIP_maximum`<br>If `WIP_Qty < WIP_minimum`: `WIP_Qty - WIP_minimum`<br>Else: NULL | Quantity outside optimal range |
| `[WIP_overstock_Value]` | `WIP_overstock × Standard Cost` | Financial impact |
| `[avg_ISS-WO_CW_-1]` to `[-4]` | Average daily ISS-WO for each of past 4 weeks | Trend data |

### 9.3 Demand Analysis Columns

| Column | Calculation | Purpose |
|--------|-------------|---------|
| `[Daily_Average]` | `(Week_1 + Week_2 + Week_3 + Week_4) / 20` | Average daily demand (20 work days) |
| `[Min_Stock]` | `Daily_Average × 5` | 5-day stock coverage |
| `[Max_Stock]` | `Daily_Average × 15` | 15-day stock coverage |

### 9.4 Filter Sheet Definitions (for Excel Reports)

1. **Non-Active Items** - `Obsolete <> 'Active'`
2. **Cycle Count Due** - `Cycle Count Due = 'Yes'`
3. **Issue 80-90 Days** - `80 < Last_ISSUE < 90`
4. **FG-SFG Operation Check** - `FG/SFG/RM IN ('FG','SFG')` AND `Operation NOT IN (30, 999)`
5. **Empty Project** - `Project missing = 'Yes'`
6. **Type Mismatch** - `Item Type Error = 'Yes'`
7. **Recently Added** - `New IS NOT NULL`
8. **0000-F000** - `No Prod Line - in BOM = 'Yes'` OR `No Group - in BOM = 'Yes'`
9. **No BOM Items** - `FG/SFG/RM = 'No BOM'`
10. **WIP_overstock** - `WIP_overstock IS NOT NULL`
11. **No Cost Items** - `No Cost - in BOM = 'Yes'`
12. **EPIC Items** - `EPIC- in BOM = 'Yes'`
13. **Routing Missing** - `Routing Missing = 'Yes'`
14. **Slow-moving Warning** - `Slow-moving Warning = 'Yes'`

---

## 10. How to extend this document

- When we analyze additional queries (Inventory, Transactions, WIP, Serials, PO/SO):
  - Add a new section per domain summarizing business rules.
  - Add canonical entrypoints under `new querries/` and extend the mermaid graphs.
- Always reflect the rule: **newer, agreed canonical queries override older logic** when definitions conflict.

---

## 11. Change Log

| Date | Change | Details |
|------|--------|--------|
| 2024-11-30 | Warning columns documented | Added Section 9 with filter criteria from SQL_queries_old project |
| 2024-11-30 | Integrated SQL_queries_old | Analyzed old project, integrated documentation, created 2798-only versions |
| 2024-11-29 | QADEE (2674) removed | All queries now use QADEE2798 only. Multi-plant logic removed. |
| 2024-11-29 | Initial canonicalization | Created `new querries/` structure with Demand, BOM, Item_Master domains. |
| 2024-11-29 | Documentation created | `business_logic_rules.md`, `graphs.md`, `canonical_index.md`, `README.md`. |
