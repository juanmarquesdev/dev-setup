#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  01-root.sh — Arch Linux initial setup (executar como root)
#
#  O que faz:
#    - Atualiza pacman e instala pacotes base
#    - Cria usuário com sudo
#    - Configura wsl.conf (systemd, usuário padrão)
#    - Configura locale
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

# ─── Carregar config ────────────────────────────────────────────────────────
if [[ ! -f "$CONFIG_ENV" ]]; then
    echo -e "${RED}  ✗ config.env não encontrado em $CONFIG_ENV${NC}"
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_ENV"

title "Arch Linux — Root Setup"
info "Usuário a criar: $SETUP_USER"

# ─── 1. Atualizar pacman ─────────────────────────────────────────────────────
step "[1/5] Atualizando pacman..."
pacman-key --init
pacman-key --populate archlinux
pacman -Syu --noconfirm
ok "Sistema atualizado"

# ─── 2. Pacotes base ─────────────────────────────────────────────────────────
step "[2/5] Instalando pacotes base..."
pacman -S --noconfirm --needed \
    base-devel git curl wget sudo
ok "Pacotes base instalados"

# ─── 3. Criar usuário ────────────────────────────────────────────────────────
step "[3/5] Criando usuário '$SETUP_USER'..."

if id "$SETUP_USER" &>/dev/null; then
    ok "Usuário $SETUP_USER já existe"
else
    useradd -m -G wheel "$SETUP_USER"
    ok "Usuário $SETUP_USER criado"
fi

# Definir senha
echo "$SETUP_USER:$SETUP_USER_PASS" | chpasswd
ok "Senha definida"

# ─── 4. Configurar sudo ──────────────────────────────────────────────────────
step "[4/5] Configurando sudo..."

if ! grep -q "^%wheel ALL=(ALL:ALL) NOPASSWD: ALL" /etc/sudoers; then
    sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers
fi
ok "Grupo wheel com NOPASSWD configurado"

# ─── 5. wsl.conf ─────────────────────────────────────────────────────────────
step "[5/5] Configurando /etc/wsl.conf..."

cat > /etc/wsl.conf << 'EOF'
[user]
default=SETUP_USER_PLACEHOLDER

[boot]
systemd=true
EOF

# Substituir placeholder pelo usuário real
sed -i "s/SETUP_USER_PLACEHOLDER/$SETUP_USER/" /etc/wsl.conf

ok "wsl.conf configurado"
info "  systemd=true | default user: $SETUP_USER"

# Locale
info "Configurando locale..."
if ! grep -q "^en_US.UTF-8" /etc/locale.gen; then
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
fi
if ! grep -q "^LANG=" /etc/environment 2>/dev/null; then
    echo "LANG=en_US.UTF-8" >> /etc/environment
fi
ok "Locale en_US.UTF-8 configurado"

# ─── Concluído ──────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}  ════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  Root setup concluído!${NC}"
echo -e "${GREEN}  ════════════════════════════════════════════════${NC}"
echo ""
