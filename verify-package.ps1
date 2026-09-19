[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$checksumFile = Join-Path $PSScriptRoot 'SHA256SUMS.txt'

Write-Host 'Memeriksa paket PWKU...' -ForegroundColor Cyan
foreach ($line in Get-Content -LiteralPath $checksumFile) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
    if ($line -notmatch '^([0-9a-fA-F]{64})\s{2}(.+)$') {
        throw "Format checksum tidak valid: $line"
    }
    $expected = $Matches[1].ToLowerInvariant()
    $relative = $Matches[2] -replace '/', [IO.Path]::DirectorySeparatorChar
    $path = Join-Path $PSScriptRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "HILANG: $relative"
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "RUSAK/BERUBAH: $relative"
    }
    Write-Host "OK  $relative" -ForegroundColor Green
}

Write-Host ''
Write-Host 'Semua file utama utuh.' -ForegroundColor Green
