param(
    [string]$MrpPath = "C:\Users\ajelacn\OneDrive - Adient\Documents\SQL Server Management Studio\output\output.csv",
    [string]$SupplierPath = "C:\Users\ajelacn\OneDrive - Adient\Documents\SQL Server Management Studio\output\output_supplier_releases.csv",
    [string]$ComparisonPath = "C:\Users\ajelacn\OneDrive - Adient\Documents\SQL Server Management Studio\output\output_mrp_vs_supplier.csv",
    [string]$InsightPath = "C:\Users\ajelacn\OneDrive - Adient\Documents\SQL Server Management Studio\output\output_mrp_insights.csv",
    [string]$SummaryPath = "C:\Users\ajelacn\OneDrive - Adient\Documents\SQL Server Management Studio\output\output_mrp_summary.csv"
)

$ErrorActionPreference = 'Stop'

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   MRP INSIGHT ENGINE" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# --- Helper Functions ---
function To-Decimal($value) {
    if ($null -eq $value -or $value -eq '') { return [decimal]0 }
    try { return [decimal]::Parse($value.ToString().Trim(), [System.Globalization.CultureInfo]::InvariantCulture) }
    catch { return [decimal]0 }
}

function Get-SafeDate($text) {
    if ($null -eq $text -or "$text".Trim() -eq '') { return $null }
    $raw = "$text".Trim()
    $dateOnly = $raw.Split(' ')[0]
    $out = [datetime]::MinValue
    if ([datetime]::TryParseExact($dateOnly, 'dd/MM/yyyy', $null, [System.Globalization.DateTimeStyles]::None, [ref]$out)) { return $out }
    if ([datetime]::TryParse($dateOnly, [ref]$out)) { return $out }
    return $null
}

# --- Load comparison data ---
Write-Host "Loading comparison data..." -ForegroundColor Yellow
if (-not (Test-Path $ComparisonPath)) {
    Write-Host "Comparison file not found. Run 07_Compare_MRP_vs_SupplierSchedules.ps1 first." -ForegroundColor Red
    exit 1
}
$comparison = Import-Csv $ComparisonPath
Write-Host "  Loaded $($comparison.Count) comparison rows" -ForegroundColor Gray

# --- Load MRP data for parameter extraction ---
Write-Host "Loading MRP output for parameters..." -ForegroundColor Yellow
$mrp = Import-Csv $MrpPath
$mrpParams = $mrp | Group-Object ItemNumber | ForEach-Object {
    $first = $_.Group[0]
    [PSCustomObject]@{
        ItemNumber    = $_.Name
        Supplier      = $first.Supplier
        SupplierName  = $first.SupplierName
        SafetyStock   = To-Decimal $first.SafetyStock
        StandardPack  = To-Decimal $first.StandardPack
        TransportDays = To-Decimal $first.TransportDays
        Planner       = $first.Planner
    }
}
Write-Host "  Extracted parameters for $($mrpParams.Count) items" -ForegroundColor Gray

# --- Classify each comparison row with detailed insights ---
Write-Host "Generating insights..." -ForegroundColor Yellow

$insights = foreach ($row in $comparison) {
    $mrpQty = To-Decimal $row.MrpPlannedQty
    $supQty = To-Decimal $row.SupplierSchedQty
    $delta = To-Decimal $row.Delta
    $coverage = if ($row.CoverageRatio -ne '') { [double]$row.CoverageRatio } else { $null }
    
    $param = $mrpParams | Where-Object { $_.ItemNumber -eq $row.ItemNumber } | Select-Object -First 1
    
    # Determine insight category and recommendation
    $insightCategory = ''
    $recommendation = ''
    $priority = 'Low'
    $potentialImpact = ''
    
    switch ($row.Status) {
        'Short' {
            $insightCategory = 'UNDER_PLANNED'
            $shortfall = [math]::Abs($delta)
            if ($coverage -lt 0.5) {
                $priority = 'Critical'
                $recommendation = "MRP covers less than 50% of supplier schedule. Review demand source, BOM explosion, or horizon settings."
                $potentialImpact = "Risk of stockout. Supplier expects $supQty but MRP only plans $mrpQty."
            } elseif ($coverage -lt 0.8) {
                $priority = 'High'
                $recommendation = "MRP undercoverage. Check if all customer schedules are loaded and BOM is complete."
                $potentialImpact = "Potential supply gap of $shortfall units."
            } else {
                $priority = 'Medium'
                $recommendation = "Minor undercoverage. May be timing difference or rounding."
                $potentialImpact = "Small gap of $shortfall units, likely acceptable."
            }
        }
        'MRP_Missing' {
            $insightCategory = 'MRP_BLIND_SPOT'
            $priority = 'Critical'
            $recommendation = "Supplier has schedule but MRP shows no demand. Check: (1) Item in BOM? (2) FG has active schedule? (3) PO line active?"
            $potentialImpact = "Supplier expects $supQty but MRP is unaware. Risk of surprise shortage."
        }
        'MRP_Extra' {
            $insightCategory = 'POTENTIAL_OVERSTOCK'
            if ($mrpQty -gt 100000) {
                $priority = 'High'
                $recommendation = "MRP plans $mrpQty but no supplier schedule. Verify if demand is real or if supplier release is missing."
                $potentialImpact = "Risk of excess inventory if demand is not confirmed."
            } else {
                $priority = 'Medium'
                $recommendation = "MRP has demand but supplier schedule is empty. May need to send release to supplier."
                $potentialImpact = "Supplier may not be expecting this order. Confirm and release."
            }
        }
        'Covered_or_Over' {
            $insightCategory = 'ALIGNED'
            if ($coverage -gt 1.5) {
                $priority = 'Low'
                $recommendation = "MRP plans significantly more than supplier schedule. Review if intentional safety buffer."
                $potentialImpact = "Potential overstock of $delta units."
            } else {
                $priority = 'OK'
                $recommendation = "MRP and supplier schedule are well aligned."
                $potentialImpact = "No action needed."
            }
        }
        'NoDemand' {
            $insightCategory = 'NO_ACTIVITY'
            $priority = 'Info'
            $recommendation = "No demand in either system for this month."
            $potentialImpact = "None."
        }
    }
    
    [PSCustomObject]@{
        ItemNumber       = $row.ItemNumber
        Supplier         = $row.Supplier
        SupplierName     = if ($param) { $param.SupplierName } else { '' }
        Month            = $row.Month
        MrpPlannedQty    = $mrpQty
        SupplierSchedQty = $supQty
        Delta            = $delta
        CoverageRatio    = $coverage
        Status           = $row.Status
        InsightCategory  = $insightCategory
        Priority         = $priority
        Recommendation   = $recommendation
        PotentialImpact  = $potentialImpact
        SafetyStock      = if ($param) { $param.SafetyStock } else { '' }
        StandardPack     = if ($param) { $param.StandardPack } else { '' }
        TransportDays    = if ($param) { $param.TransportDays } else { '' }
        Planner          = if ($param) { $param.Planner } else { '' }
    }
}

# --- Export detailed insights ---
Write-Host "Writing insights to: $InsightPath" -ForegroundColor Cyan
$insights | Export-Csv $InsightPath -NoTypeInformation -Encoding UTF8
Write-Host "  Written $($insights.Count) insight rows" -ForegroundColor Green

# --- Generate summary by priority and category ---
Write-Host "Generating summary..." -ForegroundColor Yellow

$summary = @()

# Priority summary
$summary += [PSCustomObject]@{
    SummaryType = 'BY_PRIORITY'
    Category    = 'Critical'
    Count       = ($insights | Where-Object { $_.Priority -eq 'Critical' }).Count
    TotalDelta  = ($insights | Where-Object { $_.Priority -eq 'Critical' } | Measure-Object -Property Delta -Sum).Sum
    Action      = 'Immediate review required'
}
$summary += [PSCustomObject]@{
    SummaryType = 'BY_PRIORITY'
    Category    = 'High'
    Count       = ($insights | Where-Object { $_.Priority -eq 'High' }).Count
    TotalDelta  = ($insights | Where-Object { $_.Priority -eq 'High' } | Measure-Object -Property Delta -Sum).Sum
    Action      = 'Review within 1 week'
}
$summary += [PSCustomObject]@{
    SummaryType = 'BY_PRIORITY'
    Category    = 'Medium'
    Count       = ($insights | Where-Object { $_.Priority -eq 'Medium' }).Count
    TotalDelta  = ($insights | Where-Object { $_.Priority -eq 'Medium' } | Measure-Object -Property Delta -Sum).Sum
    Action      = 'Review within 2 weeks'
}
$summary += [PSCustomObject]@{
    SummaryType = 'BY_PRIORITY'
    Category    = 'Low/OK'
    Count       = ($insights | Where-Object { $_.Priority -in 'Low','OK','Info' }).Count
    TotalDelta  = ($insights | Where-Object { $_.Priority -in 'Low','OK','Info' } | Measure-Object -Property Delta -Sum).Sum
    Action      = 'Monitor only'
}

# Category summary
foreach ($cat in ($insights | Select-Object -ExpandProperty InsightCategory -Unique)) {
    $catRows = $insights | Where-Object { $_.InsightCategory -eq $cat }
    $summary += [PSCustomObject]@{
        SummaryType = 'BY_CATEGORY'
        Category    = $cat
        Count       = $catRows.Count
        TotalDelta  = ($catRows | Measure-Object -Property Delta -Sum).Sum
        Action      = ''
    }
}

# Top problem items
$topProblems = $insights | Where-Object { $_.Priority -in 'Critical','High' } | 
    Sort-Object { [math]::Abs($_.Delta) } -Descending | 
    Select-Object -First 20

foreach ($p in $topProblems) {
    $summary += [PSCustomObject]@{
        SummaryType = 'TOP_PROBLEM_ITEMS'
        Category    = "$($p.ItemNumber) / $($p.Month)"
        Count       = 1
        TotalDelta  = $p.Delta
        Action      = $p.Recommendation
    }
}

# Export summary
Write-Host "Writing summary to: $SummaryPath" -ForegroundColor Cyan
$summary | Export-Csv $SummaryPath -NoTypeInformation -Encoding UTF8

# --- Console summary ---
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "   INSIGHT SUMMARY" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Priority Breakdown:" -ForegroundColor Yellow
$insights | Group-Object Priority | Sort-Object { 
    switch ($_.Name) { 'Critical' { 0 } 'High' { 1 } 'Medium' { 2 } 'Low' { 3 } 'OK' { 4 } default { 5 } }
} | ForEach-Object {
    $color = switch ($_.Name) { 'Critical' { 'Red' } 'High' { 'DarkYellow' } 'Medium' { 'Yellow' } default { 'Gray' } }
    Write-Host "  $($_.Name): $($_.Count) items" -ForegroundColor $color
}

Write-Host ""
Write-Host "Category Breakdown:" -ForegroundColor Yellow
$insights | Group-Object InsightCategory | ForEach-Object {
    Write-Host "  $($_.Name): $($_.Count) items"
}

Write-Host ""
Write-Host "Top 5 Critical/High Priority Items:" -ForegroundColor Yellow
$topProblems | Select-Object -First 5 | ForEach-Object {
    Write-Host "  $($_.ItemNumber) | $($_.Month) | Delta: $($_.Delta) | $($_.Priority)" -ForegroundColor $(if ($_.Priority -eq 'Critical') { 'Red' } else { 'DarkYellow' })
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "Done. Files created:" -ForegroundColor Green
Write-Host "  - $InsightPath" -ForegroundColor Gray
Write-Host "  - $SummaryPath" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Green
