<#
.SYNOPSIS
    Extract parameter mismatches for QAD cleanup.
    Step 1: Internal QAD inconsistencies (SD pattern, transport days, standard pack)
    Step 2: QAD vs IBT mismatches (SD pattern, transport days)

.DESCRIPTION
    - Queries QAD for current supplier parameters
    - Loads IBT.csv as master reference
    - Compares and generates mismatch reports ready for CIM file creation

.NOTES
    No SQL Server table creation required - all joins done in PowerShell.
#>

param(
    [string]$Server = "a265m001",
    [string]$Database = "QADEE2798",
    [string]$Username = "PowerBI",
    [string]$Password = "P0werB1",
    [string]$IBTPath = "C:\Users\ajelacn\OneDrive - Adient\Documents\SQL Server Management Studio\MRP\ShadowMRP\IBT.csv",
    [string]$OutputFolder = "C:\Users\ajelacn\OneDrive - Adient\Documents\SQL Server Management Studio\output"
)

# Ensure output folder exists
if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

# SQL connection helper function (uses credentials)
function Invoke-SqlQuery {
    param([string]$Query)
    
    Add-Type -AssemblyName System.Data
    $connString = "Server=$Server;Database=$Database;User ID=$Username;Password=$Password;Encrypt=False;TrustServerCertificate=True;"
    
    $conn = New-Object System.Data.SqlClient.SqlConnection $connString
    $conn.Open()
    
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $Query
    $cmd.CommandTimeout = 300
    
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $dataset = New-Object System.Data.DataSet
    [void]$adapter.Fill($dataset)
    
    $conn.Close()
    return $dataset.Tables[0]
}

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "   PARAMETER MISMATCH EXTRACTION" -ForegroundColor Cyan
Write-Host "   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

# ============================================================================
# STEP 1A: Extract QAD Supplier-Level Parameters (canonical per supplier)
# ============================================================================
Write-Host "STEP 1A: Extracting QAD supplier parameters..." -ForegroundColor Yellow

$sqlSupplierParams = @"
SET NOCOUNT ON;

DECLARE @CurrentDate DATE = CAST(GETDATE() AS DATE);

-- Get all active PO lines with their parameters
WITH ActivePOLines AS (
    SELECT 
        pod.pod_po_site AS Site,
        po.po_vend AS SupplierCode,
        ad.ad_name AS SupplierName,
        pod.pod_part AS ItemNumber,
        pod.pod_nbr AS PONumber,
        pod.pod_line AS POLine,
        pod.pod_translt_days AS TransportDays,
        pod.pod__chr01 AS SDPattern,
        pod.pod_ord_mult AS StandardPack
    FROM [QADEE2798].[dbo].[pod_det] pod WITH (NOLOCK)
    JOIN [QADEE2798].[dbo].[po_mstr] po WITH (NOLOCK) ON pod.pod_nbr = po.po_nbr
    LEFT JOIN [QADEE2798].[dbo].[ad_mstr] ad WITH (NOLOCK) ON po.po_vend = ad.ad_addr
    WHERE pod.pod_po_site = '2798'
      AND pod.pod_status IS NULL
      AND pod.[pod_end_eff[1]]] > @CurrentDate
),
-- Supplier-level aggregation: find canonical (modal) values
SupplierAgg AS (
    SELECT 
        Site,
        SupplierCode,
        MAX(SupplierName) AS SupplierName,
        COUNT(DISTINCT SDPattern) AS DistinctSDPatterns,
        COUNT(DISTINCT TransportDays) AS DistinctTransportDays,
        COUNT(*) AS ActivePOLineCount
    FROM ActivePOLines
    GROUP BY Site, SupplierCode
),
-- Find modal SD pattern per supplier
SDPatternModal AS (
    SELECT 
        Site, SupplierCode, SDPattern,
        ROW_NUMBER() OVER (PARTITION BY Site, SupplierCode ORDER BY COUNT(*) DESC) AS rn
    FROM ActivePOLines
    GROUP BY Site, SupplierCode, SDPattern
),
-- Find modal transport days per supplier
TransportDaysModal AS (
    SELECT 
        Site, SupplierCode, TransportDays,
        ROW_NUMBER() OVER (PARTITION BY Site, SupplierCode ORDER BY COUNT(*) DESC) AS rn
    FROM ActivePOLines
    GROUP BY Site, SupplierCode, TransportDays
)
SELECT 
    s.Site,
    s.SupplierCode,
    s.SupplierName,
    s.DistinctSDPatterns,
    s.DistinctTransportDays,
    s.ActivePOLineCount,
    sdm.SDPattern AS ModalSDPattern,
    tdm.TransportDays AS ModalTransportDays,
    CASE WHEN s.DistinctSDPatterns > 1 OR s.DistinctTransportDays > 1 THEN 'YES' ELSE 'NO' END AS HasInternalInconsistency
FROM SupplierAgg s
LEFT JOIN SDPatternModal sdm ON s.Site = sdm.Site AND s.SupplierCode = sdm.SupplierCode AND sdm.rn = 1
LEFT JOIN TransportDaysModal tdm ON s.Site = tdm.Site AND s.SupplierCode = tdm.SupplierCode AND tdm.rn = 1
ORDER BY s.SupplierCode;
"@

$qadSuppliers = Invoke-SqlQuery -Query $sqlSupplierParams
Write-Host "  Extracted $($qadSuppliers.Count) suppliers from QAD" -ForegroundColor Green

# ============================================================================
# STEP 1B: Extract QAD Item-Level Standard Pack Mismatches
# ============================================================================
Write-Host "STEP 1B: Extracting standard pack mismatches..." -ForegroundColor Yellow

$sqlStandardPack = @"
SET NOCOUNT ON;

DECLARE @CurrentDate DATE = CAST(GETDATE() AS DATE);

-- Historical standard packs from transactions
WITH HistoricalPacks AS (
    SELECT 
        tr_part AS ItemNumber,
        tr_qty_chg AS PackQty,
        COUNT(*) AS UsageCount
    FROM [QADEE2798].[dbo].[tr_hist] WITH (NOLOCK)
    WHERE tr_site = '2798'
      AND tr_type IN ('RCT-PO', 'ISS-WO', 'RCT-WO')
      AND tr_qty_chg > 0
      AND tr_effdate >= DATEADD(MONTH, -12, GETDATE())
    GROUP BY tr_part, tr_qty_chg
),
ModalPacks AS (
    SELECT 
        ItemNumber,
        PackQty AS ActualStandardPack,
        UsageCount,
        ROW_NUMBER() OVER (PARTITION BY ItemNumber ORDER BY UsageCount DESC) AS rn
    FROM HistoricalPacks
    WHERE UsageCount >= 5
),
ActivePOLines AS (
    SELECT 
        pod.pod_po_site AS Site,
        po.po_vend AS SupplierCode,
        ad.ad_name AS SupplierName,
        pod.pod_part AS ItemNumber,
        pod.pod_nbr AS PONumber,
        pod.pod_line AS POLine,
        pod.pod_ord_mult AS QAD_StandardPack
    FROM [QADEE2798].[dbo].[pod_det] pod WITH (NOLOCK)
    JOIN [QADEE2798].[dbo].[po_mstr] po WITH (NOLOCK) ON pod.pod_nbr = po.po_nbr
    LEFT JOIN [QADEE2798].[dbo].[ad_mstr] ad WITH (NOLOCK) ON po.po_vend = ad.ad_addr
    WHERE pod.pod_po_site = '2798'
      AND pod.pod_status IS NULL
      AND pod.[pod_end_eff[1]]] > @CurrentDate
)
SELECT 
    a.Site,
    a.SupplierCode,
    a.SupplierName,
    a.ItemNumber,
    a.PONumber,
    a.POLine,
    a.QAD_StandardPack,
    m.ActualStandardPack AS SuggestedStandardPack,
    m.UsageCount,
    'Update pod_ord_mult from ' + CAST(a.QAD_StandardPack AS VARCHAR) + ' to ' + CAST(m.ActualStandardPack AS VARCHAR) AS Recommendation
FROM ActivePOLines a
INNER JOIN ModalPacks m ON a.ItemNumber = m.ItemNumber AND m.rn = 1
WHERE a.QAD_StandardPack <> m.ActualStandardPack
ORDER BY a.SupplierCode, a.ItemNumber;
"@

$standardPackMismatches = Invoke-SqlQuery -Query $sqlStandardPack
Write-Host "  Found $($standardPackMismatches.Count) standard pack mismatches (UsageCount >= 5)" -ForegroundColor Green

# ============================================================================
# STEP 2: Load IBT.csv and Compare with QAD
# ============================================================================
Write-Host "STEP 2: Loading IBT master data..." -ForegroundColor Yellow

if (-not (Test-Path $IBTPath)) {
    Write-Host "  WARNING: IBT.csv not found at: $IBTPath" -ForegroundColor Red
    Write-Host "  Skipping IBT comparison. Only QAD internal checks will be output." -ForegroundColor Red
    $ibtData = @()
} else {
    $ibtData = Import-Csv $IBTPath
    Write-Host "  Loaded $($ibtData.Count) rows from IBT.csv" -ForegroundColor Green
}

# ============================================================================
# STEP 2A: Compare QAD vs IBT (SD Pattern, Transport Days)
# ============================================================================
$ibtMismatches = @()
$missingFromIBT = @()

if ($ibtData.Count -gt 0) {
    Write-Host "STEP 2A: Comparing QAD vs IBT..." -ForegroundColor Yellow
    
    # Build IBT lookup by supplier code
    $ibtLookup = @{}
    foreach ($row in $ibtData) {
        $supplierCode = $row.'Supplier code'
        if ($supplierCode) {
            $ibtLookup[$supplierCode.Trim()] = @{
                SupplierName = $row.'Supplier'
                SDPattern = $row.'SD PATTERN'
                TransitDays = $row.'Transit time (days)'
            }
        }
    }
    Write-Host "  IBT lookup built for $($ibtLookup.Count) suppliers" -ForegroundColor Green
    
    foreach ($qadRow in $qadSuppliers) {
        $supplierCode = $qadRow.SupplierCode.ToString().Trim()
        
        if ($ibtLookup.ContainsKey($supplierCode)) {
            $ibt = $ibtLookup[$supplierCode]
            
            $sdMismatch = $false
            $tdMismatch = $false
            
            # Compare SD Pattern
            $qadSD = if ($qadRow.ModalSDPattern) { $qadRow.ModalSDPattern.ToString().Trim() } else { "" }
            $ibtSD = if ($ibt.SDPattern) { $ibt.SDPattern.ToString().Trim() } else { "" }
            if ($qadSD -ne $ibtSD -and $ibtSD -ne "") {
                $sdMismatch = $true
            }
            
            # Compare Transport Days
            $qadTD = if ($qadRow.ModalTransportDays -ne $null) { [int]$qadRow.ModalTransportDays } else { 0 }
            $ibtTD = if ($ibt.TransitDays) { [int]$ibt.TransitDays } else { 0 }
            if ([Math]::Abs($qadTD - $ibtTD) -ge 1 -and $ibtTD -gt 0) {
                $tdMismatch = $true
            }
            
            if ($sdMismatch -or $tdMismatch) {
                $ibtMismatches += [PSCustomObject]@{
                    Site = $qadRow.Site
                    SupplierCode = $supplierCode
                    SupplierName = $qadRow.SupplierName
                    QAD_SDPattern = $qadSD
                    IBT_SDPattern = $ibtSD
                    SDPattern_Mismatch = if ($sdMismatch) { "YES" } else { "NO" }
                    QAD_TransportDays = $qadTD
                    IBT_TransportDays = $ibtTD
                    TransportDays_Mismatch = if ($tdMismatch) { "YES" } else { "NO" }
                    Recommendation = ""
                }
                
                # Build recommendation
                $rec = @()
                if ($sdMismatch) { $rec += "Set SD Pattern to '$ibtSD'" }
                if ($tdMismatch) { $rec += "Set Transport Days to $ibtTD" }
                $ibtMismatches[-1].Recommendation = $rec -join "; "
            }
        } else {
            # Supplier in QAD but not in IBT
            $missingFromIBT += [PSCustomObject]@{
                Site = $qadRow.Site
                SupplierCode = $supplierCode
                SupplierName = $qadRow.SupplierName
                ActivePOLineCount = $qadRow.ActivePOLineCount
                Note = "Supplier exists in QAD but not found in IBT master"
            }
        }
    }
    
    Write-Host "  Found $($ibtMismatches.Count) QAD vs IBT mismatches" -ForegroundColor Green
    Write-Host "  Found $($missingFromIBT.Count) suppliers missing from IBT" -ForegroundColor Green
}

# ============================================================================
# STEP 3: Generate Output Reports
# ============================================================================
Write-Host "`nSTEP 3: Generating output reports..." -ForegroundColor Yellow

# Report 1: Supplier Internal Inconsistencies (QAD only)
$internalInconsistencies = $qadSuppliers | Where-Object { $_.HasInternalInconsistency -eq 'YES' }
$report1Path = Join-Path $OutputFolder "param_mismatch_01_internal_inconsistency.csv"
$internalInconsistencies | Export-Csv -Path $report1Path -NoTypeInformation
Write-Host "  [1] Internal inconsistencies: $($internalInconsistencies.Count) suppliers -> $report1Path" -ForegroundColor Green

# Report 2: QAD vs IBT Mismatches
$report2Path = Join-Path $OutputFolder "param_mismatch_02_qad_vs_ibt.csv"
if ($ibtMismatches.Count -gt 0) {
    $ibtMismatches | Export-Csv -Path $report2Path -NoTypeInformation
    Write-Host "  [2] QAD vs IBT mismatches: $($ibtMismatches.Count) suppliers -> $report2Path" -ForegroundColor Green
} else {
    Write-Host "  [2] QAD vs IBT mismatches: 0 (IBT not loaded or no mismatches)" -ForegroundColor Yellow
}

# Report 3: Suppliers Missing from IBT
$report3Path = Join-Path $OutputFolder "param_mismatch_03_missing_from_ibt.csv"
if ($missingFromIBT.Count -gt 0) {
    $missingFromIBT | Export-Csv -Path $report3Path -NoTypeInformation
    Write-Host "  [3] Missing from IBT: $($missingFromIBT.Count) suppliers -> $report3Path" -ForegroundColor Green
} else {
    Write-Host "  [3] Missing from IBT: 0 (IBT not loaded or all suppliers matched)" -ForegroundColor Yellow
}

# Report 4: Standard Pack Mismatches (Item Level)
$report4Path = Join-Path $OutputFolder "param_mismatch_04_standard_pack.csv"
$standardPackMismatches | Export-Csv -Path $report4Path -NoTypeInformation
Write-Host "  [4] Standard pack mismatches: $($standardPackMismatches.Count) items -> $report4Path" -ForegroundColor Green

# Report 5: All QAD Supplier Parameters (reference)
$report5Path = Join-Path $OutputFolder "param_reference_qad_suppliers.csv"
$qadSuppliers | Export-Csv -Path $report5Path -NoTypeInformation
Write-Host "  [5] QAD supplier reference: $($qadSuppliers.Count) suppliers -> $report5Path" -ForegroundColor Green

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "   SUMMARY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Total QAD suppliers:              $($qadSuppliers.Count)"
Write-Host "  Internal inconsistencies:         $($internalInconsistencies.Count) suppliers"
Write-Host "  QAD vs IBT mismatches:            $($ibtMismatches.Count) suppliers"
Write-Host "  Missing from IBT:                 $($missingFromIBT.Count) suppliers"
Write-Host "  Standard pack mismatches:         $($standardPackMismatches.Count) items"
Write-Host ""
Write-Host "Output files in: $OutputFolder" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Review param_mismatch_01_internal_inconsistency.csv"
Write-Host "     -> Standardize SD pattern & transport days per supplier"
Write-Host "  2. Review param_mismatch_02_qad_vs_ibt.csv"
Write-Host "     -> Align QAD to IBT master values"
Write-Host "  3. Review param_mismatch_04_standard_pack.csv"
Write-Host "     -> Update pod_ord_mult to suggested values"
Write-Host "  4. Use these CSVs to create CIM files for mass upload"
Write-Host "============================================`n" -ForegroundColor Cyan
