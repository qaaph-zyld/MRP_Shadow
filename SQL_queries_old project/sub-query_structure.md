name: Inventory_per_Project.sql 
source query: SQL_queries\Item_Master_WIP_minimum.sql
Group by: Plant, Project, FG/SFG/RM, Prod line, Group, Item Number, Standard Cost, Material Cost, Item Description
SUM: WH_Qty, WIP_qty, EXLPICK_Qty, WH_Value, WIP_Value, EXLPICK_Value, Total COGS

name: WIP_overstock.sql 
source query: SQL_queries\Item_Master_WIP_minimum.sql
Group by: Plant, Project, FG/SFG/RM, Prod line, Group, Item Number, Standard Cost, Material Cost, Item Description
SUM: WH_Qty, WIP_qty, EXLPICK_Qty, WH_Value, WIP_Value, EXLPICK_Value, Total COGS
WHERE: WIP_overstock is not null    