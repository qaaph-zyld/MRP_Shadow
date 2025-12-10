# Canonical Query Index

Quick reference table for canonical queries. Use this to find the right query for a given business need.

---

## Index

| Domain | Canonical Name | Entrypoint (`new querries/`) | Implementation | Supersedes / Notes |
|--------|---------------|------------------------------|----------------|-------------------|
| **Demand** | Customer_Demand | `Demand/Customer_Demand.sql` | `Querries/Customer_Demand.sql` | Item-level demand with coverage analysis. QAD: 7.5.1-7.5.5 |
| **Demand** | Customer_Demand_per_BOM | `Demand/Customer_Demand_per_BOM.sql` | `Querries/Customer_Demand_per_BOM.sql` | Component-level weekly demand. |
| **Demand** | Customer_Demand_per_week | `Demand/Customer_Demand_per_week.sql` | `Querries/Customer_Demand_per_week.sql` | Demand aggregated by week. |
| **Demand** | Customer_Demand_total | `Demand/Customer_Demand_total.sql` | `Querries/Customer_Demand_total.sql` | Total demand summary. |
| **BOM** | BOM_exploded | `BOM/BOM_exploded.sql` | `Querries/BOM_exploded.sql` | Full BOM hierarchy. MRP version filters to customer items + RM only. |
| **Item Master** | Item_Master | `Item_Master/Item_Master.sql` | `Querries/Item_Master.sql` | Enriched 2798 item master with demand, PO, BOM classification, checks. Root version is legacy. |
| **Item Master** | Item_Master_all_no_xc_rc | `Item_Master/Item_Master_all_no_xc_rc.sql` | `Querries/Item_Master_all_no_xc_rc.sql` | 2798-only item master excluding xc/rc. MRP copy synced. |
| **Item Master** | Item_Master_Inventory_2798 | `Item_Master/Item_Master_Inventory_2798.sql` | `Querries/Item_Master_Inventory_2798.sql` | 2798 item master with WIP min/max, overstock. Root version is legacy. |
| **Item Master** | Item_Master_RM | `Item_Master/Item_Master_RM.sql` | `Querries/Item_Master_RM.sql` | Raw Materials only item master. |
| **Inventory** | Inventory_per_location | `Inventory/Inventory_per_location.sql` | `Querries/Inventory_per_location.sql` | Inventory by location with area breakdown. |
| **Inventory** | Inventory_per_location_Parameters | `Inventory/Inventory_per_location_Parameters.sql` | `Querries/Inventory_per_location_Parameters.sql` | Parameterized inventory by location. |
| **Inventory** | Inventory_Area_COGS | `Inventory/Inventory_Area_COGS.sql` | `Querries/Inventory_Area_COGS.sql` | COGS by warehouse area. |
| **Inventory** | Inventory_obsolete_CC_received | `Inventory/Inventory_obsolete_CC_received.sql` | `Querries/Inventory_obsolete_CC_received.sql` | Obsolete inventory with CC received. |
| **Inventory** | True_Obsolete | `Inventory/True_Obsolete.sql` | `Querries/True_Obsolete.sql` | Obsolescence based on transaction inactivity. |
| **Inventory** | Inventory_per_Project | `Inventory/Inventory_per_Project.sql` | `Querries/Inventory_per_Project.sql` | Inventory grouped by project with WIP metrics. |
| **Transactions** | TRANSACTION_MASTER | `Transactions/TRANSACTION_MASTER.sql` | `Querries/TRANSACTION_MASTER.sql` | Master transaction view. |
| **Transactions** | Transaction_per_week_per_month | `Transactions/Transaction_per_week_per_month.sql` | `Querries/Transaction_per_week_per_month_per_item.sql` | Transactions bucketed by week/month. |
| **Transactions** | CC_transactions | `Transactions/CC_transactions.sql` | `Querries/CC_transactions.sql` | Cycle count transactions. |
| **Transactions** | ISS-SO_per_week | `Transactions/ISS-SO_per_week.sql` | `Querries/ISS-SO_per_week.sql` | Issue to SO by week. |
| **Transactions** | RCT-PO_per_week | `Transactions/RCT-PO_per_week.sql` | `Querries/RCT-PO_per_week.sql` | Receipt from PO by week. |
| **Transactions** | RCT-WO_per_week | `Transactions/RCT-WO_per_week.sql` | `Querries/RCT-WO_per_week.sql` | Receipt from WO by week. |
| **Transactions** | List_of_Shipments | `Transactions/List_of_Shipments.sql` | `Querries/List of Shippments.sql` | ISS-SO shipment list. QAD: 7.9.x |
| **WIP** | ISS-WO_WIP_Minimum | `WIP/ISS-WO_WIP_Minimum.sql` | `Querries/ISS-WO_WIP_Minimum.sql` | WIP minimum calculation. |
| **WIP** | wip_min_max | `WIP/wip_min_max.sql` | `Querries/wip_min_max.sql` | WIP min/max levels. |
| **WIP** | Production_Efficiency_Report | `WIP/Production_Efficiency_Report.sql` | `Querries/Production_Efficiency_Report.sql` | Production efficiency metrics. |
| **WIP** | Production_per_hour_IT | `WIP/Production_per_hour_IT.sql` | `Querries/Production_per_hour_IT.sql` | Production per hour by project and time bucket. |
| **WIP** | Production_Efficiency_Current_Month | `WIP/Production_Efficiency_Current_Month.sql` | `Querries/Production_Efficiency_Report_Current_Month.sql` | Current month production efficiency. |
| **WIP** | WIP_overstock | `WIP/WIP_overstock.sql` | `Querries/WIP_overstock.sql` | Items with WIP outside min/max optimal range. |
| **Serials** | Serial_history_Item_Master | `Serials/Serial_history_Item_Master.sql` | `Querries/Serial_history_Item_Master.sql` | Serial history with item master. |
| **Serials** | Serials_CC_status | `Serials/Serials_CC_status.sql` | `Querries/Serials_CC_status.sql` | Serial CC status. |
| **Serials** | Serials_Packaging_Warehouse | `Serials/Serials_Packaging_Warehouse.sql` | `Querries/Serials_Packaging_Warehouse.sql` | Serials in packaging warehouse. |
| **Serials** | serials_tcis_data | `Serials/serials_tcis_data.sql` | `Querries/serials_tcis_data.sql` | Serials enriched with TCIS MES data. |
| **PO/SO** | PO | `PO_SO/PO.sql` | `Querries/PO.sql` | Purchase orders with checks. |
| **PO/SO** | PO_lite | `PO_SO/PO_lite.sql` | `Querries/PO_lite.sql` | Simplified PO view. |
| **PO/SO** | SO | `PO_SO/SO.sql` | `Querries/SO.sql` | Sales orders. |
| **PO/SO** | SO_lite | `PO_SO/SO_lite.sql` | `Querries/SO_lite.sql` | Simplified SO view. |
| **PO/SO** | PO_SO | `PO_SO/PO_SO.sql` | `Querries/PO_SO.sql` | Combined PO and SO view. |
| **PO/SO** | SO_per_week | `PO_SO/SO_per_week.sql` | `Querries/SO_per_week.sql` | SO by week. |
| **PO/SO** | PO_Packaging_Tracker | `PO_SO/PO_Packaging_Tracker.sql` | `Querries/PO_Packaging_Tracker.sql` | PO packaging tracking. |

---

## Legacy / Deprecated Files

### Root-level legacy (superseded by Querries versions)
- `Item_Master.sql` → use `Querries/Item_Master.sql`
- `Item_Master_Inventory_2798.sql` → use `Querries/Item_Master_Inventory_2798.sql`
- `Item_Master_2798.sql` → use `Querries/Item_Master_Inventory_2798.sql`
- `Item_Master_Browse.sql` → legacy browser view

> **Note:** 2674-specific files have been deleted (were in `archive_2674/`).

---

## How to Add New Canonical Queries

1. **Implement** the query in `Querries/` (or improve an existing one).
2. **Create wrapper** in `new querries/<Domain>/` with:
   ```sql
   -- Description of canonical query
   -- Source: Querries/<filename>.sql
   :r ..\..\Querries\<filename>.sql
   ```
3. **Update this index** with the new entry.
4. **Update `business_logic_rules.md`** if new business rules are introduced.
5. **Update `graphs.md`** if the query adds new data flows.

---

## Change Log

| Date | Query/Domain | Change | Reason |
|------|--------------|--------|--------|
| 2024-11-30 | SQL_queries_old integration | Analyzed old project, integrated docs, created 2798-only versions |
| 2024-11-30 | Inventory | Created `Inventory_per_Project.sql` (2798 only) | Project-based inventory analysis from old project |
| 2024-11-30 | WIP | Created `WIP_overstock.sql` (2798 only) | WIP min/max overstock analysis from old project |
| 2024-11-30 | Documentation | Created `qad_mapping.md` | Map SQL queries to QAD menu numbers from training docs |
| 2024-11-30 | Demand | Added `Customer_Demand_per_week`, `Customer_Demand_total` wrappers | Canonicalize existing queries |
| 2024-11-30 | Transactions | Added `List_of_Shipments` wrapper | Canonicalize shipment list query |
| 2024-11-30 | WIP | Added `Production_Efficiency_Current_Month` wrapper | Canonicalize current month efficiency |
| 2024-11-30 | Item Master | Added `Item_Master_RM` wrapper | Canonicalize RM-only item master |
| 2024-11-30 | PO/SO | Added `PO_Packaging_Tracker` wrapper | Canonicalize packaging tracker |
| 2024-11-29 | All | Removed QADEE (2674) references | Single-plant consolidation to QADEE2798 |
| 2024-11-29 | Documentation created | `business_logic_rules.md`, `graphs.md`, `canonical_index.md`, `README.md`. |
| 2024-11-29 | Full canonicalization | Added Inventory, Transactions, WIP, Serials, PO/SO domains. |
| 2024-11-29 | Cleanup | Removed duplicate UNION ALL blocks, deleted archive_2674 folder. |
| 2024-11-29 | Special queries canonicalized | Added True_Obsolete, Production_per_hour_IT, serials_tcis_data wrappers. |
