# QAD Menu to SQL Query Mapping

This document maps QAD EE menu numbers (from training documents) to canonical SQL queries.

---

## Customer Demand Management

| QAD Menu | Description | Canonical Query | Notes |
|----------|-------------|-----------------|-------|
| 7.5.1 | Customer Planning Schedule (Long Term) | `Demand/Customer_Demand.sql` | Long-term demand from `sod_det` |
| 7.5.2 | Customer Shipping Schedule (Short Term) | `Demand/Customer_Demand.sql` | Short-term demand |
| 7.5.3 | Required Ship Schedule Maintenance | `Demand/Customer_Demand.sql` | RSS data |
| 7.5.5 | Required Ship Schedule Update | `Demand/Customer_Demand.sql` | Combined schedule |
| 22.1 | Forecast Maintenance | — | No dedicated forecast query |
| 22.28 | Forecast Report | — | No dedicated forecast query |

---

## Inventory Management

| QAD Menu | Description | Canonical Query | Notes |
|----------|-------------|-----------------|-------|
| 3.6.6 | Inventory Detail by Location | `Inventory/Inventory_per_location.sql` | |
| 3.6.15 | Inventory Valuation as of Date | `Inventory/Inventory_Area_COGS.sql` | COGS by area |
| 3.6.16 | Inventory Valuation by Location | `Inventory/Inventory_per_location_Parameters.sql` | |
| 3.6.39 | Inventory Valuation as of Date | `Inventory/Inventory_per_location.sql` | |
| 75.7.2.12 | Inventory Detail by Item Browse | `Item_Master/Item_Master.sql` | Enriched item view |
| 1.15.40.12 | Inventory Detail Browse | `Inventory/Inventory_per_location.sql` | |
| 3.1.14 | Inventory Detail Browse by Item | `Item_Master/Item_Master.sql` | |

---

## Goods Receipt (RCT-PO)

| QAD Menu | Description | Canonical Query | Notes |
|----------|-------------|-----------------|-------|
| 5.5.5.5 | PO Shipper Maintenance | `Transactions/RCT-PO_per_week.sql` | Receipt transactions |
| 5.5.5.11 | PO Shipper Receipt | `Transactions/RCT-PO_per_week.sql` | |
| 5.5.5.16 | Schedule Receipt Browse | `Transactions/RCT-PO_per_week.sql` | |
| 5.5.6.1 | DMR Receipt | `Transactions/TRANSACTION_MASTER.sql` | DMR = RCT-PO with remarks |
| 3.21.2 | Transaction History | `Transactions/TRANSACTION_MASTER.sql` | |

---

## Shipping (ISS-SO)

| QAD Menu | Description | Canonical Query | Notes |
|----------|-------------|-----------------|-------|
| 7.9.1 | Picklist/Pre-Shipper Automatic | `Transactions/ISS-SO_per_week.sql` | |
| 7.9.2 | Pre-Shipper/Shipper Workbench | `Transactions/ISS-SO_per_week.sql` | |
| 7.9.5 | Pre-Shipper/Shipper Confirm | `Transactions/ISS-SO_per_week.sql` | |
| 7.9.16.1 | Shipment Check Report | `Transactions/ISS-SO_per_week.sql` | |
| 7.9.16.2 | Shipper Report | `Transactions/ISS-SO_per_week.sql` | |
| 35.4.1 | Shipment ASN Export | — | EDI export, no SQL equivalent |

---

## Production / Backflush (RCT-WO, ISS-WO)

| QAD Menu | Description | Canonical Query | Notes |
|----------|-------------|-----------------|-------|
| 18.22.13 | Manual Backflush | `Transactions/RCT-WO_per_week.sql` | RCT-WO transactions |
| 18.22.1.1 | Production Line Maintenance | `WIP/Production_Efficiency_Report.sql` | Production by line |
| 14.13.1 | Routing Maintenance | — | Setup only, no query |

---

## MRP / Materials Management

| QAD Menu | Description | Canonical Query | Notes |
|----------|-------------|-----------------|-------|
| 23.1 | Net Change Materials Plan | — | **GAP**: No MRP pegging query |
| 23.2 | Regenerate Materials Plan | — | **GAP** |
| 23.3 | Selective Materials Plan | — | **GAP** |
| 23.6 | Action Message Browse | — | **GAP**: No action message query |
| 23.7 | Action Message Report | — | **GAP** |
| 23.13 | MRP Summary Inquiry | — | **GAP** |
| 23.16 | MRP Detail Inquiry | — | **GAP** |
| 23.17 | MRP Detail Report | — | **GAP** |
| 23.18 | MRP Export | — | **GAP** |
| 96.3.5.3.21 | Days On Hand Browse | — | **GAP**: No DOH query |
| 3.6.24.1 | Expeditors Workbench | — | **GAP** |
| 3.6.24.2 | Days of Supply Report | — | **GAP**: No DOS query |

---

## Supplier Scheduling

| QAD Menu | Description | Canonical Query | Notes |
|----------|-------------|-----------------|-------|
| 5.5.3.1 | Schedule Update from MRP | — | **GAP**: No SA query |
| 5.5.3.3 | Schedule Maintenance | — | **GAP** |
| 5.5.3.4 | Schedule Inquiry | — | **GAP** |
| 5.5.3.10 | Multiple Part Release Print | — | **GAP** |
| 35.4.8 | Supplier Shipping Schedule Export | — | EDI export |
| 5.5.5.13 | Cumulative Received Maintenance | `PO_SO/PO.sql` | Cum data in PO |
| 5.5.5.14 | Cum Received Reset | — | Maintenance only |

---

## Schedule Analysis

| QAD Menu | Description | Canonical Query | Notes |
|----------|-------------|-----------------|-------|
| 7.5.7 | Customer & Supplier Diamond Report | — | **GAP**: No diamond query |
| 7.5.21.7 | Schedule Analysis Tool | — | **GAP** |
| 5.5.5.24.1 | Diamond Report | — | **GAP** |
| 7.5.21.24.8 | Cust Ship Schedule Variance Browse | — | **GAP** |
| 7.5.21.24.9 | Cust Plan Schedule Variance Browse | — | **GAP** |

---

## PO/SO Management

| QAD Menu | Description | Canonical Query | Notes |
|----------|-------------|-----------------|-------|
| 5.5.1.x | Purchase Order Maintenance | `PO_SO/PO.sql` | |
| 7.3.x | Sales Order Maintenance | `PO_SO/SO.sql` | |

---

## Summary of Gaps

### High Priority (Frequently Used)
1. **MRP Pegging / Days of Supply** - Core planning visibility
2. **Action Messages** - Expedite/De-expedite alerts

### Medium Priority
3. **Supplier Schedule (SA) Query** - `sa_det` table
4. **Schedule Variance / Diamond** - Release comparison

### Low Priority (Nice to Have)
5. **Forecast Query** - `fc_mstr` table
6. **DMR-specific View** - Filter TRANSACTION_MASTER for DMR remarks

---

## Change Log

| Date | Change |
|------|--------|
| 2024-11-30 | Initial creation based on QAD training documents analysis |
