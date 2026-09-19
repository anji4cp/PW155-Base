[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Read-Default {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$Default
    )
    $answer = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}

function Test-TcpPort {
    param([string]$Address, [int]$Port)
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $pending = $client.BeginConnect($Address, $Port, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne(3000)) { return $false }
        $client.EndConnect($pending)
        return $client.Connected
    }
    catch { return $false }
    finally { $client.Dispose() }
}

function Test-PackageChecksums {
    $checksumFile = Join-Path $PSScriptRoot 'SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $checksumFile)) {
        throw "Daftar checksum tidak ditemukan: $checksumFile"
    }
    Write-Host 'Memeriksa keutuhan ISO, arsip, skema, dan library...' -ForegroundColor Yellow
    foreach ($line in Get-Content -LiteralPath $checksumFile) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^([0-9a-fA-F]{64})\s{2}(.+)$') {
            throw "Format checksum tidak valid: $line"
        }
        $expected = $Matches[1].ToLowerInvariant()
        $relative = $Matches[2] -replace '/', [IO.Path]::DirectorySeparatorChar
        $path = Join-Path $PSScriptRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "File checksum tidak ditemukan: $relative"
        }
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        if ($actual -ne $expected) {
            throw "Checksum tidak cocok: $relative"
        }
        Write-Host "  OK $relative" -ForegroundColor DarkGreen
    }
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '  INSTALLER OTOMATIS PERFECT WORLD 1.5.5 + PANEL WEB' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Ubuntu harus sudah selesai dipasang dan OpenSSH harus aktif.'
Write-Host 'Password tidak disimpan oleh skrip Windows ini.'
Write-Host ''

$targetAddress = Read-Default -Prompt 'Alamat server SSH' -Default '127.0.0.1'
$sshPortText = Read-Default -Prompt 'Port SSH' -Default '2223'
$sshUser = Read-Default -Prompt 'Username Ubuntu' -Default 'pwadmin'

$sshPort = 0
if (-not [int]::TryParse($sshPortText, [ref]$sshPort) -or $sshPort -lt 1 -or $sshPort -gt 65535) {
    throw 'Port SSH tidak valid.'
}

$ssh = (Get-Command ssh.exe -ErrorAction SilentlyContinue).Source
$scp = (Get-Command scp.exe -ErrorAction SilentlyContinue).Source
if (-not $ssh -or -not $scp) {
    throw 'OpenSSH Client Windows tidak ditemukan. Aktifkan Windows Optional Feature: OpenSSH Client.'
}

if (-not (Test-TcpPort -Address $targetAddress -Port $sshPort)) {
    throw "SSH $targetAddress`:$sshPort belum dapat dijangkau. Pastikan VM hidup, OpenSSH aktif, dan jaringan bridge atau port forwarding sesuai."
}

$requiredItems = @(
    (Join-Path $PSScriptRoot 'install-pw155.sh'),
    (Join-Path $PSScriptRoot 'Perfect_World_Server_1.5.5.tar.gz'),
    (Join-Path $PSScriptRoot 'web.tar.gz'),
    (Join-Path $PSScriptRoot 'client-data.tar.gz'),
    (Join-Path $PSScriptRoot 'ubuntu-debs-20.04.tar.gz'),
    (Join-Path $PSScriptRoot 'support')
)
foreach ($item in $requiredItems) {
    if (-not (Test-Path -LiteralPath $item)) {
        throw "File paket tidak ditemukan: $item"
    }
}

Test-PackageChecksums

Write-Host ''
Write-Host 'Tahap 1/2 - Mengirim paket ke Ubuntu (sekitar 1,4 GB)...' -ForegroundColor Yellow
Write-Host 'Masukkan password Ubuntu saat diminta.' -ForegroundColor DarkYellow
& $scp -r -P $sshPort @requiredItems "${sshUser}@${targetAddress}:/home/${sshUser}/"
if ($LASTEXITCODE -ne 0) { throw "Pengiriman file gagal, kode $LASTEXITCODE." }

Write-Host ''
Write-Host 'Tahap 2/2 - Menjalankan pemasangan di Ubuntu...' -ForegroundColor Yellow
Write-Host 'Password Ubuntu mungkin diminta lagi untuk SSH dan sudo.' -ForegroundColor DarkYellow
$remoteCommand = "sudo bash /home/$sshUser/install-pw155.sh"
& $ssh -tt -p $sshPort "${sshUser}@${targetAddress}" $remoteCommand
if ($LASTEXITCODE -ne 0) { throw "Instalasi Ubuntu gagal, kode $LASTEXITCODE." }

Write-Host ''
Write-Host 'SELESAI.' -ForegroundColor Green
if ($targetAddress -eq '127.0.0.1' -and $sshPort -eq 2223) {
    Write-Host 'Panel web : http://127.0.0.1:8081 (VirtualBox NAT sesuai tutorial)'
    Write-Host 'Port game : 127.0.0.1:29001'
} else {
    Write-Host "Panel web VM : http://${targetAddress}:8080"
    Write-Host "Port game VM : ${targetAddress}:29000"
}
Write-Host 'Admin     : admin'
Write-Host 'Password  : lihat output instalasi Ubuntu di atas (acak pada instalasi baru)'
Write-Host 'Ganti password admin setelah login pertama.' -ForegroundColor Yellow
