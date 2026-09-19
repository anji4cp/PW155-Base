[CmdletBinding()]
param(
    [string]$HostName = '127.0.0.1',
    [ValidateRange(1, 65535)][int]$Port = 2223,
    [string]$UserName = 'pwadmin',
    [string]$EditorDirectory
)

$ErrorActionPreference = 'Stop'
$packageRoot = $PSScriptRoot
$workspaceRoot = Split-Path -Parent $packageRoot
if ([string]::IsNullOrWhiteSpace($EditorDirectory)) {
    $EditorDirectory = Join-Path $workspaceRoot 'Universal-Data-Editor-Rollback'
}
$editorExe = Join-Path $EditorDirectory 'Universal data Editor.exe'
$serverSetup = Join-Path $packageRoot 'support\pw155-enable-universal-editor.sh'
$deployHelper = Join-Path $packageRoot 'support\pw155-ude-deploy'
if (-not (Test-Path -LiteralPath $editorExe)) { throw "Universal Data Studio tidak ditemukan: $editorExe" }
if (-not (Test-Path -LiteralPath $serverSetup)) { throw "Script server tidak ditemukan: $serverSetup" }
if (-not (Test-Path -LiteralPath $deployHelper)) { throw "Helper rollback tidak ditemukan: $deployHelper" }

function Find-PuttyTool([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $candidate = Join-Path $root "PuTTY\$Name"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw "$Name tidak ditemukan. Pasang PuTTY untuk Windows terlebih dahulu."
}

$sshDirectory = Join-Path $EditorDirectory 'ssh'
New-Item -ItemType Directory -Force -Path $sshDirectory | Out-Null
Copy-Item -LiteralPath (Find-PuttyTool 'putty.exe') -Destination (Join-Path $sshDirectory 'putty.exe') -Force
Copy-Item -LiteralPath (Find-PuttyTool 'pscp.exe') -Destination (Join-Path $sshDirectory 'pscp.exe') -Force
Copy-Item -LiteralPath (Find-PuttyTool 'plink.exe') -Destination (Join-Path $sshDirectory 'plink.exe') -Force
Set-Content -LiteralPath (Join-Path $sshDirectory 'restart.txt') -Encoding ascii -Value 'sudo /srv/pw155/tools/pw155-ude-deploy restart'
Set-Content -LiteralPath (Join-Path $sshDirectory 'custom.txt') -Encoding ascii -Value 'sudo /srv/pw155/tools/pw155-ude-deploy status'

Write-Host "Menyiapkan server $UserName@$HostName`:$Port..." -ForegroundColor Cyan
Write-Host 'Masukkan password Ubuntu saat SSH/sudo meminta. Password tidak disimpan.'
& scp.exe -P $Port $serverSetup $deployHelper "$UserName@$HostName`:/tmp/"
if ($LASTEXITCODE -ne 0) { throw "Upload script gagal dengan exit code $LASTEXITCODE." }
& ssh.exe -tt -p $Port "$UserName@$HostName" "sudo /bin/bash /tmp/pw155-enable-universal-editor.sh '$UserName' /tmp/pw155-ude-deploy; rm -f /tmp/pw155-enable-universal-editor.sh /tmp/pw155-ude-deploy"
if ($LASTEXITCODE -ne 0) { throw "Setup server gagal dengan exit code $LASTEXITCODE." }

Write-Host ''
Write-Host 'SETUP UNIVERSAL DATA STUDIO SELESAI' -ForegroundColor Green
Write-Host "Editor: $editorExe"
Write-Host 'Buka Server > Settings > Server, lalu isi 127.0.0.1, port 2223, user pwadmin.'
