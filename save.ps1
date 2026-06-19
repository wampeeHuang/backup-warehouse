param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$inbox = Join-Path $root "inbox"
$store = Join-Path $root "store\sha256"
$indexFile = Join-Path $root "index.jsonl"
$ignoreFile = Join-Path $root "_config\warehouseignore"
$runtimeDir = Join-Path $root "_runtime"

foreach ($d in @($store, $runtimeDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

$ignorePatterns = @()
if (Test-Path $ignoreFile) {
    $ignorePatterns = Get-Content $ignoreFile | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' } | ForEach-Object { $_.Trim() }
}

function Test-Ignored($filePath) {
    $relative = $filePath.Replace("$inbox\", "").Replace("\", "/")
    foreach ($p in $ignorePatterns) {
        # directory pattern: "node_modules/" matches any file under it
        if ($p.EndsWith("/") -and $relative.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
        # wildcard patterns: "*.log", "*.tmp"
        if ($p.StartsWith("*.") -and $relative.EndsWith($p.Substring(1), [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
        # exact match or contains
        if ($relative -like "*$p*") {
            return $true
        }
    }
    return $false
}

function Get-Hash($path) {
    return (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLower()
}

$files = @(Get-ChildItem -Path $inbox -File -Recurse -ErrorAction SilentlyContinue)
if (-not $files -or $files.Count -eq 0) {
    Write-Host "inbox is empty, nothing to digest."
    exit 0
}

if (-not (Test-Path $indexFile)) {
    "" | Set-Content $indexFile -Encoding UTF8
}

$existingHashes = @{}
if (Test-Path $indexFile) {
    Get-Content $indexFile -Encoding UTF8 | Where-Object { $_ -match '"hash":"sha256:([a-f0-9]{64})"' } | ForEach-Object {
        if ($_ -match '"hash":"sha256:([a-f0-9]{64})"') {
            $existingHashes[$matches[1]] = $true
        }
    }
}

$stats = @{ scanned = 0; stored = 0; deduped = 0; skipped = 0; errors = 0 }
$newRecords = @()

Write-Host ("=" * 60)
Write-Host ("Digesting inbox: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Write-Host ("Files found: {0}" -f $files.Count)
Write-Host ("")

foreach ($file in $files) {
    $stats.scanned++

    if ($file.Name -eq "receipt.md" -or $file.Name -eq ".source.json" -or $file.Name -eq ".gitkeep") {
        $stats.skipped++
        continue
    }

    if (Test-Ignored $file.FullName) {
        Write-Host ("  SKIP: {0}" -f $file.FullName.Replace("$inbox\", ""))
        $stats.skipped++
        continue
    }

    try {
        $rawHash = Get-Hash $file.FullName
        $hash = "sha256:$rawHash"
        $prefix = $rawHash.Substring(0, 2)
        $storeDir = Join-Path $store $prefix
        $storePath = Join-Path $storeDir $rawHash

        if ($existingHashes.ContainsKey($rawHash) -or (Test-Path $storePath)) {
            $record = @{
                hash = $hash
                path = $file.FullName.Replace("$inbox\", "")
                size = $file.Length
                mtime = $file.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
                inbox_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                ext = $file.Extension
            }
            $newRecords += (ConvertTo-Json $record -Compress)
            $existingHashes[$rawHash] = $true

            if (-not $DryRun) { Remove-Item $file.FullName -Force }
            Write-Host ("  DEDUP: {0} ({1:N0} B)" -f $file.Name, $file.Length)
            $stats.deduped++
            continue
        }

        if (-not (Test-Path $storeDir)) {
            New-Item -ItemType Directory -Path $storeDir -Force | Out-Null
        }

        if (-not $DryRun) {
            Copy-Item $file.FullName $storePath -Force
            $storeRawHash = Get-Hash $storePath
            if ($storeRawHash -ne $rawHash) {
                Write-Host ("  ERROR: hash mismatch - {0}" -f $file.Name)
                Remove-Item $storePath -Force -ErrorAction SilentlyContinue
                $stats.errors++
                continue
            }
        }

        $record = @{
            hash = $hash
            path = $file.FullName.Replace("$inbox\", "")
            size = $file.Length
            mtime = $file.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
            inbox_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            ext = $file.Extension
        }
        $newRecords += (ConvertTo-Json $record -Compress)
        $existingHashes[$rawHash] = $true

        if (-not $DryRun) { Remove-Item $file.FullName -Force }
        Write-Host ("  STORE: {0} ({1:N0} B)" -f $file.Name, $file.Length)
        $stats.stored++
    }
    catch {
        Write-Host ("  ERROR: {0} - {1}" -f $file.Name, $_.Exception.Message)
        $stats.errors++
    }
}

if ($newRecords.Count -gt 0 -and -not $DryRun) {
    $newRecords | Add-Content $indexFile -Encoding UTF8
}

# Clean empty dirs
Get-ChildItem -Path $inbox -Directory -Recurse -ErrorAction SilentlyContinue |
    Where-Object { @(Get-ChildItem $_.FullName -Force).Count -eq 0 } |
    ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

Write-Host ("")
Write-Host ("-" * 60)
Write-Host ("Digest complete")
Write-Host ("  scanned: {0}" -f $stats.scanned)
Write-Host ("  stored:  {0}" -f $stats.stored)
Write-Host ("  deduped: {0}" -f $stats.deduped)
Write-Host ("  skipped: {0}" -f $stats.skipped)
if ($stats.errors -gt 0) { Write-Host ("  ERRORS:  {0}" -f $stats.errors) }
Write-Host ("=" * 60)

if ($DryRun) { Write-Host "(DryRun mode)" }

if ($stats.errors -gt 0) { exit 1 } else { exit 0 }
