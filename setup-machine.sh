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
echo -e "${GREEN}${BOLD}  ✓ Basis-setup voltooid${NC}"
echo "  ${HOSTNAME,,} – ${IP}/${PREFIX}"
echo
echo -e "${BOLD}${CYAN}── Handmatige stappen (TODO) ──${NC}"
echo
echo -e "  ${YELLOW}[ ]${NC} apt-get update && apt-get upgrade"
echo -e "  ${YELLOW}[ ]${NC} Pakketten installeren: curl wget git vim htop ufw fail2ban"
echo -e "      ca-certificates gnupg lsb-release unattended-upgrades chrony open-vm-tools"
echo -e "  ${YELLOW}[ ]${NC} SSH hardening (/etc/ssh/sshd_config):"
echo -e "      PermitRootLogin no, PasswordAuthentication no, MaxAuthTries 3"
echo -e "  ${YELLOW}[ ]${NC} UFW configureren: default deny incoming, allow 22/tcp"
echo -e "  ${YELLOW}[ ]${NC} fail2ban configureren voor SSH (maxretry 3, bantime 86400)"
echo -e "  ${YELLOW}[ ]${NC} sysctl hardening (/etc/sysctl.d/99-bunk.conf):"
echo -e "      disable ipv6, enable syncookies, rp_filter, log_martians"
echo -e "  ${YELLOW}[ ]${NC} Automatische beveiligingsupdates (unattended-upgrades)"
echo -e "  ${YELLOW}[ ]${NC} NTP instellen (chrony)"
echo -e "  ${YELLOW}[ ]${NC} Docker installeren (indien nodig)"
echo -e "  ${YELLOW}[ ]${NC} Herstart de machine"
echo

read -rp "Herstarten? [Y/N] " RB
[[ "${RB,,}" == "y" ]] && reboot