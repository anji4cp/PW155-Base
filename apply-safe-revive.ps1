[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Read-Default {
    param([string]$Prompt, [string]$Default)
    $answer = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}

$server = Read-Default -Prompt 'Alamat server SSH' -Default '192.168.30.10'
$portText = Read-Default -Prompt 'Port SSH' -Default '22'
$user = Read-Default -Prompt 'Username Ubuntu' -Default 'pwadmin'
$port = 0
if (-not [int]::TryParse($portText, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
    throw 'Port SSH tidak valid.'
}

$helper = Join-Path $PSScriptRoot 'support\pw155-configure-safe-revive.sh'
if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) {
    throw "Helper tidak ditemukan: $helper"
}

$ssh = (Get-Command ssh.exe -ErrorAction SilentlyContinue).Source
$scp = (Get-Command scp.exe -ErrorAction SilentlyContinue).Source
if (-not $ssh -or -not $scp) {
    throw 'OpenSSH Client Windows tidak ditemukan.'
}

Write-Host 'Perubahan akan me-restart World Utama dan memutus karakter yang sedang online.' -ForegroundColor Yellow
$confirm = Read-Host 'Ketik LANJUT untuk menerapkan'
if ($confirm -cne 'LANJUT') {
    Write-Host 'Dibatalkan; server tidak diubah.'
    exit 0
}

Write-Host 'Mengirim helper. Password SSH mungkin diminta.' -ForegroundColor Cyan
& $scp -P $port $helper "${user}@${server}:/home/${user}/pw155-configure-safe-revive.sh"
if ($LASTEXITCODE -ne 0) { throw "Pengiriman helper gagal, kode $LASTEXITCODE." }

$remote = @(
    "sudo install -m 0755 /home/$user/pw155-configure-safe-revive.sh /srv/pw155/tools/pw155-configure-safe-revive.sh"
    'sudo /srv/pw155/tools/pw155-configure-safe-revive.sh --apply'
    'sudo /srv/pw155/tools/pw155-service.sh stop-map gs01'
    'sudo /srv/pw155/tools/pw155-service.sh start-map gs01'
    'sudo /srv/pw155/tools/pw155-configure-safe-revive.sh --check'
) -join ' && '

Write-Host 'Menerapkan konfigurasi dan me-restart World Utama.' -ForegroundColor Cyan
& $ssh -tt -p $port "${user}@${server}" $remote
if ($LASTEXITCODE -ne 0) { throw "Penerapan gagal, kode $LASTEXITCODE." }

Write-Host 'Safe Revive aktif. Uji mati/respawn setelah login ulang.' -ForegroundColor Green
