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
Write-Host ("仓库完整性检查: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Write-Host ("")

# 1. Count index entries
$indexHashes = @{}
if (Test-Path $indexFile) {
    Get-Content $indexFile -Encoding UTF8 | Where-Object { $_ -match '"hash":"(sha256:[a-f0-9]{64})"' } | ForEach-Object {
        if ($_ -match '"hash":"(sha256:[a-f0-9]{64})"') {
            $indexHashes[$matches[1]] = $true
        }
    }
}
$indexCount = $indexHashes.Count
Write-Host ("  index 记录数: {0}" -f $indexCount)

# 2. Count store files
$storeFiles = @()
if (Test-Path $storeDir) {
    $storeFiles = @(Get-ChildItem -Path $storeDir -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^sha256:[a-f0-9]{64}$' })
}
$storeCount = $storeFiles.Count
Write-Host ("  store 文件数: {0}" -f $storeCount)

# 3. Compare counts
if ($indexCount -ne $storeCount) {
    $msg = "数量不一致: index={0} store={1}" -f $indexCount, $storeCount
    Write-Host ("  🚨 {0}" -f $msg)
    $issues += $msg

    # Find missing
    $storeHashes = @{}
    foreach ($f in $storeFiles) { $storeHashes[$f.Name] = $true }
    $inIndexNotStore = $indexHashes.Keys | Where-Object { -not $storeHashes.ContainsKey($_) }
    $inStoreNotIndex = $storeHashes.Keys | Where-Object { -not $indexHashes.ContainsKey($_) }

    if ($inIndexNotStore) {
        Write-Host ("  index 有但 store 无: {0} 个" -f $inIndexNotStore.Count)
        $inIndexNotStore | Select-Object -First 5 | ForEach-Object { Write-Host ("    {0}" -f $_) }
    }
    if ($inStoreNotIndex) {
        Write-Host ("  store 有但 index 无: {0} 个" -f $inStoreNotIndex.Count)
        $inStoreNotIndex | Select-Object -First 5 | ForEach-Object { Write-Host ("    {0}" -f $_) }
    }
} else {
    Write-Host ("  数量一致 ✅")
}

# 4. Spot-check random files
if ($storeFiles.Count -gt 0) {
    Write-Host ("")
    Write-Host ("  随机抽查 {0} 个文件 SHA256..." -f [Math]::Min($SampleSize, $storeFiles.Count))
    $sample = Get-Random -InputObject $storeFiles -Count ([Math]::Min($SampleSize, $storeFiles.Count))

    $passed = 0
    $failed = 0
    foreach ($f in $sample) {
        $computed = "sha256:" + (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLower()
        $expected = $f.Name
        if ($computed -eq $expected) {
            $passed++
        } else {
            $msg = "SHA256 不匹配: {0}" -f $f.Name
            Write-Host ("  🚨 {0}" -f $msg)
            $issues += $msg
            $failed++
        }
    }
    Write-Host ("  抽查: {0} 通过, {1} 失败" -f $passed, $failed)
}

# 5. Report
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$report = @"
[$timestamp] 仓库检查
  index 记录: $indexCount
  store 文件: $storeCount
  抽查: $passed/$SampleSize 通过
  问题: $($issues.Count)
"@
$report | Set-Content $reportFile -Encoding UTF8

if ($issues.Count -gt 0) {
    $attentionContent = @"
# 🚨 仓库异常 — $timestamp

$($issues -join "`n")

详见 `_runtime/check-report.txt`
"@
    $attentionContent | Set-Content $attentionFile -Encoding UTF8
    Write-Host ("")
    Write-Host ("=" * 60)
    Write-Host ("🚨 发现问题 {0} 个，详见 ATTENTION.md" -f $issues.Count)
    exit 1
} else {
    # Remove attention file if everything is clean
    if (Test-Path $attentionFile) {
        Remove-Item $attentionFile -Force
    }
    Write-Host ("")
    Write-Host ("=" * 60)
    Write-Host ("✅ 仓库健康")
    exit 0
}
