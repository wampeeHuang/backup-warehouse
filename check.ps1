param(
    [int]$SampleSize = 10
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$indexFile = Join-Path $root "index.jsonl"
$storeDir = Join-Path $root "store"
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

# Read index
$indexEntries = @()
if (Test-Path $indexFile) {
    Get-Content $indexFile -Encoding UTF8 | ForEach-Object {
        try {
            $obj = $_ | ConvertFrom-Json
            $indexEntries += $obj
        } catch {}
    }
}
$indexCount = $indexEntries.Count
Write-Host ("  index records: {0}" -f $indexCount)

# Count store files (exclude .gitkeep)
$storeFiles = @()
if (Test-Path $storeDir) {
    $storeFiles = @(Get-ChildItem -Path $storeDir -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne ".gitkeep" })
}
$storeCount = $storeFiles.Count
Write-Host ("  store files:   {0}" -f $storeCount)

# Count unique hashes in index
$indexHashes = @{}
foreach ($entry in $indexEntries) {
    $h = $entry.hash -replace '^sha256:', ''
    $indexHashes[$h] = $true
}
$uniqueHashCount = $indexHashes.Count
Write-Host ("  unique hashes: {0}" -f $uniqueHashCount)

if ($uniqueHashCount -ne $storeCount) {
    $msg = "Count mismatch: unique-hashes={0} store-files={1}" -f $uniqueHashCount, $storeCount
    Write-Host ("  FAIL: {0}" -f $msg)
    $issues += $msg

    $storeFileNames = @{}
    foreach ($f in $storeFiles) { $storeFileNames[$f.FullName] = $true }

    $indexFilePaths = @{}
    foreach ($entry in $indexEntries) {
        $dateFolder = if ($entry.mtime) { $entry.mtime.Substring(0, 10) } else { "" }
        $fp = Join-Path $storeDir $dateFolder $entry.path
        $indexFilePaths[$fp] = $true
    }

    $inStoreNotIndex = $storeFileNames.Keys | Where-Object { -not $indexFilePaths.ContainsKey($_) }
    $inIndexNotStore = $indexFilePaths.Keys | Where-Object { -not $storeFileNames.ContainsKey($_) }

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

# Spot-check
$passed = 0
$failed = 0
if ($indexEntries.Count -gt 0) {
    Write-Host ("")
    $n = [Math]::Min($SampleSize, $indexEntries.Count)
    Write-Host ("  Spot-checking {0} files..." -f $n)
    $sample = Get-Random -InputObject $indexEntries -Count $n

    foreach ($entry in $sample) {
        $dateFolder = if ($entry.mtime) { $entry.mtime.Substring(0, 10) } else { (Get-Date $entry.inbox_at).ToString("yyyy-MM-dd") }
        $filePath = Join-Path $storeDir $dateFolder $entry.path
        $expectedHash = $entry.hash -replace '^sha256:', ''

        if (-not (Test-Path $filePath)) {
            $msg = "File missing: {0}" -f $filePath
            Write-Host ("  FAIL: {0}" -f $msg)
            $issues += $msg
            $failed++
            continue
        }

        $computed = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash.ToLower()
        if ($computed -eq $expectedHash) {
            $passed++
        } else {
            $msg = "SHA256 mismatch: {0}" -f $entry.path
            Write-Host ("  FAIL: {0}" -f $msg)
            $issues += $msg
            $failed++
        }
    }
    Write-Host ("  Passed: {0}, Failed: {1}" -f $passed, $failed)
}

# Write report
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$report = "[$timestamp] index=$indexCount store=$storeCount unique-hashes=$uniqueHashCount spot_check=$passed/$SampleSize issues=$($issues.Count)"
$report | Set-Content $reportFile -Encoding UTF8

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
