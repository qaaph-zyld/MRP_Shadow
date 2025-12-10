param(
    [string]$MrpPath = "C:\Users\ajelacn\OneDrive - Adient\Documents\SQL Server Management Studio\output\output.csv",
    [string]$SupplierPath = "C:\Users\ajelacn\OneDrive - Adient\Documents\SQL Server Management Studio\output\output_supplier_releases.csv",
    [string]$OutPath = "C:\Users\ajelacn\OneDrive - Adient\Documents\SQL Server Management Studio\output\output_mrp_vs_supplier.csv"
)

$ErrorActionPreference = 'Stop'

Write-Host "Loading MRP output from: $MrpPath" -ForegroundColor Cyan
$mrp = Import-Csv $MrpPath

Write-Host "Loading supplier releases from: $SupplierPath" -ForegroundColor Cyan
$supp = Import-Csv $SupplierPath

Write-Host ("MRP rows:       {0}" -f $mrp.Count) -ForegroundColor Yellow
Write-Host ("Supplier rows:  {0}" -f $supp.Count) -ForegroundColor Yellow
Write-Host "Starting aggregation..." -ForegroundColor Cyan

# --- Helper: safe decimal conversion
function To-Decimal($value) {
    if ($null -eq $value -or $value -eq '') { return [decimal]0 }
    try {
        return [decimal]::Parse($value.ToString().Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return [decimal]0
    }
}

# --- Helper: safe date parsing for both 'dd/MM/yyyy' and 'dd/MM/yyyy hh:mm:ss'
function Get-SafeDate($text) {
    if ($null -eq $text -or "$text".Trim() -eq '') { return $null }

    $raw = "$text".Trim()
    # If there is a time part, take only the date portion before the first space
    $dateOnly = $raw.Split(' ')[0]

    $out = [datetime]::MinValue
    if ([datetime]::TryParseExact($dateOnly, 'dd/MM/yyyy', $null, [System.Globalization.DateTimeStyles]::None, [ref]$out)) {
        return $out
    }
    if ([datetime]::TryParse($dateOnly, [ref]$out)) {
        return $out
    }
    return $null
}

# --- Build monthly aggregated MRP planned orders per item/supplier ---
$mrpAgg = $mrp |
    Where-Object { $_.PlannedOrderQty -ne '' -and (To-Decimal $_.PlannedOrderQty) -gt 0 } |
    ForEach-Object {
        $due = Get-SafeDate $_.PlannedOrderDueDate
        if ($due) {
            [PSCustomObject]@{
                ItemNumber = $_.ItemNumber
                Supplier   = $_.Supplier
                Month      = '{0:yyyy-MM}' -f $due
                Qty        = To-Decimal $_.PlannedOrderQty
            }
        }
    } |
    Group-Object ItemNumber, Supplier, Month |
    ForEach-Object {
        $key = $_.Name.Split(',')
        [PSCustomObject]@{
            ItemNumber     = $key[0].Trim()
            Supplier       = $key[1].Trim()
            Month          = $key[2].Trim()
            MrpPlannedQty  = ($_.Group | Measure-Object -Property Qty -Sum).Sum
        }
    }

# --- Build monthly aggregated supplier scheduled quantities per item/supplier ---
$suppAgg = $supp |
    Where-Object { $_.'Schedule Qty' -ne '' -and (To-Decimal $_.'Schedule Qty') -gt 0 -and $_.'Active/Closed' -eq 'Active' } |
    ForEach-Object {
        # Schedule release Date example: 16/02/2026 00:00:00
        $d = Get-SafeDate $_.'Schedule release Date'
        if ($d) {
            [PSCustomObject]@{
                ItemNumber = $_.'Item Number'
                Supplier   = $_.'PO Supplier'
                Month      = '{0:yyyy-MM}' -f $d
                Qty        = To-Decimal $_.'Schedule Qty'
            }
        }
    } |
    Group-Object ItemNumber, Supplier, Month |
    ForEach-Object {
        $key = $_.Name.Split(',')
        [PSCustomObject]@{
            ItemNumber        = $key[0].Trim()
            Supplier          = $key[1].Trim()
            Month             = $key[2].Trim()
            SupplierSchedQty  = ($_.Group | Measure-Object -Property Qty -Sum).Sum
        }
    }

# Log aggregated key counts
Write-Host ("MRP agg keys:      {0}" -f $mrpAgg.Count) -ForegroundColor Yellow
Write-Host ("Supplier agg keys: {0}" -f $suppAgg.Count) -ForegroundColor Yellow

# --- Join MRP and Supplier aggregates using hash tables for performance ---
$mrpIndex = @{}
foreach ($m in $mrpAgg) {
    $key = "$(($m.ItemNumber))|$(($m.Supplier))|$(($m.Month))"
    $mrpIndex[$key] = $m
}

$suppIndex = @{}
foreach ($s in $suppAgg) {
    $key = "$(($s.ItemNumber))|$(($s.Supplier))|$(($s.Month))"
    $suppIndex[$key] = $s
}

$allKeyStrings = ($mrpIndex.Keys + $suppIndex.Keys) | Sort-Object -Unique
Write-Host ("Total unique item/supplier/month keys: {0}" -f $allKeyStrings.Count) -ForegroundColor Yellow

$result = foreach ($key in $allKeyStrings) {
    $m = $mrpIndex[$key]
    $s = $suppIndex[$key]

    $parts = $key.Split('|')
    $item = $parts[0]
    $suppCode = $parts[1]
    $month = $parts[2]

    $mrpQty = if ($m) { [decimal]$m.MrpPlannedQty } else { [decimal]0 }
    $supQty = if ($s) { [decimal]$s.SupplierSchedQty } else { [decimal]0 }
    $delta  = $mrpQty - $supQty
    $coverage = if ($supQty -ne 0) { [math]::Round([double]($mrpQty / $supQty), 3) } else { $null }

    $status = if ($supQty -eq 0 -and $mrpQty -eq 0) { 'NoDemand' }
              elseif ($supQty -gt 0 -and $mrpQty -eq 0) { 'MRP_Missing' }
              elseif ($supQty -eq 0 -and $mrpQty -gt 0) { 'MRP_Extra' }
              elseif ($mrpQty -ge $supQty) { 'Covered_or_Over' }
              else { 'Short' }

    [PSCustomObject]@{
        ItemNumber       = $item
        Supplier         = $suppCode
        Month            = $month
        MrpPlannedQty    = [decimal]$mrpQty
        SupplierSchedQty = [decimal]$supQty
        Delta            = [decimal]$delta
        CoverageRatio    = $coverage
        Status           = $status
    }
}

Write-Host "Writing comparison to: $OutPath" -ForegroundColor Cyan
$result | Sort-Object ItemNumber, Supplier, Month | Export-Csv $OutPath -NoTypeInformation -Encoding UTF8

Write-Host "Done. Rows: $($result.Count)" -ForegroundColor Green
