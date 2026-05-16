# WSL Dev Environment Setup

Guia do ambiente de desenvolvimento em Windows + WSL Arch Linux.

## Opcao rapida: setup automatico (recomendado)

Se voce nao quiser fazer tudo manualmente, este repositorio ja tem script para automatizar o processo inteiro:

```powershell
cd dev-setup
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup.ps1
```

O script cobre setup de Windows, setup root no Arch, setup de usuario no Arch e retomada apos reboot.
Durante a execucao, ele pergunta qual repositorio de dotfiles deve ser clonado.

## Repositorio

- Repo principal: https://github.com/juanmarquesdev/dev-setup
- README automatizado: `dev-setup/README.md`
- Dotfiles: use o seu proprio repositorio de dotfiles

---

## Guia manual completo

As etapas abaixo mantem o processo documentado para quem prefere configurar tudo manualmente.

## 1. PowerShell 7

```powershell
winget install Microsoft.PowerShell
```

## 2. WSL + Arch Linux

```powershell
wsl --install --no-distribution
wsl --install archlinux
```

Se o Windows pedir reinicializacao, reinicie antes de continuar.

## 3. Windows Terminal (tema + fonte)

### 3.1 Fonte

Instale CaskaydiaMono Nerd Font:
- https://www.nerdfonts.com/font-downloads

### 3.2 Catppuccin Mocha no settings.json

```json
"schemes": [
  {
    "name": "Catppuccin Mocha",
    "background": "#1E1E2E",
    "foreground": "#CDD6F4",
    "cursorColor": "#F5E0DC",
    "selectionBackground": "#585B70",
    "black": "#45475A",
    "blue": "#89B4FA",
    "cyan": "#94E2D5",
    "green": "#A6E3A1",
    "purple": "#F5C2E7",
    "red": "#F38BA8",
    "white": "#BAC2DE",
    "yellow": "#F9E2AF",
    "brightBlack": "#585B70",
    "brightBlue": "#89B4FA",
    "brightCyan": "#94E2D5",
    "brightGreen": "#A6E3A1",
    "brightPurple": "#F5C2E7",
    "brightRed": "#F38BA8",
    "brightWhite": "#A6ADC8",
    "brightYellow": "#F9E2AF"
  }
]
```

### 3.3 Perfil do Arch

```json
{
  "colorScheme": "Catppuccin Mocha",
  "font": {
    "face": "CaskaydiaMono Nerd Font"
  },
  "opacity": 95,
  "suppressApplicationTitle": true,
  "tabTitle": "Arch"
}
```

### 3.4 Desabilitar pesquisa web do menu Iniciar

```powershell
reg add HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search /V BingSearchEnabled /T REG_DWORD /D 0 /F
```

## 4. Arch Linux como root (primeira inicializacao)

### 4.1 Atualizar e instalar base

```bash
pacman-key --init
pacman-key --populate archlinux
pacman -Syu
pacman -S --needed base-devel git curl wget sudo
```

### 4.2 Criar usuario e sudo

```bash
useradd -m -G wheel SEU_USUARIO
passwd SEU_USUARIO
```

Edite sudoers:

```bash
EDITOR=nano visudo
```

Descomente:

```text
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
```

### 4.3 Configurar /etc/wsl.conf

```bash
cat > /etc/wsl.conf << 'EOF'
[user]
default=SEU_USUARIO

[boot]
systemd=true

[interop]
appendWindowsPath=false
EOF
```

### 4.4 Corrigir WSLInterop para systemd

```bash
echo ':WSLInterop:M::MZ::/init:PF' > /usr/lib/binfmt.d/WSLInterop.conf
```

### 4.5 Locale

```bash
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >> /etc/environment
```

### 4.6 Reiniciar WSL

```powershell
wsl --shutdown
wsl
```

## 5. Arch Linux como usuario

### 5.1 Instalar paru

```bash
cd /tmp
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si
```

### 5.2 Pacotes CLI

```bash
sudo pacman -S --needed zsh fzf ripgrep fd bat eza tmux htop socat openssh stow base-devel
```

### 5.3 Docker e asdf

```bash
paru -S --needed docker docker-compose asdf-vm
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

Depois disso, reinicie a sessao para aplicar o grupo docker.

### 5.4 oh-my-zsh + plugins + p10k

```bash
git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh

git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
  ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions

git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
  ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

git clone --depth=1 https://github.com/zsh-users/zsh-completions \
  ~/.oh-my-zsh/custom/plugins/zsh-completions

git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
  ~/.oh-my-zsh/custom/themes/powerlevel10k
```

No `.zshrc`:

```bash
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions fzf)

source /usr/share/fzf/key-bindings.zsh
source /usr/share/fzf/completion.zsh

alias ls="eza --icons"
alias ll="eza -lah --icons"
alias lt="eza --tree --icons"
alias cat="bat"
```

Defina zsh como shell padrao:

```bash
sudo chsh -s /usr/bin/zsh "$USER"
```

## 6. Git global

```bash
git config --global user.name 'SEU_NOME'
git config --global user.email 'SEU_EMAIL'
git config --global init.defaultBranch main
git config --global core.editor 'code --wait'
git config --global pull.rebase true
git config --global core.autocrlf false
git config --global core.pager ''
```

## 7. SSH Agent Bitwarden no WSL

### 7.1 Instalar npiperelay no Windows

```powershell
winget install --id jstarks.npiperelay -e

$src = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\jstarks.npiperelay*" `
  -Recurse -Filter "npiperelay.exe" | Select-Object -ExpandProperty FullName
Copy-Item $src "$env:LOCALAPPDATA\Microsoft\WindowsApps\npiperelay.exe" -Force
```

### 7.2 Bridge no .zshrc

```zsh
if grep -qi microsoft /proc/version; then
  export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"

  WIN_NPIPERELAY=$(cmd.exe /c "where npiperelay.exe" 2>/dev/null | \
    tr -d '\r' | \
    grep -i "npiperelay.exe$" | \
    head -n 1)

  if [ -n "$WIN_NPIPERELAY" ]; then
    NPIPERELAY=$(wslpath -u "$WIN_NPIPERELAY")

    if [ -x "$NPIPERELAY" ] && ! ss -a | grep -q "$SSH_AUTH_SOCK"; then
      rm -f "$SSH_AUTH_SOCK"
      setsid socat \
        UNIX-LISTEN:"$SSH_AUTH_SOCK",fork \
        EXEC:"\"$NPIPERELAY\" -ei -s //./pipe/openssh-ssh-agent" \
        >/dev/null 2>&1 &
    fi
  fi
fi

setopt NO_NOTIFY
```

### 7.3 Validar

```bash
ssh-add -L
ssh -T git@github.com
```

## 8. Dotfiles com GNU Stow

```bash
git clone git@github.com:SEU_USUARIO/SEU_REPO_DOTFILES.git ~/dotfiles
cd ~/dotfiles
stow zsh git tmux ssh
```

## 9. Assinatura SSH no Git

Se existir `~/.ssh/pessoal.pub`:

```bash
PUBKEY=$(cat ~/.ssh/pessoal.pub)
echo "SEU_EMAIL $PUBKEY" > ~/.ssh/allowed_signers

git config --global gpg.format ssh
git config --global user.signingKey ~/.ssh/pessoal.pub
git config --global commit.gpgSign true
git config --global tag.gpgSign true
git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
```

## Etapas manuais finais

1. Bitwarden Desktop: Settings -> SSH Agent -> Enable.
2. Rodar `p10k configure` no Arch.
3. Adicionar chave publica no GitHub como Signing Key: https://github.com/settings/keys.
4. Se necessario, reiniciar WSL para aplicar grupo docker e shell padrao.

## Resultado esperado

- Ambiente Windows + WSL Arch alinhado ao setup do repositorio
- Ferramentas base de terminal instaladas
- Docker e asdf disponiveis
- zsh com p10k e plugins
- Dotfiles aplicados com stow
- SSH via Bitwarden funcionando no WSL