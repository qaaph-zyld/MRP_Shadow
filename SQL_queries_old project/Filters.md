*create sheets for each of the filters below (within inventory_report); filter Item Numbers based on these filters, with the columns included in each sheet, as listed below.

Filters:

Non-Active Items: if [Obsolete] <> Active
Cycle Count Due: if [Cycle Count Due] = "Yes" (pt_cyc_int - Last_CC <5)
Issue 80-90 Days: if 90 > Last_ISSUE > 80
FG-SFG Operation Check: if [Operation check] = "Yes" ([FG/SFG/RM]="FG" or "SFG" and [Operation] <>(30 or 999))
Empty Project: if [Project missing] = "Yes" (project is "" and [FG/SFG/RM] <> "No BOM")
Type Mismatch: if [Item Type Error] = "Yes" (Item Type <> [FG/SFG/RM])
Recently Added: if [New] is not null (today-[Date added]<30)
0000-F000: if [No Prod Line - in BOM] = "Yes" or [No Group - in BOM] = "Yes" (prod line is 0000 or Group is F000)
No BOM Items: if [FG/SFG/RM] = "No BOM"
WIP_overstock: if [WIP_overstock] is not null (WIP inventory is either above maximum or below minimum threshold)
No Cost Items: if [No Cost - in BOM] = "Yes" (Standard Cost = 0 and item is in BOM)
EPIC Items: if [EPIC- in BOM] = "Yes" (Item Number Status = "EPIC" and item is in BOM)
Routing Missing: if [Routing Missing] = "Yes" (Routing is null and item is in BOM)
Slow-moving Warning: if [Slow-moving Warning] = "Yes" (90 < Last_ISSUE < 180)

columns included in each sheet:

Plant
Item Number
Standard Cost
Material Cost
LBO
Item Description
pt_desc2
Prod Line
Group
pt_part_type
Item Number Status
Date added
ABC
pt_cyc_int
Safety Stock
Safety Time
Item Planner
Item Supplier
Routing
Net weight
pt_net_wt_um
Item Type
Project
FG/SFG/RM
Operation
Total Qty Nettable
Total Qty Nonet
Total Inv
Last_ISSUE
Last_REC
Last_CC
Obsolete
Total CMAT
Total COGS
New
WH_Qty
WIP_Qty
EXLPICK_Qty
WH_Value
WIP_Value
EXLPICK_Value
WIP_minimum
WIP_maximum
WIP_overstock
WIP_overstock_Value
avg_ISS-WO_CW_-1
avg_ISS-WO_CW_-2
avg_ISS-WO_CW_-3
avg_ISS-WO_CW_-4

# Inventory Report Filtering System

## Implementation Details

The inventory report now includes multiple sheets, each containing data filtered according to specific criteria. This allows for easier analysis of different inventory categories and potential issues. The report is generated using data from the SQL query in `SQL_queries\Item_Master_WIP_minimum.sql`.

### Available Filters

The inventory report includes the following sheets:

1. **Main Report** - Contains all inventory data without filtering
2. **Non-Active Items** - Items where [Obsolete] is not "Active"
3. **Cycle Count Due** - Items where [Cycle Count Due] is "Yes" (pt_cyc_int - Last_CC < 5)
4. **Issue 80-90 Days** - Items where Last_ISSUE is between 80 and 90 days
5. **FG-SFG Operation Check** - Items where [Operation check] is "Yes"
6. **Empty Project** - Items where [Project missing] is "Yes" (project is empty and [FG/SFG/RM] is not "No BOM")
7. **Type Mismatch** - Items where [Item Type Error] is "Yes" (Item Type doesn't match [FG/SFG/RM])
8. **Recently Added** - Items where [New] is not null (added less than 30 days ago)
9. **0000-F000** - Items where [No Prod Line - in BOM] is "Yes" or [No Group - in BOM] is "Yes"
10. **No BOM Items** - Items where [FG/SFG/RM] is "No BOM"
11. **WIP_overstock** - Items where [WIP_overstock] is not null (WIP inventory is either above maximum or below minimum threshold)
12. **No Cost Items** - Items where [No Cost - in BOM] is "Yes" (Standard Cost = 0 and item is in BOM)
13. **EPIC Items** - Items where [EPIC- in BOM] is "Yes" (Item Number Status = "EPIC" and item is in BOM)
14. **Routing Missing** - Items where [Routing Missing] is "Yes" (Routing is null and item is in BOM)
15. **Slow-moving Warning** - Items where [Slow-moving Warning] is "Yes" (90 < Last_ISSUE < 180)

Each filtered sheet contains only the columns specified in the "columns included in each sheet" section above, while the Main Report retains all columns from the original data.

### Warning Columns and Related Filters

The SQL query includes several warning columns that directly correspond to specific filters:

| Warning Column | Description | Related Filter |
|----------------|-------------|---------------|
| [Cycle Count Due] | Items due for cycle count | Filter #3 |
| [Project missing] | Items missing project information | Filter #6 |
| [Item Type Error] | Items with type mismatch | Filter #7 |
| [New] | Recently added items | Filter #8 |
| [No Prod Line - in BOM] | Items with missing product line | Filter #9 |
| [No Group - in BOM] | Items with missing group | Filter #9 |
| [No Cost - in BOM] | Items with zero standard cost | Filter #12 |
| [EPIC- in BOM] | Items with EPIC status | Filter #13 |
| [Routing Missing] | Items missing routing information | Filter #14 |
| [Slow-moving Warning] | Items with limited recent activity | Filter #15 |
| [WIP_overstock] | Items with WIP inventory outside optimal range | Filter #11 |

### WIP Analysis Columns

The following columns have been added to enhance WIP inventory analysis:

1. **WIP_minimum** - Minimum recommended WIP inventory level (3× average of last 4 weeks of ISS-WO transactions)
2. **WIP_maximum** - Maximum recommended WIP inventory level (7× average of last 4 weeks of ISS-WO transactions)
3. **WIP_overstock** - Quantity of inventory outside optimal range (above maximum or below minimum)
4. **WIP_overstock_Value** - Financial impact of inventory outside optimal range (Standard Cost × WIP_overstock)
5. **avg_ISS-WO_CW_-1 to -4** - Average daily ISS-WO transactions for each of the past 4 weeks

### Usage

The filtering system is automatically applied when running the Inventory_daily_report.py script. All filtered views are included in a single Excel file with multiple sheets.

```bash
python Inventory_daily_report.py
```

No additional parameters are required to use the filtering functionality.

### Error Handling

The filtering system includes robust error handling to ensure that if any filter cannot be applied (due to missing columns or data format issues), the report generation will continue with the available filters.

### Future Enhancements

Potential future enhancements could include:
- Configurable filter criteria through the config.ini file
- Additional filters based on other inventory metrics
- Custom filter combinations defined by users
- Automated scheduling of report generation
- Email notifications for critical inventory issues
