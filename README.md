# Dev Setup

Automatiza a configuração completa de um ambiente de desenvolvimento **Windows + WSL Arch Linux**.

## O que é configurado

**Windows**
- PowerShell 7
- CaskaydiaMono Nerd Font
- WSL + Arch Linux
- npiperelay (ponte SSH Bitwarden → WSL)
- Windows ssh-agent desativado (Bitwarden assume)
- Windows Terminal com tema Catppuccin Mocha

**Arch Linux**
- Usuário com sudo (grupo wheel)
- systemd + WSLInterop fix
- paru (AUR helper)
- CLI: `zsh`, `fzf`, `ripgrep`, `fd`, `bat`, `eza`, `tmux`, `htop`, `socat`, `openssh`, `stow`
- oh-my-zsh + Powerlevel10k + plugins (autosuggestions, syntax-highlighting, completions)
- Dotfiles clonados e aplicados via GNU Stow
- Git configurado com assinatura SSH

---

## Como usar

### Pré-requisitos

- Windows 10/11 com winget
- [Bitwarden Desktop](https://bitwarden.com/download/) instalado e logado
- Suas chaves SSH salvas no Bitwarden

### 1. Clonar o repositório

```powershell
git clone https://github.com/juanmarquesdev/dev-setup
cd dev-setup
```

### 2. Editar a configuração

Abra `setup.ps1` e edite o bloco `$Config` no topo:

```powershell
$Config = @{
    WslDistro      = "archlinux"
    WslUser        = "seu-usuario"
    GitName        = "Seu Nome"
    GitEmail       = "seu@email.com"
    DotfilesRepo   = "git@github.com:seu-usuario/dotfiles.git"
    DotfilesPkgs   = "zsh git tmux ssh"   # pacotes do stow
}
```

### 3. Executar

```powershell
# PowerShell como Administrador
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup.ps1
```

O script vai:
1. Instalar tudo no Windows
2. Instalar e configurar o Arch Linux automaticamente
3. Clonar seus dotfiles e aplicar via stow
4. Configurar git, SSH signing e zsh

### 4. Passos manuais (após o script)

| Passo | O que fazer |
|-------|-------------|
| Bitwarden SSH | Settings → SSH Agent → Enable |
| p10k | No terminal Arch: `p10k configure` |
| GitHub signing key | [Settings → SSH Keys](https://github.com/settings/keys) → New SSH key → **Signing Key** |

---

## Estrutura

```
dev-setup/
├── setup.ps1          # Entry point — orquestra tudo
└── arch/
    ├── 01-root.sh     # Setup inicial como root
    └── 02-user.sh     # Setup do ambiente como usuário
```

## Notas técnicas

### WSLInterop + systemd
Com `systemd=true` no `wsl.conf`, o suporte a executáveis Windows precisa ser registrado via binfmt_misc. O `01-root.sh` cria `/usr/lib/binfmt.d/WSLInterop.conf` para corrigir isso automaticamente.

### SSH Bridge (Bitwarden → WSL)
Usa npiperelay + socat para expor as chaves do Bitwarden via unix socket no WSL. O script de bridge fica no `.zshrc` e é inicializado automaticamente ao abrir o terminal.

### Dotfiles com GNU Stow
Cada pasta em `~/dotfiles/` é um "pacote". O stow cria symlinks de `~/dotfiles/<pacote>/.<arquivo>` para `~/.<arquivo>`.
