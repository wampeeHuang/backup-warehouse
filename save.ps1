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

# Ensure directories exist
foreach ($d in @($store, $runtimeDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# Load ignore patterns
$ignorePatterns = @()
if (Test-Path $ignoreFile) {
    $ignorePatterns = Get-Content $ignoreFile | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' } | ForEach-Object { $_.Trim() }
}

function Test-Ignored($path) {
    $relative = $path.Replace("$inbox\", "").Replace("\", "/")
    foreach ($p in $ignorePatterns) {
        if ($relative -like $p) { return $true }
        if ($relative -match [regex]::Escape($p).Replace("\\*", ".*")) { return $true }
    }
    return $false
}

function Get-SHA256($path) {
    $hash = (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLower()
    return "sha256:$hash"
}

# Collect files from inbox
$files = Get-ChildItem -Path $inbox -File -Recurse -ErrorAction SilentlyContinue
if (-not $files -or $files.Count -eq 0) {
    Write-Host "inbox 为空，无需消化。"
    exit 0
}

# Init index if not exists
if (-not (Test-Path $indexFile)) {
    "" | Set-Content $indexFile -Encoding UTF8
}

# Load existing hashes from index for dedup
$existingHashes = @{}
if (Test-Path $indexFile) {
    Get-Content $indexFile -Encoding UTF8 | Where-Object { $_ -match 'sha256:([a-f0-9]{64})' } | ForEach-Object {
        if ($_ -match '"hash":"(sha256:[a-f0-9]{64})"') {
            $existingHashes[$matches[1]] = $true
        }
    }
}

$stats = @{ scanned = 0; stored = 0; deduped = 0; skipped = 0; errors = 0 }
$newRecords = @()

Write-Host ("=" * 60)
Write-Host ("开始消化 inbox: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Write-Host ("文件数: {0} 个" -f $files.Count)
Write-Host ("")

foreach ($file in $files) {
    $stats.scanned++

    # Skip warehouse's own files
    if ($file.Name -eq "receipt.md" -or $file.Name -eq ".source.json") {
        $stats.skipped++
        continue
    }

    # Apply ignore rules
    if (Test-Ignored $file.FullName) {
        Write-Host ("  跳过(过滤): {0}" -f $file.Name)
        $stats.skipped++
        continue
    }

    try {
        # Compute hash
        $hash = Get-SHA256 $file.FullName
        $prefix = $hash.Substring(7, 2)
        $storeDir = Join-Path $store $prefix
        $storePath = Join-Path $storeDir $hash

        # Check dedup
        if ($existingHashes.ContainsKey($hash) -or (Test-Path $storePath)) {
            # Dedup: only write index record, delete inbox copy
            $record = @{
                hash = $hash
                path = $file.FullName.Replace("$inbox\", "")
                size = $file.Length
                mtime = $file.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
                inbox_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                ext = $file.Extension
            }
            $newRecords += (ConvertTo-Json $record -Compress)
            $existingHashes[$hash] = $true

            if (-not $DryRun) {
                Remove-Item $file.FullName -Force
            }
            Write-Host ("  去重: {0} ({1:N0} B)" -f $file.Name, $file.Length)
            $stats.deduped++
            continue
        }

        # New file: copy to store
        if (-not (Test-Path $storeDir)) {
            New-Item -ItemType Directory -Path $storeDir -Force | Out-Null
        }

        if (-not $DryRun) {
            Copy-Item $file.FullName $storePath -Force

            # Verify store copy
            $storeHash = Get-SHA256 $storePath
            if ($storeHash -ne $hash) {
                Write-Host ("  🚨 SHA256 不匹配: {0}" -f $file.Name)
                Write-Host ("     源: {0}" -f $hash)
                Write-Host ("     副本: {0}" -f $storeHash)
                Remove-Item $storePath -Force -ErrorAction SilentlyContinue
                $stats.errors++
                continue
            }
        }

        # Write index record
        $record = @{
            hash = $hash
            path = $file.FullName.Replace("$inbox\", "")
            size = $file.Length
            mtime = $file.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
            inbox_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            ext = $file.Extension
        }
        $newRecords += (ConvertTo-Json $record -Compress)
        $existingHashes[$hash] = $true

        # Delete inbox copy after verified
        if (-not $DryRun) {
            Remove-Item $file.FullName -Force
        }
        Write-Host ("  入库: {0} ({1:N0} B)" -f $file.Name, $file.Length)
        $stats.stored++
    }
    catch {
        Write-Host ("  🚨 错误: {0} — {1}" -f $file.Name, $_.Exception.Message)
        $stats.errors++
    }
}

# Write index
if ($newRecords.Count -gt 0 -and -not $DryRun) {
    $newRecords | Add-Content $indexFile -Encoding UTF8
}

# Clean empty dirs in inbox
Get-ChildItem -Path $inbox -Directory -Recurse -ErrorAction SilentlyContinue |
    Where-Object { @(Get-ChildItem $_.FullName -Force).Count -eq 0 } |
    ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

# Report
Write-Host ("")
Write-Host ("-" * 60)
Write-Host ("消化完成")
Write-Host ("  扫描: {0}" -f $stats.scanned)
Write-Host ("  新存: {0}" -f $stats.stored)
Write-Host ("  去重: {0}" -f $stats.deduped)
Write-Host ("  跳过: {0}" -f $stats.skipped)
if ($stats.errors -gt 0) {
    Write-Host ("  🚨 异常: {0}" -f $stats.errors)
}
Write-Host ("=" * 60)

if ($DryRun) { Write-Host "(DryRun 模式，未实际写入)" }

if ($stats.errors -gt 0) { exit 1 } else { exit 0 }
