# ============================================================================
# MASTER ORCHESTRATION SCRIPT
# Runs the complete MRP analysis pipeline:
#   1. Execute SQL queries and export CSVs
#   2. Run comparison between MRP and Supplier Schedules
#   3. Generate insights and recommendations
# ============================================================================

param(
    [string]$Server = "a265m001",
    [string]$Database = "QADEE2798",
    [string]$Username = "PowerBI",
    [string]$Password = "P0werB1",
    [switch]$SkipSqlExport,
    [switch]$SkipValidation
)

$ErrorActionPreference = 'Stop'
$basePath = "C:\Users\ajelacn\OneDrive - Adient\Documents\SQL Server Management Studio"
$mrpFolder = "$basePath\MRP\ShadowMRP"
$outputFolder = "$basePath\output"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "   SHADOW MRP FULL ANALYSIS PIPELINE" -ForegroundColor Cyan
Write-Host "   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Ensure output folder exists
if (-not (Test-Path $outputFolder)) {
    New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
}

# --- Helper: Run SQL and export to CSV ---
function Invoke-SqlToCsv {
    param(
        [string]$SqlFile,
        [string]$OutFile,
        [string]$Description
    )
    
    Write-Host "[$Description]" -ForegroundColor Yellow
    Write-Host "  SQL: $SqlFile" -ForegroundColor Gray
    Write-Host "  OUT: $OutFile" -ForegroundColor Gray
    
    Add-Type -AssemblyName System.Data
    $connString = "Server=$Server;Database=$Database;User ID=$Username;Password=$Password;Encrypt=False;TrustServerCertificate=True;"
    
    try {
        $conn = New-Object System.Data.SqlClient.SqlConnection $connString
        $conn.Open()
        
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = Get-Content $SqlFile -Raw
        $cmd.CommandTimeout = 600  # 10 minutes
        
        $reader = $cmd.ExecuteReader()
        $table = New-Object System.Data.DataTable
        $table.Load($reader)
        
        $table | Export-Csv $OutFile -NoTypeInformation -Encoding UTF8
        Write-Host "  Done: $($table.Rows.Count) rows" -ForegroundColor Green
        
        $conn.Close()
        return $true
    }
    catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# ============================================================================
# STEP 1: Execute SQL queries and export CSVs
# ============================================================================
if (-not $SkipSqlExport) {
    Write-Host ""
    Write-Host "STEP 1: Exporting SQL query results to CSV" -ForegroundColor Cyan
    Write-Host "-------------------------------------------" -ForegroundColor Cyan
    
    # MRP Shadow Query
    $success1 = Invoke-SqlToCsv `
        -SqlFile "$mrpFolder\04_ShadowMRP_ReadOnly_Query.sql" `
        -OutFile "$outputFolder\output.csv" `
        -Description "Shadow MRP Planned Orders"
    
    # Active Supplier Schedules
    $success2 = Invoke-SqlToCsv `
        -SqlFile "$mrpFolder\06_Active_Supplier_Schedules.sql" `
        -OutFile "$outputFolder\output_supplier_releases.csv" `
        -Description "Active Supplier Schedules"
    
    if (-not $success1 -or -not $success2) {
        Write-Host "SQL export failed. Aborting." -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host ""
    Write-Host "STEP 1: SKIPPED (using existing CSVs)" -ForegroundColor DarkGray
}

# ============================================================================
# STEP 2: Run Parameter Validation & Anomaly Detection (optional)
# ============================================================================
if (-not $SkipValidation) {
    Write-Host ""
    Write-Host "STEP 2: Running Parameter Validation & Anomaly Detection" -ForegroundColor Cyan
    Write-Host "-------------------------------------" -ForegroundColor Cyan
    
    Write-Host "  NOTE: 08_Parameter_Validation_Combined.sql expects #IBT_Master to be loaded from IBT.csv (optional)" -ForegroundColor Yellow

    # Parameter validation (combined) - non-fatal if IBT is not loaded or any error occurs
    $paramSuccess = $false
    try {
        $paramSuccess = Invoke-SqlToCsv `
            -SqlFile "$mrpFolder\08_Parameter_Validation_Combined.sql" `
            -OutFile "$outputFolder\output_parameter_validation.csv" `
            -Description "Parameter Validation (Combined)"
    }
    catch {
        Write-Host "  Parameter validation failed or IBT not loaded: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    if (-not $paramSuccess) {
        Write-Host "  Parameter validation skipped (no IBT data or error)." -ForegroundColor DarkYellow
    }

    # Anomaly Detection (combined) - also non-fatal
    $anomalySuccess = $false
    try {
        $anomalySuccess = Invoke-SqlToCsv `
            -SqlFile "$mrpFolder\09_Anomaly_Detection_Combined.sql" `
            -OutFile "$outputFolder\output_anomalies.csv" `
            -Description "Anomaly Detection (Combined)"
    }
    catch {
        Write-Host "  Anomaly detection failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host ""
    Write-Host "STEP 2: SKIPPED (validation not requested)" -ForegroundColor DarkGray
}

# ============================================================================
# STEP 3: Run MRP vs Supplier Comparison
# ============================================================================
Write-Host ""
Write-Host "STEP 3: Running MRP vs Supplier Comparison" -ForegroundColor Cyan
Write-Host "-------------------------------------------" -ForegroundColor Cyan

try {
    & powershell -ExecutionPolicy Bypass -File "$mrpFolder\07_Compare_MRP_vs_SupplierSchedules.ps1"
    Write-Host "  Comparison complete" -ForegroundColor Green
}
catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================================================
# STEP 4: Generate Insights
# ============================================================================
Write-Host ""
Write-Host "STEP 4: Generating Insights" -ForegroundColor Cyan
Write-Host "-------------------------------------------" -ForegroundColor Cyan

try {
    & powershell -ExecutionPolicy Bypass -File "$mrpFolder\10_MRP_Insight_Engine.ps1"
}
catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================================================
# FINAL SUMMARY
# ============================================================================
Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "   PIPELINE COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Output files created in: $outputFolder" -ForegroundColor Yellow
Write-Host ""
Get-ChildItem "$outputFolder\output*.csv" | ForEach-Object {
    $size = [math]::Round($_.Length / 1KB, 1)
    Write-Host "  - $($_.Name) ($size KB)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Review output_mrp_insights.csv for action items" -ForegroundColor Gray
Write-Host "  2. Review output_mrp_summary.csv for priority overview" -ForegroundColor Gray
Write-Host "  3. Address Critical/High priority items first" -ForegroundColor Gray
Write-Host "  4. Run 08_Parameter_Validation.sql in SSMS to sync with IBT" -ForegroundColor Gray
Write-Host ""
