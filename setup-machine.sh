#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# setup-machine.sh – Bunk Hosting machine setup
# Gebruik: sudo bash setup-machine.sh
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
section() { echo -e "\n${BOLD}${CYAN}── $* ──${NC}"; }
die()     { echo -e "${RED}[✗] $*${NC}" >&2; exit 1; }
ask()     { echo -e "${BOLD}$*${NC}"; }

[[ $EUID -ne 0 ]] && die "Draai als root: sudo bash $0"

echo -e "${BOLD}"
echo "  Bunk Hosting – Machine Setup"
echo -e "${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
section "Hostname"
# ═══════════════════════════════════════════════════════════════════════════════

ask "Hostname (bijv. BUNK-PROD-BND-NL1-01):"
read -rp "  → " HOSTNAME
[[ -n "$HOSTNAME" ]] || die "Hostname mag niet leeg zijn."

# ═══════════════════════════════════════════════════════════════════════════════
section "Netwerk"
# ═══════════════════════════════════════════════════════════════════════════════

echo "Beschikbare interfaces:"
ip -o link show | awk -F': ' 'NR>1{print "  " $2}'
echo

ask "Interface (bijv. ens160, eth0):"
read -rp "  → " IFACE
ip link show "$IFACE" &>/dev/null || die "Interface '$IFACE' bestaat niet."

echo
echo "IP-schema referentie:"
echo "  VLAN 10 – Management:  192.168.10.225–253  /27  gw: 192.168.10.254"
echo "  VLAN 20 – Backend:     192.168.20.225–253  /27  gw: 192.168.20.254"
echo "  VLAN 30 – Klant VMs:   10.10.0.1–31.253   /19  gw: 10.10.0.254"
echo

ask "IP-adres (bijv. 192.168.20.225):"
read -rp "  → " IP
[[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Ongeldig IP."

ask "Subnetprefix (bijv. 27):"
read -rp "  → " PREFIX
[[ "$PREFIX" =~ ^[0-9]+$ && "$PREFIX" -le 32 ]] || die "Ongeldig prefix."

ask "Gateway (bijv. 192.168.20.254):"
read -rp "  → " GW
[[ "$GW" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Ongeldige gateway."

ask "DNS-servers (standaard: 1.1.1.1,8.8.8.8):"
read -rp "  → " DNS
DNS="${DNS:-1.1.1.1,8.8.8.8}"

# ═══════════════════════════════════════════════════════════════════════════════
section "SSH public key"
# ═══════════════════════════════════════════════════════════════════════════════

ask "SSH public key voor de ubuntu gebruiker (Enter om over te slaan):"
read -rp "  → " SSH_KEY

# ═══════════════════════════════════════════════════════════════════════════════
section "Overzicht"
# ═══════════════════════════════════════════════════════════════════════════════

echo
echo "  Hostname  : $HOSTNAME"
echo "  IP        : ${IP}/${PREFIX}"
echo "  Gateway   : $GW"
echo "  DNS       : $DNS"
echo "  Interface : $IFACE"
echo

read -rp "Doorgaan? [Y/N] " GO
[[ "${GO,,}" == "y" ]] || die "Afgebroken."

# ═══════════════════════════════════════════════════════════════════════════════
section "Hostname instellen"
# ═══════════════════════════════════════════════════════════════════════════════

hostnamectl set-hostname "${HOSTNAME,,}"
sed -i "/127.0.1.1/d" /etc/hosts
echo "127.0.1.1  ${HOSTNAME,,}.bunkhosting.lan ${HOSTNAME,,}" >> /etc/hosts
log "Hostname: ${HOSTNAME,,}"

# ═══════════════════════════════════════════════════════════════════════════════
section "Netwerk instellen (Netplan)"
# ═══════════════════════════════════════════════════════════════════════════════

rm -f /etc/netplan/*.yaml

cat > /etc/netplan/01-static.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      dhcp4: false
      dhcp6: false
      addresses:
        - ${IP}/${PREFIX}
      routes:
        - to: default
          via: ${GW}
      nameservers:
        addresses:
$(echo "$DNS" | tr ',' '\n' | awk '{print "          - " $1}')
EOF

chmod 600 /etc/netplan/01-static.yaml
ip link set "$IFACE" up
netplan apply
sleep 3
log "Netwerk: ${IP}/${PREFIX} via ${GW}"

# Wacht tot DNS beschikbaar is
for i in {1..10}; do
    if getent hosts archive.ubuntu.com &>/dev/null; then
        break
    fi
    warn "Wacht op DNS... ($i/10)"
    sleep 2
done
getent hosts archive.ubuntu.com &>/dev/null || die "DNS werkt niet — controleer nameservers en gateway."

# ═══════════════════════════════════════════════════════════════════════════════
section "Updates installeren"
# ═══════════════════════════════════════════════════════════════════════════════

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    curl wget git vim htop ufw fail2ban \
    ca-certificates gnupg lsb-release \
    unattended-upgrades chrony open-vm-tools
log "Pakketten geïnstalleerd"

# ═══════════════════════════════════════════════════════════════════════════════
section "Hardening"
# ═══════════════════════════════════════════════════════════════════════════════

# sysctl
cat > /etc/sysctl.d/99-bunk.conf <<'EOF'
net.ipv4.ip_forward = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
kernel.randomize_va_space = 2
kernel.yama.ptrace_scope = 1
kernel.dmesg_restrict = 1
kernel.sysrq = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF
sysctl --system -q
log "sysctl hardening"

# SSH
cat > /etc/ssh/sshd_config <<'EOF'
Port 22
AddressFamily inet
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
UsePAM yes
KexAlgorithms curve25519-sha256,diffie-hellman-group16-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes256-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com
SyslogFacility AUTH
LogLevel VERBOSE
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
systemctl restart ssh
log "SSH gehard (alleen key-based)"

# UFW
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw --force enable
log "UFW: default deny, SSH open"

# fail2ban
cat > /etc/fail2ban/jail.d/bunk.conf <<'EOF'
[sshd]
enabled  = true
maxretry = 3
bantime  = 86400
findtime = 600
EOF
systemctl enable fail2ban
systemctl restart fail2ban
log "fail2ban actief"

# Automatische beveiligingsupdates
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
log "Automatische updates ingeschakeld"

# NTP
systemctl enable chrony
systemctl start chrony 2>/dev/null || true
log "NTP (chrony) actief"

# ═══════════════════════════════════════════════════════════════════════════════
section "SSH public key"
# ═══════════════════════════════════════════════════════════════════════════════

if [[ -n "$SSH_KEY" ]]; then
    mkdir -p /home/ubuntu/.ssh
    echo "$SSH_KEY" >> /home/ubuntu/.ssh/authorized_keys
    chmod 700 /home/ubuntu/.ssh
    chmod 600 /home/ubuntu/.ssh/authorized_keys
    chown -R ubuntu:ubuntu /home/ubuntu/.ssh
    log "SSH public key toegevoegd"
else
    warn "Geen SSH-sleutel opgegeven — voeg dit handmatig toe via /home/ubuntu/.ssh/authorized_keys"
fi

# ═══════════════════════════════════════════════════════════════════════════════
echo
echo -e "${GREEN}${BOLD}  ✓ Setup voltooid${NC}"
echo "  ${HOSTNAME,,} – ${IP}/${PREFIX}"
echo

read -rp "Herstarten? [Y/N] " RB
[[ "${RB,,}" == "y" ]] && reboot