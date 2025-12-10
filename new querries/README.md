# New Querries - Canonical Entrypoints

> **IMPORTANT: Run in SQLCMD Mode**  
> These wrapper files use `:r` includes. In SSMS: Query → SQLCMD Mode (or Ctrl+Shift+M)

This folder centralizes the **canonical** SQL queries used for reporting, MRP analysis, inventory, and governance. Each file here is a *thin wrapper* that includes the real implementation from its source location.

> **Important:** Newer queries always have precedence. Whenever we choose between different implementations of the same concept, we point `new querries` at the newer/richer one and treat others as legacy or specialized.

---

## 1. Usage

1. Open the desired `.sql` file under `new querries/`.
2. Make sure **SQLCMD Mode** is enabled in SSMS (Query > SQLCMD Mode).
3. Run the script.
4. The file will use `:r` to include and execute the canonical implementation from `Querries/` (or another agreed folder).

Example:

- `new querries/Demand/Customer_Demand.sql` contains:

  - comments describing the canonical query
  - a single `:r ..\..\Querries\Customer_Demand.sql` line

---

## 2. Current canonical entrypoints

### Demand
- `Demand/Customer_Demand.sql` - Item-level demand with coverage analysis (QAD: 7.5.1-7.5.5)
- `Demand/Customer_Demand_per_BOM.sql` - Component-level weekly demand buckets
- `Demand/Customer_Demand_per_week.sql` - Demand aggregated by week
- `Demand/Customer_Demand_total.sql` - Total demand summary

### BOM
- `BOM/BOM_exploded.sql` - Full BOM hierarchy for plant 2798

### Item Master
- `Item_Master/Item_Master.sql` - Enriched item master with BOM, PO, costs
- `Item_Master/Item_Master_all_no_xc_rc.sql` - Item master excluding xc/rc
- `Item_Master/Item_Master_Inventory_2798.sql` - Item master with WIP min/max
- `Item_Master/Item_Master_RM.sql` - Raw Materials only item master

### Inventory
- `Inventory/Inventory_per_location.sql` - Inventory by location
- `Inventory/Inventory_per_location_Parameters.sql` - Parameterized inventory
- `Inventory/Inventory_Area_COGS.sql` - COGS by warehouse area
- `Inventory/Inventory_obsolete_CC_received.sql` - Obsolete with CC
- `Inventory/True_Obsolete.sql` - Obsolescence classification by last transactions
- `Inventory/Inventory_per_Project.sql` - Inventory grouped by project with WIP metrics

### Transactions
- `Transactions/TRANSACTION_MASTER.sql` - Master transaction view (QAD: 3.21.2)
- `Transactions/Transaction_per_week_per_month.sql` - Weekly/monthly buckets
- `Transactions/CC_transactions.sql` - Cycle count transactions
- `Transactions/ISS-SO_per_week.sql` - Issue to SO by week (QAD: 7.9.x)
- `Transactions/RCT-PO_per_week.sql` - Receipt from PO by week (QAD: 5.5.5.x)
- `Transactions/RCT-WO_per_week.sql` - Receipt from WO by week (QAD: 18.22.13)
- `Transactions/List_of_Shipments.sql` - ISS-SO shipment list

### WIP
- `WIP/ISS-WO_WIP_Minimum.sql` - WIP minimum calculation
- `WIP/wip_min_max.sql` - WIP min/max levels
- `WIP/Production_Efficiency_Report.sql` - Production efficiency
- `WIP/Production_per_hour_IT.sql` - Production per hour by project
- `WIP/Production_Efficiency_Current_Month.sql` - Current month production efficiency
- `WIP/WIP_overstock.sql` - Items with WIP outside min/max optimal range

### Serials
- `Serials/Serial_history_Item_Master.sql` - Serial history with item master
- `Serials/Serials_CC_status.sql` - Serial CC status
- `Serials/Serials_Packaging_Warehouse.sql` - Serials in packaging
- `Serials/serials_tcis_data.sql` - Serials with TCIS MES integration

### PO/SO
- `PO_SO/PO.sql` - Purchase orders with checks
- `PO_SO/PO_lite.sql` - Simplified PO view
- `PO_SO/SO.sql` - Sales orders
- `PO_SO/SO_lite.sql` - Simplified SO view
- `PO_SO/PO_SO.sql` - Combined PO and SO
- `PO_SO/SO_per_week.sql` - SO by week
- `PO_SO/PO_Packaging_Tracker.sql` - PO packaging tracking

For details of the underlying business rules, see:

- `new querries/docs/business_logic_rules.md`
- `new querries/docs/qad_mapping.md` - Maps SQL queries to QAD menu numbers
- `new querries/docs/canonical_index.md` - Full index of all canonical queries

---

## 3. Adding new canonical queries

When you create or upgrade a query and want it to become canonical:

1. Put the **implementation** under an appropriate folder (typically `Querries/`).
2. Create a new wrapper under `new querries/` (possibly inside a new domain subfolder), containing:

   - A short header comment describing the query.
   - A `:r` reference to the implementation file (relative path from the wrapper).

3. Update `business_logic_rules.md` and, if needed, the mermaid diagrams to document:

   - The new business rules.
   - Any legacy queries that this new one supersedes.

This keeps `new querries/` as a stable, curated set of entrypoints while allowing underlying implementations to evolve.
