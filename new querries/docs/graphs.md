# Query & Data Flow Diagrams

This document contains mermaid diagrams that visualize the data sources, query dependencies, and canonical vs legacy query mappings.

---

## 1. Data Source & Domain Dependencies

Shows how QADEE2798 database feeds the canonical queries across different domains.

```mermaid
graph TD
    subgraph "QADEE2798 Database"
        PT[pt_mstr<br/>Item Master]
        PS[ps_mstr<br/>BOM Structure]
        SOD[sod_det<br/>Sales Order Detail]
        SCH[sch_mstr + active_schd_det<br/>Schedules]
        LD[ld_det<br/>Location Detail]
        XZ[xxwezoned_det<br/>Warehouse Zones]
        INV[15 / in_mstr<br/>Inventory]
        SCT[sct_det<br/>Standard Cost]
        TR[tr_hist<br/>Transaction History]
        PO[pod_det + po_mstr<br/>Purchase Orders]
        SO[so_mstr<br/>Sales Orders]
        SER[ser_active_picked<br/>Serials]
    end

    subgraph "Canonical Queries"
        CD[Customer_Demand]
        CDBOM[Customer_Demand_per_BOM]
        BOMX[BOM_exploded]
        IM[Item_Master]
        IMALL[Item_Master_all_no_xc_rc]
        IMINV[Item_Master_Inventory_2798]
    end

    PT --> IM
    PT --> IMALL
    PT --> IMINV
    PS --> BOMX
    PS --> IM
    PS --> IMALL
    SOD --> CD
    SOD --> CDBOM
    SCH --> CD
    SCH --> CDBOM
    LD --> IM
    LD --> IMALL
    LD --> IMINV
    XZ --> IM
    XZ --> IMALL
    XZ --> IMINV
    INV --> CD
    INV --> IM
    INV --> IMALL
    INV --> IMINV
    SCT --> IM
    SCT --> IMALL
    SCT --> IMINV
    TR --> IM
    TR --> IMALL
    TR --> IMINV
    PO --> IM
    SO --> CDBOM
```

---

## 2. Canonical vs Legacy Query Mapping

Shows which queries are canonical (in `new querries/`) and which are legacy/specialized.

```mermaid
graph LR
    subgraph "new querries/ (Canonical Entrypoints)"
        NQ_CD[Demand/Customer_Demand.sql]
        NQ_CDBOM[Demand/Customer_Demand_per_BOM.sql]
        NQ_BOM[BOM/BOM_exploded.sql]
        NQ_IM[Item_Master/Item_Master.sql]
        NQ_IMALL[Item_Master/Item_Master_all_no_xc_rc.sql]
        NQ_IMINV[Item_Master/Item_Master_Inventory_2798.sql]
    end

    subgraph "Querries/ (Canonical Implementations)"
        Q_CD[Customer_Demand.sql]
        Q_CDBOM[Customer_Demand_per_BOM.sql]
        Q_BOM[BOM_exploded.sql]
        Q_IM[Item_Master.sql]
        Q_IMALL[Item_Master_all_no_xc_rc.sql]
        Q_IMINV[Item_Master_Inventory_2798.sql]
    end

    subgraph "MRP/ (Legacy/Specialized)"
        M_CD[Customer_Demand.sql]
        M_CDBOM[Customer_Demand_per_BOM.sql]
        M_BOM[BOM_exploded.sql]
        M_IMALL[Item_Master_all_no_xc_rc.sql]
    end

    subgraph "Root (Legacy)"
        R_IM[Item_Master.sql]
        R_IMINV[Item_Master_Inventory_2798.sql]
    end

    NQ_CD -->|:r| Q_CD
    NQ_CDBOM -->|:r| Q_CDBOM
    NQ_BOM -->|:r| Q_BOM
    NQ_IM -->|:r| Q_IM
    NQ_IMALL -->|:r| Q_IMALL
    NQ_IMINV -->|:r| Q_IMINV

    M_CD -.->|different view| Q_CD
    M_CDBOM -.->|RM-only| Q_CDBOM
    M_BOM -.->|customer items only| Q_BOM
    M_IMALL -.->|synced copy| Q_IMALL

    R_IM -.->|legacy| Q_IM
    R_IMINV -.->|legacy| Q_IMINV
```

---

## 3. Domain Hierarchy

Shows how the query domains relate to each other.

```mermaid
graph TB
    subgraph "Foundation Layer"
        BOM[BOM Domain<br/>Structure & Components]
        INV[Inventory Domain<br/>Quantities & Locations]
        COST[Cost Domain<br/>Standard Cost, CMAT, LBO]
    end

    subgraph "Analysis Layer"
        DEMAND[Demand Domain<br/>Customer Requirements]
        ITEM[Item Master Domain<br/>Part Attributes]
    end

    subgraph "Reporting Layer"
        COVERAGE[Coverage Analysis]
        OBSOL[Obsolescence Tracking]
        WIP[WIP Min/Max]
        CHECKS[Data Quality Checks]
    end

    BOM --> DEMAND
    BOM --> ITEM
    INV --> DEMAND
    INV --> ITEM
    COST --> ITEM

    DEMAND --> COVERAGE
    ITEM --> OBSOL
    ITEM --> WIP
    ITEM --> CHECKS
```

---

## 4. Query Execution Flow (Item Master example)

Shows the CTE flow within the canonical Item_Master query.

```mermaid
flowchart TD
    A[ItemMaster CTE<br/>Basic item attributes] --> M[MainResultSet]
    B[InventoryData CTE<br/>MRP Qty, Non-Nettable] --> M
    C[StandardCost CTE<br/>Cost breakdown] --> M
    D[BOMItems CTE<br/>FG/SFG/RM classification] --> M
    
    M --> F[FinalMainResultSet]
    E[TransactionHistory CTE<br/>Last Issue/Receipt] --> F
    G[PODetails CTE<br/>PO attributes] --> F
    
    F --> OUT[Final Output]
    H[COGSByArea CTE<br/>COGS per warehouse area] --> OUT
    I[DemandData CTE<br/>Weekly demand buckets] --> OUT
```

---

## Notes

- All diagrams use **QADEE2798** as the single data source (QADEE/2674 removed).
- Dashed lines indicate legacy or specialized relationships.
- Solid lines indicate canonical relationships.
- The `:r` notation indicates SQLCMD include directive.
