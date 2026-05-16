#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  02-user.sh — Arch Linux dev environment setup (executar como usuário)
#
#  O que faz:
#    - Instala paru (AUR helper)
#    - Instala CLI utilities e ferramentas de desenvolvimento
#    - Instala zsh + oh-my-zsh + powerlevel10k + plugins
#    - Clona dotfiles e aplica com stow
#    - Configura git (global + assinatura SSH)
#    - Define zsh como shell padrão
#
#  Chamado automaticamente por setup.ps1
# ════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SETUP_DIR="${1:-/tmp/dev-setup}"
CONFIG_ENV="$SETUP_DIR/config.env"

# ─── Cores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; GRAY='\033[0;37m'; NC='\033[0m'

title()  { echo -e "\n${MAGENTA}  ══ $1 ══${NC}"; }
step()   { echo -e "${CYAN}  ❯ $1${NC}"; }
ok()     { echo -e "${GREEN}  ✔ $1${NC}"; }
warn()   { echo -e "${YELLOW}  ⚠ $1${NC}"; }
info()   { echo -e "${GRAY}    $1${NC}"; }

# ─── Verificar não está rodando como root ────────────────────────────────────
if [[ "$EUID" -eq 0 ]]; then
    echo -e "${RED}  ✗ Execute como usuário normal, não como root${NC}"
    exit 1
fi

# ─── Carregar config ────────────────────────────────────────────────────────
if [[ ! -f "$CONFIG_ENV" ]]; then
    echo -e "${RED}  ✗ config.env não encontrado em $CONFIG_ENV${NC}"
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_ENV"

# ─── Função: skip se já instalado ───────────────────────────────────────────
is_installed() { command -v "$1" &>/dev/null; }
dir_exists()   { [[ -d "$1" ]]; }

title "Arch Linux — User Setup"
info "Usuário: $(whoami)"

# ─── 1. paru (AUR helper) ───────────────────────────────────────────────────
step "[1/9] paru (AUR helper)"

if is_installed paru; then
    ok "paru já instalado"
else
    BUILD_DIR="$(mktemp -d)"
    git clone https://aur.archlinux.org/paru.git "$BUILD_DIR/paru"
    cd "$BUILD_DIR/paru"
    makepkg -si --noconfirm
    cd ~
    rm -rf "$BUILD_DIR"
    ok "paru instalado"
fi

# ─── 2. Pacotes pacman ──────────────────────────────────────────────────────
step "[2/9] Pacotes CLI e ferramentas"

PACMAN_PKGS=(
    # Shell
    zsh

    # Utilitários modernos
    fzf ripgrep fd bat eza tmux htop

    # SSH e rede
    socat openssh

    # Gerenciamento de dotfiles
    stow

    # Compilação
    base-devel
)

sudo pacman -S --noconfirm --needed "${PACMAN_PKGS[@]}"
ok "Pacotes instalados: ${PACMAN_PKGS[*]}"

# ─── 3. Docker via paru ─────────────────────────────────────────────────────
step "[3/9] Docker, docker-compose e asdf"

AUR_PKGS=(docker docker-compose asdf-vm)

for pkg in "${AUR_PKGS[@]}"; do
    if paru -Qi "$pkg" &>/dev/null; then
        info "$pkg já instalado"
    else
        paru -S --noconfirm --needed "$pkg"
        info "$pkg instalado"
    fi
done

# Habilitar e iniciar serviço docker
sudo systemctl enable --now docker 2>/dev/null || warn "systemctl não disponível (WSL sem systemd?)"

# Adicionar usuário ao grupo docker para uso sem sudo
if ! groups "$(whoami)" | grep -qw docker; then
    sudo usermod -aG docker "$(whoami)"
    warn "Usuário adicionado ao grupo docker — reinicie a sessão para aplicar"
fi

ok "Docker e asdf instalados"

# ─── 4. oh-my-zsh ───────────────────────────────────────────────────────────
step "[4/9] oh-my-zsh"

ZSH_DIR="$HOME/.oh-my-zsh"
CUSTOM_DIR="$ZSH_DIR/custom"

if dir_exists "$ZSH_DIR"; then
    ok "oh-my-zsh já instalado"
else
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$ZSH_DIR"
    ok "oh-my-zsh clonado"
fi

# ─── Plugins ────────────────────────────────────────────────────────────────
step "[5/9] Plugins zsh + Powerlevel10k"

declare -A PLUGINS=(
    ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
    ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting"
    ["zsh-completions"]="https://github.com/zsh-users/zsh-completions"
)

for plugin in "${!PLUGINS[@]}"; do
    dest="$CUSTOM_DIR/plugins/$plugin"
    if dir_exists "$dest"; then
        info "$plugin já presente"
    else
        git clone --depth=1 "${PLUGINS[$plugin]}" "$dest"
        info "$plugin clonado"
    fi
done

P10K_DIR="$CUSTOM_DIR/themes/powerlevel10k"
if dir_exists "$P10K_DIR"; then
    info "powerlevel10k já presente"
else
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
    info "powerlevel10k clonado"
fi

ok "Plugins e tema instalados"

# ─── 5. Dotfiles ────────────────────────────────────────────────────────────
step "[6/9] Dotfiles"

if dir_exists "$HOME/dotfiles"; then
    ok "Dotfiles já clonados — atualizando..."
    cd "$HOME/dotfiles" && git pull --ff-only 2>/dev/null || warn "git pull falhou (verifique SSH)"
else
    info "Clonando $SETUP_DOTFILES_REPO..."

    # Iniciar bridge SSH (npiperelay) para poder usar chaves do Bitwarden
    export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
    WIN_NPIPERELAY=$(cmd.exe /c 'where npiperelay.exe' 2>/dev/null | tr -d '\r' | grep -i 'npiperelay.exe$' | head -n 1 || true)

    if [[ -n "$WIN_NPIPERELAY" ]]; then
        NPIPERELAY=$(wslpath -u "$WIN_NPIPERELAY")
        if ! ss -a | grep -q "$SSH_AUTH_SOCK"; then
            rm -f "$SSH_AUTH_SOCK"
            setsid socat UNIX-LISTEN:"$SSH_AUTH_SOCK",fork \
                EXEC:"\"$NPIPERELAY\" -ei -s //./pipe/openssh-ssh-agent" \
                >/dev/null 2>&1 &
            sleep 2
        fi
        info "Agente SSH iniciado"
    else
        warn "npiperelay não encontrado — clone manualmente após configurar Bitwarden"
    fi

    # Adicionar GitHub ao known_hosts silenciosamente
    mkdir -p "$HOME/.ssh"
    ssh-keyscan github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null

    git clone "$SETUP_DOTFILES_REPO" "$HOME/dotfiles"
    ok "Dotfiles clonados"
fi

# ─── stow ───────────────────────────────────────────────────────────────────
info "Aplicando stow para: $SETUP_DOTFILES_PKGS"
cd "$HOME/dotfiles"

for pkg in $SETUP_DOTFILES_PKGS; do
    if [[ -d "$pkg" ]]; then
        stow --restow "$pkg" 2>/dev/null && info "stow $pkg ✔" || warn "stow $pkg falhou — remova conflitos manualmente"
    fi
done

ok "Dotfiles aplicados"

# ─── 6. Git config ──────────────────────────────────────────────────────────
step "[7/9] Git"

git config --global user.name      "$SETUP_GIT_NAME"
git config --global user.email     "$SETUP_GIT_EMAIL"
git config --global init.defaultBranch main
git config --global core.editor    "code --wait"
git config --global pull.rebase    true
git config --global core.autocrlf  false
git config --global core.pager     ""

ok "Git configurado: $SETUP_GIT_NAME <$SETUP_GIT_EMAIL>"

# ─── 7. Git SSH signing ─────────────────────────────────────────────────────
step "[8/9] Git — SSH signing"

# Permite escolher interativamente uma chave pública para signing.
# Também aceita override por variável de ambiente: SETUP_GIT_SIGNING_KEY.
DEFAULT_SIGNING_KEY="$HOME/.ssh/pessoal.pub"
SSH_SIGNING_KEY="${SETUP_GIT_SIGNING_KEY:-$DEFAULT_SIGNING_KEY}"

if [[ ! -f "$SSH_SIGNING_KEY" ]]; then
    mapfile -t SSH_PUBLIC_KEYS < <(find "$HOME/.ssh" -maxdepth 1 -type f -name "*.pub" | sort)

    if (( ${#SSH_PUBLIC_KEYS[@]} > 0 )); then
        if [[ -t 0 ]]; then
            info "Escolha a chave pública para assinatura SSH do Git:"

            default_idx=1
            for i in "${!SSH_PUBLIC_KEYS[@]}"; do
                idx=$((i + 1))
                [[ "${SSH_PUBLIC_KEYS[$i]}" == "$DEFAULT_SIGNING_KEY" ]] && default_idx=$idx
                info "  [$idx] ${SSH_PUBLIC_KEYS[$i]}"
            done

            read -r -p "Opção [$default_idx]: " key_choice
            key_choice=${key_choice:-$default_idx}

            if [[ "$key_choice" =~ ^[0-9]+$ ]] && (( key_choice >= 1 && key_choice <= ${#SSH_PUBLIC_KEYS[@]} )); then
                SSH_SIGNING_KEY="${SSH_PUBLIC_KEYS[$((key_choice - 1))]}"
            else
                warn "Opção inválida; usando padrão detectado"
                SSH_SIGNING_KEY="${SSH_PUBLIC_KEYS[$((default_idx - 1))]}"
            fi
        else
            SSH_SIGNING_KEY="${SSH_PUBLIC_KEYS[0]}"
            info "Sem TTY interativo; usando chave detectada: $SSH_SIGNING_KEY"
        fi
    fi
fi

if [[ -f "$SSH_SIGNING_KEY" ]]; then
    PUBKEY=$(cat "$SSH_SIGNING_KEY")
    ALLOWED_SIGNERS="$HOME/.ssh/allowed_signers"

    # allowed_signers
    echo "$SETUP_GIT_EMAIL $PUBKEY" > "$ALLOWED_SIGNERS"

    git config --global gpg.format               ssh
    git config --global user.signingKey          "$SSH_SIGNING_KEY"
    git config --global commit.gpgSign           true
    git config --global tag.gpgSign              true
    git config --global gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"

    ok "Git SSH signing configurado"
    info "Chave: $SSH_SIGNING_KEY"
    warn "Lembre-se de adicionar a chave no GitHub: Settings → SSH Keys → Signing Key"
else
    warn "Chave $SSH_SIGNING_KEY não encontrada — configure o signing manualmente após o setup"
fi

# ─── 8. Default shell → zsh ─────────────────────────────────────────────────
step "[9/9] Shell padrão"

CURRENT_SHELL=$(getent passwd "$(whoami)" | cut -d: -f7)
if [[ "$CURRENT_SHELL" == *"zsh" ]]; then
    ok "zsh já é o shell padrão"
else
    sudo chsh -s /usr/bin/zsh "$(whoami)"
    ok "zsh definido como shell padrão"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}  ════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  User setup concluído!${NC}"
echo -e "${GREEN}  ════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}  Passos manuais restantes:${NC}"
echo ""
echo -e "${CYAN}  1. Bitwarden${NC}"
echo -e "${GRAY}     Settings → SSH Agent → Enable${NC}"
echo ""
echo -e "${CYAN}  2. Powerlevel10k${NC}"
echo -e "${GRAY}     Abra o terminal e execute: p10k configure${NC}"
echo -e "${GRAY}     Depois: mv ~/.p10k.zsh ~/dotfiles/zsh/ && cd ~/dotfiles && stow --restow zsh && git add . && git commit -m 'add p10k config' && git push${NC}"
echo ""
echo -e "${CYAN}  3. Chave de assinatura no GitHub${NC}"
echo -e "${GRAY}     github.com/settings/keys → New SSH key → Signing Key${NC}"
echo -e "${GRAY}     Cole: $(cat "$SSH_SIGNING_KEY" 2>/dev/null || echo "$HOME/.ssh/pessoal.pub")${NC}"
echo ""
