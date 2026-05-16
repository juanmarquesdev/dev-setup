#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Dev environment setup — Windows + WSL Arch Linux.
    Orquestra todo o processo: Windows, Arch root e Arch user setup.
    Suporta retomada automática após reboot via Scheduled Task.

.USAGE
    # Execute como Administrador:
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\setup.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─── Estado / Resume ────────────────────────────────────────────────────────
$StateDir  = "$env:APPDATA\dev-setup"
$StateFile = "$StateDir\state.json"
$TaskName  = "DevSetupResume"

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

function Convert-ToUnixLineEndings {
    param([string]$Path)
    Get-ChildItem $Path -Recurse -File | ForEach-Object {
        $content = [System.IO.File]::ReadAllText($_.FullName) -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText($_.FullName, $content,
            (New-Object System.Text.UTF8Encoding $false))
    }
}

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

function Save-State {
    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    $script:State | ConvertTo-Json -Depth 5 | Set-Content $StateFile -Encoding UTF8
}

function Step-Done {
    param([string]$name)
    if ($script:State.Done -notcontains $name) {
        $script:State.Done = @($script:State.Done) + $name
        Save-State
    }
}

function Step-Skip {
    param([string]$name)
    return $script:State.Done -contains $name
}

function Register-ResumeTask {
    # Resolve full path to pwsh.exe so the task works even when PATH is minimal at logon
    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    $pwsh = if ($pwshCmd) { $pwshCmd.Source } else { $null }
    if (-not $pwsh) {
        $pwsh = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
    }
    $scriptDir = Split-Path $script:State.ScriptPath -Parent
    $action    = New-ScheduledTaskAction -Execute $pwsh `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($script:State.ScriptPath)`"" `
        -WorkingDirectory $scriptDir
    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2)
    Register-ScheduledTask -TaskName $TaskName -Action $action `
        -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
}

function Unregister-ResumeTask {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Ask-Reboot {
    param([string]$reason)
    Write-Host ""
    Write-Warn $reason
    Write-Host ""
    $ans = Read-Host "  Deseja reiniciar agora? (s/n)"
    if ($ans -match "^[sS]") {
        Register-ResumeTask
        Write-Ok "Setup agendado para continuar automaticamente após o login"
        Write-Info "Reiniciando em 5 segundos..."
        Start-Sleep 5
        Restart-Computer -Force
        exit
    }
    Write-Warn "Execute o script novamente após reiniciar para continuar"
    exit
}

function Test-RebootPending {
    $keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )
    foreach ($k in $keys) { if (Test-Path $k) { return $true } }
    try {
        $p = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
            -Name "PendingFileRenameOperations" -ErrorAction Stop
        if ($p) { return $true }
    } catch {}
    return $false
}

# ════════════════════════════════════════════════════════════════════════════
#  Carregar estado existente ou perguntar parâmetros
# ════════════════════════════════════════════════════════════════════════════
if (Test-Path $StateFile) {
    # ─── Retomada após reboot ────────────────────────────────────────────────
    Write-Title "Retomando Setup"
    $loaded = Get-Content $StateFile -Raw | ConvertFrom-Json

    $script:State = @{
        ScriptPath = $loaded.ScriptPath
        EncPass    = $loaded.EncPass
        Done       = @($loaded.Done)
        Config     = $loaded.Config
    }

    # Descriptografar senha (DPAPI — só funciona na mesma máquina/usuário)
    $plainPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
                        ($script:State.EncPass | ConvertTo-SecureString)))

    Unregister-ResumeTask

    $Config = $script:State.Config
    Write-Info "Etapas já concluídas: $(if ($script:State.Done) { $script:State.Done -join ', ' } else { '(nenhuma)' })"
    Write-Host ""

} else {
    # ─── Primeira execução: perguntar parâmetros ─────────────────────────────
    Write-Title "Dev Environment Setup"
    Write-Info "Responda as perguntas abaixo para configurar o setup:"
    Write-Host ""

    $in = (Read-Host "  Distro WSL [archlinux]").Trim()
    $wslDistro = if ($in) { $in } else { "archlinux" }

    $wslUser = ""
    while (-not $wslUser) {
        $wslUser = (Read-Host "  Usuário Linux (obrigatório)").Trim()
    }

    $gitName = ""
    while (-not $gitName) {
        $gitName = (Read-Host "  Nome Git (obrigatório)").Trim()
    }

    $gitEmail = ""
    while (-not $gitEmail) {
        $gitEmail = (Read-Host "  Email Git (obrigatório)").Trim()
    }

    $dotfilesRepo = ""
    while (-not $dotfilesRepo) {
        $dotfilesRepo = (Read-Host "  Repositório de dotfiles para clonar (obrigatório)").Trim()
    }

    $in = (Read-Host "  Dotfiles pacotes [zsh git tmux ssh]").Trim()
    $dotfilesPkgs = if ($in) { $in } else { "zsh git tmux ssh" }

    Write-Host ""
    $securePass = Read-Host "  Senha para '$wslUser' no WSL" -AsSecureString
    $plainPass  = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))

    $script:State = @{
        ScriptPath = $PSCommandPath
        EncPass    = ($securePass | ConvertFrom-SecureString)
        Done       = @()
        Config     = [PSCustomObject]@{
            WslDistro    = $wslDistro
            WslUser      = $wslUser
            GitName      = $gitName
            GitEmail     = $gitEmail
            DotfilesRepo = $dotfilesRepo
            DotfilesPkgs = $dotfilesPkgs
        }
    }
    Save-State

    $Config = $script:State.Config

    Write-Host ""
    Write-Info "Distro  : $($Config.WslDistro)"
    Write-Info "Usuário : $($Config.WslUser)"
    Write-Info "Git     : $($Config.GitName) <$($Config.GitEmail)>"
    Write-Info "Dotfiles: $($Config.DotfilesRepo)"
    Write-Host ""
}

# ════════════════════════════════════════════════════════════════════════════
Write-Title "Windows Setup"

# ────────────────────────────────────────────────────────────────────────────
#  1. PowerShell 7
# ────────────────────────────────────────────────────────────────────────────
Write-Step 1 6 "PowerShell 7"
if (Step-Skip "ps7") { Write-Ok "PowerShell 7 — etapa já concluída" }
else {
    Install-WingetPkg "Microsoft.PowerShell" "PowerShell 7"
    Step-Done "ps7"
}

# ────────────────────────────────────────────────────────────────────────────
#  2. CaskaydiaMono Nerd Font
# ────────────────────────────────────────────────────────────────────────────
Write-Step 2 6 "CaskaydiaMono Nerd Font"
if (Step-Skip "font") { Write-Ok "Nerd Font — etapa já concluída" }
else {
    $regFonts   = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    $fontNames  = (Get-ItemProperty $regFonts).PSObject.Properties.Name
    $fontExists = $fontNames -match "CaskaydiaMonoNerdFont"

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

        $shell = New-Object -ComObject Shell.Application
        $fontsFolder = $shell.Namespace(0x14)   # ssfFONTS
        Get-ChildItem $tmpDir -Filter "CaskaydiaMonoNerdFont*.ttf" | ForEach-Object {
            if (-not (Test-Path "$env:WINDIR\Fonts\$($_.Name)")) {
                $fontsFolder.CopyHere($_.FullName, 0x10)
            }
        }
        Remove-Item $tmpZip, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok "Fonte instalada"
    }
    Step-Done "font"
}

# ────────────────────────────────────────────────────────────────────────────
#  3a. WSL — habilitar features Windows
# ────────────────────────────────────────────────────────────────────────────
Write-Step 3 7 "WSL — features Windows"
if (Step-Skip "wsl-features") { Write-Ok "WSL features — etapa já concluída" }
else {
    try {
        $wslStatus = wsl --status 2>&1
        $featuresEnabled = ($LASTEXITCODE -eq 0) -and
                           ($wslStatus -match "Versão padrão" -or $wslStatus -match "Default Version" -or $wslStatus -match "WSL 2")
    } catch {
        $featuresEnabled = $false
    }

    if ($featuresEnabled) {
        Write-Ok "Features WSL já habilitadas"
    } else {
        Write-Info "Habilitando features WSL (VirtualMachinePlatform + WSL)..."
        wsl --install --no-distribution
        # wsl --install --no-distribution usa DISM/CBS, que escreve em
        # Component Based Servicing\RebootPending quando é a primeira vez.
        Write-Ok "Features habilitadas"
    }
    Step-Done "wsl-features"

    # Verificar reboot via CBS (funciona porque DISM escreve nessa chave)
    if (Test-RebootPending) {
        Ask-Reboot "As features do WSL foram habilitadas e requerem reinicialização para continuar."
    }
}

# ────────────────────────────────────────────────────────────────────────────
#  3b. WSL — instalar distro
# ────────────────────────────────────────────────────────────────────────────
Write-Step 4 7 "WSL — instalar $($Config.WslDistro)"
if (Step-Skip "wsl-distro") { Write-Ok "Distro WSL — etapa já concluída" }
else {
    $distros = wsl --list --quiet 2>&1
    if ($distros -match $Config.WslDistro) {
        Write-Ok "$($Config.WslDistro) já instalado"
    } else {
        Write-Info "Instalando $($Config.WslDistro)..."
        wsl --install $Config.WslDistro --no-launch
        # Instalar distro não exige reboot do Windows — é apenas extração de tarball
        Write-Ok "$($Config.WslDistro) instalado"
    }
    Step-Done "wsl-distro"
}

# ────────────────────────────────────────────────────────────────────────────
#  5. npiperelay (SSH bridge)
# ────────────────────────────────────────────────────────────────────────────
Write-Step 5 7 "npiperelay"
if (Step-Skip "npipe") { Write-Ok "npiperelay — etapa já concluída" }
else {
    Install-WingetPkg "albertony.npiperelay" "npiperelay"

    $npipe = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\albertony.npiperelay*" `
        -Recurse -Filter "npiperelay.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($npipe) {
        Copy-Item $npipe.FullName "$env:LOCALAPPDATA\Microsoft\WindowsApps\npiperelay.exe" -Force
        Write-Ok "npiperelay copiado para WindowsApps"
    } else {
        Write-Warn "npiperelay.exe não localizado — copie manualmente para %LOCALAPPDATA%\Microsoft\WindowsApps\"
    }
    Step-Done "npipe"
}

# ────────────────────────────────────────────────────────────────────────────
#  6. SSH Agent do Windows (desativar — Bitwarden vai assumir)
# ────────────────────────────────────────────────────────────────────────────
Write-Step 6 7 "Desativando Windows ssh-agent"
if (Step-Skip "sshagent") { Write-Ok "ssh-agent — etapa já concluída" }
else {
    $svc = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -eq "Running") { Stop-Service "ssh-agent" -Force }
        Set-Service "ssh-agent" -StartupType Disabled
        Write-Ok "ssh-agent desativado"
    } else {
        Write-Ok "ssh-agent não encontrado (ok)"
    }
    Step-Done "sshagent"
}

# ────────────────────────────────────────────────────────────────────────────
#  7. Desabilitar pesquisa web do menu Iniciar
# ────────────────────────────────────────────────────────────────────────────
Write-Step 7 8 "Desabilitar pesquisa web do menu Iniciar"
if (Step-Skip "bingsearch") { Write-Ok "Pesquisa web do menu Iniciar — etapa já concluída" }
else {
    reg add HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search /V BingSearchEnabled /T REG_DWORD /D 0 /F | Out-Null
    Write-Ok "Pesquisa web do menu Iniciar desabilitada"
    Step-Done "bingsearch"
}

# ────────────────────────────────────────────────────────────────────────────
#  8. Windows Terminal — Catppuccin Mocha
# ────────────────────────────────────────────────────────────────────────────
Write-Step 8 8 "Windows Terminal — Catppuccin Mocha"
if (Step-Skip "terminal") { Write-Ok "Windows Terminal — etapa já concluída" }
else {
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
            $_.name -match "arch" -or
            ($_.PSObject.Properties['source'] -and $_.source -match "arch")
        } | Select-Object -First 1

        if ($archProfile) {
            $archProfile | Add-Member -NotePropertyName "colorScheme"              -NotePropertyValue "Catppuccin Mocha" -Force
            $archProfile | Add-Member -NotePropertyName "suppressApplicationTitle" -NotePropertyValue $true -Force
            $archProfile | Add-Member -NotePropertyName "tabTitle"                 -NotePropertyValue "Arch" -Force
            $archProfile | Add-Member -NotePropertyName "opacity"                  -NotePropertyValue 95 -Force

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
    Step-Done "terminal"
}

# ════════════════════════════════════════════════════════════════════════════
#  Arch Linux — Root Setup
# ════════════════════════════════════════════════════════════════════════════
Write-Title "Arch Linux — Root Setup"

if (Step-Skip "arch-root") { Write-Ok "Root setup — etapa já concluída" }
else {
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
    Convert-ToUnixLineEndings $tmpSetup

    Write-Info "Executando 01-root.sh em $($Config.WslDistro)..."
    Write-Host ""

    wsl -d $Config.WslDistro -u root -- bash "$wslTmpPath/01-root.sh" "$wslTmpPath"

    Write-Host ""
    Write-Info "Reiniciando WSL..."
    wsl --shutdown
    Start-Sleep -Seconds 3

    Step-Done "arch-root"
}

# ════════════════════════════════════════════════════════════════════════════
#  Arch Linux — User Setup
# ════════════════════════════════════════════════════════════════════════════
Write-Title "Arch Linux — User Setup"

if (Step-Skip "arch-user") { Write-Ok "User setup — etapa já concluída" }
else {
    $tmpSetup   = "$env:TEMP\dev-setup"
    $wslTmpPath = "/mnt/c" + ($tmpSetup.Substring(2) -replace "\\", "/")

    # Regenerar config.env caso o tmp tenha sido limpo
    if (-not (Test-Path "$tmpSetup\config.env")) {
        New-Item -ItemType Directory -Path $tmpSetup -Force | Out-Null
        Copy-Item "$PSScriptRoot\arch\*" $tmpSetup -Recurse -Force
        $configEnv = @"
SETUP_USER="$($Config.WslUser)"
SETUP_USER_PASS="$plainPass"
SETUP_GIT_NAME="$($Config.GitName)"
SETUP_GIT_EMAIL="$($Config.GitEmail)"
SETUP_DOTFILES_REPO="$($Config.DotfilesRepo)"
SETUP_DOTFILES_PKGS="$($Config.DotfilesPkgs)"
"@
        Set-Content "$tmpSetup\config.env" -Value $configEnv -Encoding UTF8 -NoNewline
        Convert-ToUnixLineEndings $tmpSetup
    }

    Write-Host ""
    Write-Warn "AÇÃO NECESSÁRIA antes de continuar:"
    Write-Host "  1. Abra o Bitwarden Desktop e desbloqueie o cofre" -ForegroundColor White
    Write-Host "  2. Confirme que Settings → SSH Agent está habilitado" -ForegroundColor White
    Write-Host "  3. Num terminal WSL separado, inicie o socket manualmente:" -ForegroundColor White
    Write-Host ""
    Write-Host "       export SSH_AUTH_SOCK=`$HOME/.ssh/agent.sock" -ForegroundColor Cyan
    Write-Host "       rm -f `$SSH_AUTH_SOCK" -ForegroundColor Cyan
    Write-Host "       NPIPERELAY=`$(wslpath -u `"`$(cmd.exe /c 'where npiperelay.exe' 2>/dev/null | tr -d '\r')`")" -ForegroundColor Cyan
    Write-Host "       setsid socat UNIX-LISTEN:`$SSH_AUTH_SOCK,fork EXEC:`"`"`$NPIPERELAY`" -ei -s //./pipe/openssh-ssh-agent`" &" -ForegroundColor Cyan
    Write-Host "       sleep 1 && ssh-add -l" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Sem o socket ativo o clone dos dotfiles irá travar." -ForegroundColor Gray
    Write-Host ""
    Read-Host "  Pressione Enter quando o socket estiver rodando"
    Write-Host ""

    Write-Info "Executando 02-user.sh como '$($Config.WslUser)'..."
    Write-Host ""

    wsl -d $Config.WslDistro -u $Config.WslUser -- bash "$wslTmpPath/02-user.sh" "$wslTmpPath"

    # Limpar arquivos temporários (contém senha)
    Remove-Item $tmpSetup -Recurse -Force -ErrorAction SilentlyContinue

    Step-Done "arch-user"
}

# ─── Limpeza do estado ───────────────────────────────────────────────────────
Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
Remove-Item $StateDir  -Force -ErrorAction SilentlyContinue
Unregister-ResumeTask

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
