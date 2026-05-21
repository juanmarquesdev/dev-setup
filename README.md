# Dev Setup

Automatiza a configuração de um ambiente de desenvolvimento completo em Windows + WSL Arch Linux.

## O que este projeto configura

### Windows
- PowerShell 7
- CaskaydiaMono Nerd Font
- WSL (features + distro Arch Linux)
- `npiperelay` para ponte SSH do Bitwarden para o WSL
- serviço `ssh-agent` do Windows desativado
- pesquisa web do menu Iniciar desabilitada via `BingSearchEnabled=0`
- Windows Terminal com esquema Catppuccin Mocha no perfil Arch

### Arch Linux (WSL)
- setup inicial como root (`01-root.sh`):
    - usuário com `wheel` + sudo sem senha
    - `/etc/wsl.conf` com `systemd=true` e usuário padrão
    - locale `en_US.UTF-8`
- setup como usuário (`02-user.sh`):
    - `paru` (AUR helper)
    - pacotes CLI: `zsh`, `fzf`, `ripgrep`, `fd`, `bat`, `eza`, `tmux`, `htop`, `socat`, `openssh`, `stow`
    - `docker`, `docker-compose` e `asdf-vm` (AUR)
    - oh-my-zsh + Powerlevel10k + plugins
    - clone e aplicação de dotfiles com GNU Stow
    - git global + assinatura SSH (quando `~/.ssh/pessoal.pub` existir)

## Como usar

### Pré-requisitos
- Windows 10/11
- `winget` habilitado
- Bitwarden Desktop instalado e logado
- chaves SSH disponíveis no Bitwarden

### 1. Clonar o repositório

```powershell
git clone https://github.com/juanmarquesdev/dev-setup
cd dev-setup
```

### 2. Executar o setup

```powershell
# Execute no PowerShell como Administrador
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup.ps1
```

### 3. Informar os parâmetros no assistente interativo

Na primeira execução, o script pergunta:
- distro WSL (default: `archlinux`)
- usuário Linux
- nome e email do Git
- repositório de dotfiles para clonar (obrigatório)
- pacotes do stow
- senha do usuário Linux

O estado é salvo em `%APPDATA%\dev-setup\state.json` para retomada automática após reboot.

## Fluxo de execução

1. Configuração de Windows (PowerShell, fonte, WSL, npiperelay, search web do Iniciar desabilitada, Terminal)
2. Execução de `arch/01-root.sh` como root no Arch
3. Reinício do WSL quando necessário
4. Execução de `arch/02-user.sh` como usuário comum
5. Ajustes finais (shell padrão, git e signing)

## Passos manuais após o setup

1. Bitwarden: habilitar `Settings -> SSH Agent -> Enable`.
2. Powerlevel10k: executar `p10k configure` no terminal Arch.
3. GitHub Signing Key: adicionar sua chave pública em https://github.com/settings/keys como `Signing Key`.
4. Grupo docker: se o usuário foi adicionado ao grupo durante o setup, reiniciar a sessão do WSL.

## Estrutura

```text
dev-setup/
|-- setup.ps1
`-- arch/
        |-- 01-root.sh
        `-- 02-user.sh
```

## Notas técnicas

### Resume após reboot
O `setup.ps1` cria uma Scheduled Task (`DevSetupResume`) no Windows para retomar automaticamente depois do login quando houver reinicialização no meio do processo.

### Ponte SSH Bitwarden -> WSL
A integração usa `npiperelay` + `socat` para expor um socket Unix em `$HOME/.ssh/agent.sock` no WSL, permitindo `git`/`ssh` com as chaves do Bitwarden.

### Dotfiles com GNU Stow
Cada diretório em `~/dotfiles` é tratado como pacote. O `stow --restow` recria links simbólicos para manter o home consistente.
