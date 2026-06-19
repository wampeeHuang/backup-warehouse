param(
    [int]$SampleSize = 10
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$indexFile = Join-Path $root "index.jsonl"
$storeDir = Join-Path $root "store\sha256"
$attentionFile = Join-Path $root "ATTENTION.md"
$runtimeDir = Join-Path $root "_runtime"

if (-not (Test-Path $runtimeDir)) {
    New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null
}
$reportFile = Join-Path $runtimeDir "check-report.txt"

$issues = @()

Write-Host ("=" * 60)
Write-Host ("Warehouse check: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Write-Host ("")

$indexHashes = @{}
if (Test-Path $indexFile) {
    Get-Content $indexFile -Encoding UTF8 | Where-Object { $_ -match '"hash":"sha256:([a-f0-9]{64})"' } | ForEach-Object {
        if ($_ -match '"hash":"sha256:([a-f0-9]{64})"') {
            $indexHashes[$matches[1]] = $true
        }
    }
}
$indexCount = $indexHashes.Count
Write-Host ("  index records: {0}" -f $indexCount)

$storeFiles = @()
if (Test-Path $storeDir) {
    $storeFiles = @(Get-ChildItem -Path $storeDir -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^[a-f0-9]{64}$' })
}
$storeCount = $storeFiles.Count
Write-Host ("  store files:   {0}" -f $storeCount)

if ($indexCount -ne $storeCount) {
    $msg = "Count mismatch: index={0} store={1}" -f $indexCount, $storeCount
    Write-Host ("  FAIL: {0}" -f $msg)
    $issues += $msg

    $storeHashes = @{}
    foreach ($f in $storeFiles) { $storeHashes[$f.Name] = $true }
    $inIndexNotStore = $indexHashes.Keys | Where-Object { -not $storeHashes.ContainsKey($_) }
    $inStoreNotIndex = $storeHashes.Keys | Where-Object { -not $indexHashes.ContainsKey($_) }

    if ($inIndexNotStore) {
        Write-Host ("  In index but not store: {0}" -f $inIndexNotStore.Count)
        $inIndexNotStore | Select-Object -First 5 | ForEach-Object { Write-Host ("    {0}" -f $_) }
    }
    if ($inStoreNotIndex) {
        Write-Host ("  In store but not index: {0}" -f $inStoreNotIndex.Count)
        $inStoreNotIndex | Select-Object -First 5 | ForEach-Object { Write-Host ("    {0}" -f $_) }
    }
} else {
    Write-Host ("  Count OK")
}

$passed = 0
$failed = 0
if ($storeFiles.Count -gt 0) {
    Write-Host ("")
    $n = [Math]::Min($SampleSize, $storeFiles.Count)
    Write-Host ("  Spot-checking {0} files..." -f $n)
    $sample = Get-Random -InputObject $storeFiles -Count $n

    foreach ($f in $sample) {
        $computed = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLower()
        $expected = $f.Name
        if ($computed -eq $expected) {
            $passed++
        } else {
            $msg = "SHA256 mismatch: {0}" -f $f.Name
            Write-Host ("  FAIL: {0}" -f $msg)
            $issues += $msg
            $failed++
        }
    }
    Write-Host ("  Passed: {0}, Failed: {1}" -f $passed, $failed)
}

# Write report
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$report = "[$timestamp] index=$indexCount store=$storeCount spot_check=$passed/$SampleSize issues=$($issues.Count)"
$report | Set-Content $reportFile -Encoding UTF8

# Handle issues
if ($issues.Count -gt 0) {
    $lines = @("# Warehouse Issue - $timestamp", "", "Issues found: $($issues.Count)", "")
    $lines += $issues | ForEach-Object { "- $_" }
    $lines += "", "See _runtime/check-report.txt for details."
    $lines -join "`n" | Set-Content $attentionFile -Encoding UTF8
    Write-Host ("")
    Write-Host ("=" * 60)
    Write-Host ("ISSUES: {0} - see ATTENTION.md" -f $issues.Count)
    exit 1
} else {
    if (Test-Path $attentionFile) {
        Remove-Item $attentionFile -Force
    }
    Write-Host ("")
    Write-Host ("=" * 60)
    Write-Host ("OK - warehouse healthy")
    exit 0
}
