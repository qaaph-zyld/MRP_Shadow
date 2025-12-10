SQL_queries\Item_Master.sql

1) column [New] - we need to change how values are calculated
the first query should contain [pt_added] column and column [New] - if today()-pt_added < 30, the value being New, else null and then you merge the two queries

2) column [Inventory Check] - if [Total Inv] <> 0, then "Yes", else "No"; if [Item both plants] 

3) column [No Cost - in BOM] - if [Standard Cost] = 0 and [FG/SFG/RM] <>"No BOM" then "Yes", else null

4) column [No Prod Line - in BOM] - if [Prod Line] = "0000" and [FG/SFG/RM] <>"No BOM" then "Yes", else null

5) column [No Group - in BOM] - if [Group] = "F000" and [FG/SFG/RM] <>"No BOM" then "Yes", else null

6) column [EPIC- in BOM] - if [Item Number Status] = "EPIC" and [FG/SFG/RM] <>"No BOM" then "Yes", else null

7) column [ABC] - if [Group] ='LTH KIT' or [FG/SFG/RM] in ('SFG","FG") then "A", else if [Group] = ("COMP") then "B", else if [Group] in ("Thread","Rolls"] then

8) column [Routing Missing] - if [Routing] = null and [FG/SFG/RM] <>"No BOM" then "Yes" else null

9) column [Project missing] - if [Project] = null and [FG/SFG/RM] <>"No BOM" then "Yes" else null

10) column [Operation check] - if count of [Item Number] > 1 and [Item both Plants] is null, then "Yes" else null

11) column [Cycle Count Due] - if pt_cyc_int - Last_CC <5 then "Yes" else null

12) column [Slow-moving Warning] - if 90<Last_ISSUE<180 then "Yes" else null

13) column [Item Type Error] - if Item Type <> [FG/SFG/RM] then "Yes" else null


SQL_queries\Item_Master_WIP_minimum.sql

14) column [WIP_maximum] - calculated as 7x the average of the last 4 weeks of ISS-WO transactions

15) column [WIP_overstock] - if [WIP_Qty] > [WIP_maximum], calculate [WIP_Qty] - [WIP_maximum]; if [WIP_Qty] < [WIP_minimum], calculate [WIP_Qty] - [WIP_minimum]; otherwise null.

16) column [WIP_overstock_Value] - calculated as [Standard Cost] * [WIP_overstock], or 0 if [WIP_overstock] is null
