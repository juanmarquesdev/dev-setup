#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Dev environment setup — Windows + WSL Arch Linux.
    Orquestra todo o processo: Windows, Arch root e Arch user setup.

.USAGE
    # Execute como Administrador:
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\setup.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ════════════════════════════════════════════════════════════════════════════
#  CONFIGURAÇÃO — edite antes de executar
# ════════════════════════════════════════════════════════════════════════════
$Config = @{
    WslDistro      = "archlinux"
    WslUser        = "jrbmx"
    GitName        = "juanmarquesdev"
    GitEmail       = "juanbatistamarques+github@gmail.com"
    DotfilesRepo   = "git@github.com:juanmarquesdev/dotfiles.git"
    DotfilesPkgs   = "zsh git tmux ssh"
}
# ════════════════════════════════════════════════════════════════════════════

# ─── Helpers ────────────────────────────────────────────────────────────────
function Write-Title {
    param($text)
    $pad = "═" * ($text.Length + 4)
    Write-Host ""
    Write-Host "  ╔$pad╗" -ForegroundColor Magenta
    Write-Host "  ║  $text  ║" -ForegroundColor Magenta
    Write-Host "  ╚$pad╝" -ForegroundColor Magenta
    Write-Host ""
}

function Write-Step  { param($n, $total, $msg) Write-Host "  [$n/$total] $msg" -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host "  ✔  $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "  ⚠  $msg" -ForegroundColor Yellow }
function Write-Info  { param($msg) Write-Host "     $msg" -ForegroundColor Gray }
function Write-Pause { param($msg) Write-Host "`n  ⏸  $msg" -ForegroundColor Yellow; Read-Host "     Pressione Enter para continuar" }

function Test-WingetPkg {
    param($id)
    $out = winget list --id $id --exact 2>&1
    return ($LASTEXITCODE -eq 0) -and ($out -match [regex]::Escape($id))
}

function Install-WingetPkg {
    param($id, $name)
    if (Test-WingetPkg $id) {
        Write-Ok "$name já instalado"
        return
    }
    Write-Info "Instalando $name..."
    winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
    Write-Ok "$name instalado"
}

# ════════════════════════════════════════════════════════════════════════════
Write-Title "Dev Environment Setup"
Write-Info "Distro  : $($Config.WslDistro)"
Write-Info "Usuário : $($Config.WslUser)"
Write-Info "Git     : $($Config.GitName) <$($Config.GitEmail)>"
Write-Info "Dotfiles: $($Config.DotfilesRepo)"
Write-Host ""

# Senha do usuário WSL
$securePass = Read-Host "  Senha para o usuário '$($Config.WslUser)' no WSL" -AsSecureString
$plainPass  = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))

Write-Host ""

# ────────────────────────────────────────────────────────────────────────────
#  1. PowerShell 7
# ────────────────────────────────────────────────────────────────────────────
Write-Step 1 6 "PowerShell 7"
Install-WingetPkg "Microsoft.PowerShell" "PowerShell 7"

# ────────────────────────────────────────────────────────────────────────────
#  2. CaskaydiaMono Nerd Font
# ────────────────────────────────────────────────────────────────────────────
Write-Step 2 6 "CaskaydiaMono Nerd Font"

$regFonts   = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
$fontNames  = (Get-ItemProperty $regFonts).PSObject.Properties.Name
$fontExists = $fontNames -match "CaskaydiaMono"

if ($fontExists) {
    Write-Ok "CaskaydiaMono Nerd Font já instalada"
} else {
    $tmpZip = "$env:TEMP\CascadiaMono.zip"
    $tmpDir = "$env:TEMP\CascadiaMono"
    Write-Info "Baixando fonte..."
    Invoke-WebRequest -Uri "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip" `
        -OutFile $tmpZip -UseBasicParsing
    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
    Expand-Archive $tmpZip -DestinationPath $tmpDir

    $fontsFolder = "$env:WINDIR\Fonts"
    Get-ChildItem $tmpDir -Filter "*NF*.ttf" | ForEach-Object {
        Copy-Item $_.FullName $fontsFolder -Force
        New-ItemProperty -Path $regFonts -Name "$($_.BaseName) (TrueType)" `
            -Value $_.Name -PropertyType String -Force | Out-Null
    }
    Remove-Item $tmpZip, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "Fonte instalada"
}

# ────────────────────────────────────────────────────────────────────────────
#  3. WSL + Arch Linux
# ────────────────────────────────────────────────────────────────────────────
Write-Step 3 6 "WSL + Arch Linux"

$distros = wsl --list --quiet 2>&1
if ($distros -match $Config.WslDistro) {
    Write-Ok "Arch Linux já instalado"
} else {
    Write-Info "Instalando WSL e Arch Linux..."
    wsl --install --no-distribution
    wsl --install $Config.WslDistro
    Write-Ok "Arch Linux instalado"
    Write-Warn "Se for a primeira instalação do WSL, pode ser necessário reiniciar o PC"
    Write-Pause "Reinicie se solicitado e execute o script novamente"
}

# ────────────────────────────────────────────────────────────────────────────
#  4. npiperelay (SSH bridge)
# ────────────────────────────────────────────────────────────────────────────
Write-Step 4 6 "npiperelay"
Install-WingetPkg "albertony.npiperelay" "npiperelay"

$npipe = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\albertony.npiperelay*" `
    -Recurse -Filter "npiperelay.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($npipe) {
    Copy-Item $npipe.FullName "$env:LOCALAPPDATA\Microsoft\WindowsApps\npiperelay.exe" -Force
    Write-Ok "npiperelay copiado para WindowsApps"
} else {
    Write-Warn "npiperelay.exe não localizado — copie manualmente para %LOCALAPPDATA%\Microsoft\WindowsApps\"
}

# ────────────────────────────────────────────────────────────────────────────
#  5. SSH Agent do Windows (desativar — Bitwarden vai assumir)
# ────────────────────────────────────────────────────────────────────────────
Write-Step 5 6 "Desativando Windows ssh-agent"

$svc = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -eq "Running") { Stop-Service "ssh-agent" -Force }
    Set-Service "ssh-agent" -StartupType Disabled
    Write-Ok "ssh-agent desativado"
} else {
    Write-Ok "ssh-agent não encontrado (ok)"
}

# ────────────────────────────────────────────────────────────────────────────
#  6. Windows Terminal — Catppuccin Mocha
# ────────────────────────────────────────────────────────────────────────────
Write-Step 6 6 "Windows Terminal — Catppuccin Mocha"

$wtPaths = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)
$settingsPath = $wtPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $settingsPath) {
    Write-Warn "settings.json do Windows Terminal não encontrado — configure manualmente"
} else {
    $json = Get-Content $settingsPath -Raw | ConvertFrom-Json

    # Adicionar esquema Catppuccin Mocha
    $scheme = [PSCustomObject]@{
        name              = "Catppuccin Mocha"
        background        = "#1E1E2E"; foreground   = "#CDD6F4"
        cursorColor       = "#F5E0DC"; selectionBackground = "#585B70"
        black             = "#45475A"; brightBlack  = "#585B70"
        red               = "#F38BA8"; brightRed    = "#F38BA8"
        green             = "#A6E3A1"; brightGreen  = "#A6E3A1"
        yellow            = "#F9E2AF"; brightYellow = "#F9E2AF"
        blue              = "#89B4FA"; brightBlue   = "#89B4FA"
        purple            = "#F5C2E7"; brightPurple = "#F5C2E7"
        cyan              = "#94E2D5"; brightCyan   = "#94E2D5"
        white             = "#BAC2DE"; brightWhite  = "#A6ADC8"
    }

    if (-not ($json.schemes | Where-Object { $_.name -eq "Catppuccin Mocha" })) {
        $json.schemes += $scheme
        Write-Info "Esquema Catppuccin Mocha adicionado"
    }

    # Atualizar perfil Arch
    $archProfile = $json.profiles.list | Where-Object {
        $_.name -match "arch" -or $_.source -match "arch"
    } | Select-Object -First 1

    if ($archProfile) {
        $archProfile | Add-Member -NotePropertyName "colorScheme"           -NotePropertyValue "Catppuccin Mocha" -Force
        $archProfile | Add-Member -NotePropertyName "suppressApplicationTitle" -NotePropertyValue $true -Force
        $archProfile | Add-Member -NotePropertyName "tabTitle"              -NotePropertyValue "Arch" -Force
        $archProfile | Add-Member -NotePropertyName "opacity"               -NotePropertyValue 95 -Force

        if (-not $archProfile.PSObject.Properties["font"]) {
            $archProfile | Add-Member -NotePropertyName "font" -NotePropertyValue ([PSCustomObject]@{ face = "CaskaydiaMono Nerd Font" }) -Force
        } else {
            $archProfile.font | Add-Member -NotePropertyName "face" -NotePropertyValue "CaskaydiaMono Nerd Font" -Force
        }
        Write-Info "Perfil Arch atualizado"
    } else {
        Write-Warn "Perfil Arch não encontrado no Terminal — abra o Arch uma vez e execute: .\fix-terminal.ps1"
    }

    # Backup + salvar
    Copy-Item $settingsPath "$settingsPath.bak" -Force
    $json | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8
    Write-Ok "Windows Terminal configurado"
}

# ════════════════════════════════════════════════════════════════════════════
#  Arch Linux — Root Setup
# ════════════════════════════════════════════════════════════════════════════
Write-Title "Arch Linux — Root Setup"

# Copiar scripts para diretório acessível pelo WSL
$tmpSetup   = "$env:TEMP\dev-setup"
$wslTmpPath = "/mnt/c" + ($tmpSetup.Substring(2) -replace "\\", "/")

New-Item -ItemType Directory -Path $tmpSetup -Force | Out-Null
Copy-Item "$PSScriptRoot\arch\*" $tmpSetup -Recurse -Force

# Gerar config.env para os scripts Arch
$configEnv = @"
SETUP_USER="$($Config.WslUser)"
SETUP_USER_PASS="$plainPass"
SETUP_GIT_NAME="$($Config.GitName)"
SETUP_GIT_EMAIL="$($Config.GitEmail)"
SETUP_DOTFILES_REPO="$($Config.DotfilesRepo)"
SETUP_DOTFILES_PKGS="$($Config.DotfilesPkgs)"
"@
Set-Content "$tmpSetup\config.env" -Value $configEnv -Encoding UTF8 -NoNewline

Write-Info "Executando 01-root.sh em $($Config.WslDistro)..."
Write-Host ""

wsl -d $Config.WslDistro -u root -- bash "$wslTmpPath/01-root.sh" "$wslTmpPath"

Write-Host ""
Write-Info "Reiniciando WSL..."
wsl --shutdown
Start-Sleep -Seconds 3

# ════════════════════════════════════════════════════════════════════════════
#  Arch Linux — User Setup
# ════════════════════════════════════════════════════════════════════════════
Write-Title "Arch Linux — User Setup"
Write-Info "Executando 02-user.sh como '$($Config.WslUser)'..."
Write-Host ""

wsl -d $Config.WslDistro -u $Config.WslUser -- bash "$wslTmpPath/02-user.sh" "$wslTmpPath"

# Limpar arquivos temporários (contém senha)
Remove-Item $tmpSetup -Recurse -Force -ErrorAction SilentlyContinue

# ════════════════════════════════════════════════════════════════════════════
Write-Title "Setup Concluído!"

Write-Host "  Passos manuais restantes:`n" -ForegroundColor White

Write-Host "  1. Bitwarden SSH Agent" -ForegroundColor Yellow
Write-Host "     Bitwarden Desktop → Settings → SSH Agent → Enable`n" -ForegroundColor Gray

Write-Host "  2. Powerlevel10k wizard" -ForegroundColor Yellow
Write-Host "     Abra o Arch no Windows Terminal e execute: p10k configure`n" -ForegroundColor Gray

Write-Host "  3. Chave de assinatura no GitHub" -ForegroundColor Yellow
Write-Host "     github.com/settings/keys → New SSH key → Signing Key" -ForegroundColor Gray
Write-Host "     Cole a chave: ~/.ssh/pessoal.pub`n" -ForegroundColor Gray

Write-Host "  ════════════════════════════════════════════════`n" -ForegroundColor Magenta
