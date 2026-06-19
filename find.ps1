param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Keyword
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$indexFile = Join-Path $root "index.jsonl"

if (-not (Test-Path $indexFile)) {
    Write-Host "index.jsonl 不存在，仓库尚未入库任何文件。"
    exit 0
}

$lines = Get-Content $indexFile -Encoding UTF8 | Where-Object { $_ -match $Keyword }

if (-not $lines -or $lines.Count -eq 0) {
    Write-Host "未找到匹配 '$Keyword' 的记录。"
    exit 0
}

Write-Host ("匹配 {0} 条记录:" -f $lines.Count)
Write-Host ("-" * 80)

foreach ($line in $lines) {
    try {
        $obj = $line | ConvertFrom-Json
        Write-Host ("{0} | {1} | {2:N0} B | {3} | {4}" -f
            $obj.hash,
            $obj.path,
            $obj.size,
            $obj.inbox_at,
            $obj.ext)
    }
    catch {
        Write-Host $line
    }
}

Write-Host ("-" * 80)
Write-Host ("共 {0} 条" -f $lines.Count)
