#!/bin/bash
#===============================================================================
#
# FILE: setup-server.sh
#
# NAME: Forteress
#
# USAGE: ./setup-server.sh
#
# DESCRIPTION: A comprehensive setup script for Ubuntu servers.
#
#              This script installs and configures essential development tools,
#              terminal enhancements, containerization platforms (Docker,
#              MicroK8s), and applies basic security hardening.
#
# OPTIONS: ---
# REQUIREMENTS: An Ubuntu-based system, sudo privileges, and a configured .env file.
# BUGS: ---
# NOTES: ---
# AUTHOR: Vivien Roggero LLC
# MODIFIED BY: Gemini
# CREATION DATE: 2024-08-01
# LAST MODIFIED: 2024-08-01
# VERSION: 1.3
#
#===============================================================================

# ██████╗     ██╗      █████╗ ██████╗ 
# ██╔══██╗    ██║     ██╔══██╗██╔══██╗
# ██████╔╝    ██║     ███████║██████╔╝
# ██╔══██╗    ██║     ██╔══██║██╔══██╗
# ██║  ██║    ███████╗██║  ██║██████╔╝
# ╚═╝  ╚═╝    ╚══════╝╚═╝  ╚═╝╚═════╝ 

set -euo pipefail
# Source shared configuration and utilities
source "$(dirname "${BASH_SOURCE[0]}")/00-config.sh"



# --- Configuration ---
readonly ESSENTIAL_PACKAGES=(
    git curl wget jq make build-essential python3 python3-pip unzip
    htop ncdu screen tmux mc rsync whois dnsutils nmap sysstat lsof
    iftop vnstat bmon tree net-tools bat ripgrep silversearcher-ag
    fzf neofetch ca-certificates gnupg apache2-utils zsh dialog
)
readonly SECURITY_PACKAGES=(
    ufw fail2ban unattended-upgrades auditd
)
readonly K8S_NETWORK_CIDR="10.1.5.0/24" # Network CIDR for internal k8s communication

# --- Colors and Formatting ---
readonly C_RESET='\033[0m'
readonly C_BOLD='\033[1m'
readonly C_BLUE='\033[1;34m'
readonly C_GREEN='\033[1;32m'
readonly C_RED='\033[1;31m'
readonly C_YELLOW='\033[1;33m'
readonly C_CYAN='\033[1;36m'

# --- Logging and Banners ---
log_step() {
    echo -e "\n${C_BLUE}==>${C_RESET} ${C_BOLD}$1${C_RESET}"
}
log_success() {
    echo -e " ${C_GREEN}✓${C_RESET} $1"
}
log_error() {
    echo -e " ${C_RED}✗${C_RESET} $1" >&2
}
log_warn() {
    echo -e " ${C_YELLOW}⚠️${C_RESET} $1"
}
print_banner() {
    echo -e "${C_CYAN}"
    cat << "EOF"

███████╗ ██████╗ ██████╗ ████████╗██████╗ ███████╗███████╗███████╗
██╔════╝██╔═══██╗██╔══██╗╚══██╔══╝██╔══██╗██╔════╝██╔════╝██╔════╝
█████╗  ██║   ██║██████╔╝   ██║   ██████╔╝█████╗  ███████╗███████╗
██╔══╝  ██║   ██║██╔══██╗   ██║   ██╔══██╗██╔══╝  ╚════██║╚════██║
██║     ╚██████╔╝██║  ██║   ██║   ██║  ██║███████╗███████║███████║
╚═╝      ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝
                                                                  

   Setup Script by Vivien Roggero LLC
EOF
    echo -e "${C_RESET}"
}

# --- Helper Functions ---
check_sudo() {
    if [[ "$EUID" -ne 0 ]]; then
        log_warn "This script requires sudo privileges for some operations. You may be prompted for your password."
    fi
}
command_exists() {
    command -v "$1" &>/dev/null
}
get_ubuntu_codename() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$VERSION_CODENAME"
    else
        log_error "Cannot determine Ubuntu version."
        exit 1
    fi
}
install_package() {
    if ! dpkg -l | grep -q "^ii  $1 "; then
        log_step "Installing $1..."
        execute_command "sudo apt-get install -y '$1'"
        log_success "$1 installed successfully."
    else
        log_success "$1 is already installed."
    fi
}

# --- Installation Functions ---
install_system_tools() {
    log_step "Updating package lists and installing essential tools..."
    execute_command "sudo apt-get update"
    for pkg in "${ESSENTIAL_PACKAGES[@]}"; do
        install_package "$pkg"
    done
    log_success "All essential system tools are installed."
}
install_terminal_enhancements() {
    log_step "Setting up terminal enhancements..."
    
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log_step "Installing Oh My Zsh..."
        
        # Install Oh My Zsh non-interactively
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        
        # Install powerlevel10k theme
        execute_command "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git '${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k'"
        
        # Install plugins
        execute_command "git clone https://github.com/zsh-users/zsh-autosuggestions '${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions'"
        execute_command "git clone https://github.com/zsh-users/zsh-syntax-highlighting.git '${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting'"
        
        # Configure .zshrc
        cat > "$HOME/.zshrc" << 'EOF'
# Enable Powerlevel10k instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
    git
    docker
    kubectl
    helm
    sudo
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# Aliases
alias k='microk8s kubectl'
alias mk='microk8s kubectl'
alias h='helm'
alias d='docker'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias bat='batcat' # On Debian/Ubuntu, bat is installed as batcat

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF
        # Set zsh as default shell
        if [[ "$SHELL" != "$(which zsh)" ]]; then
            log_step "Setting Zsh as default shell..."
            execute_command "sudo chsh -s '$(which zsh)' '$USER'"
        fi
        log_success "Oh My Zsh and plugins installed and configured."
    else
        log_success "Oh My Zsh is already installed."
    fi
}
install_docker() {
    if ! command_exists docker; then
        log_step "Installing Docker..."
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(get_ubuntu_codename) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        sudo usermod -aG docker "$USER"
        log_success "Docker installed successfully."
    else
        log_success "Docker is already installed."
    fi
}
install_microk8s() {
    if ! command_exists microk8s; then
        log_step "Installing MicroK8s..."
        sudo snap install microk8s --classic
        sudo usermod -a -G microk8s "$USER"
        newgrp microk8s &>/dev/null || true # Attempt to apply group change immediately
        sudo chown -f -R "$USER" ~/.kube
        log_success "MicroK8s installed."
    else
        log_success "MicroK8s is already installed."
    fi
}
install_helm() {
    if ! command_exists helm; then
        log_step "Installing Helm..."
        curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
        sudo apt-get install apt-transport-https --yes
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
        sudo apt-get update
        sudo apt-get install -y helm
        log_success "Helm installed successfully."
    else
        log_success "Helm is already installed."
    fi
}
install_container_tools() {
    log_step "Installing all containerization tools..."
    install_docker
    install_microk8s
    install_helm
    log_success "All containerization tools installed."
}

# --- Configuration & Hardening Functions ---
configure_docker() {
    log_step "Configuring Docker..."
    mkdir -p "$HOME/.docker"

    if [ ! -f /etc/docker/daemon.json ]; then
        log_step "Configuring Docker daemon with systemd cgroup driver..."
        sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
        sudo systemctl restart docker
        log_success "Docker daemon configured and restarted."
    else
        log_success "Docker daemon configuration already exists."
    fi
}
configure_microk8s() {
    log_step "Configuring MicroK8s..."
    if ! sudo microk8s status --wait-ready --timeout=60 &>/dev/null; then
        log_step "Starting MicroK8s..."
        execute_command "sudo microk8s start"
        execute_command "sudo microk8s status --wait-ready"
    fi

    log_step "Enabling essential MicroK8s addons..."
    execute_command "sudo microk8s enable dns storage ingress cert-manager"

    log_step "Configuring and enabling MetalLB with range: ${METAL_LB_RANGE}"
    execute_command "sudo microk8s enable metallb:${METAL_LB_RANGE}"

    # Create microk8s-hostpath-immediate StorageClass if it does not exist
    log_step "Ensuring microk8s-hostpath-immediate StorageClass exists..."
    if ! sudo microk8s kubectl get storageclass microk8s-hostpath-immediate &>/dev/null; then
        cat <<EOF | sudo microk8s kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: microk8s-hostpath-immediate
provisioner: microk8s.io/hostpath
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: Immediate
EOF
        log_success "microk8s-hostpath-immediate StorageClass created."
    else
        log_success "microk8s-hostpath-immediate StorageClass already exists."
    fi

    log_step "Waiting for addons to become available..."
    sleep 30

    log_success "MicroK8s configured successfully."
}

# --- Security Hardening ---
install_security_tools() {
    log_step "Installing security tools..."
    sudo apt-get update
    for pkg in "${SECURITY_PACKAGES[@]}"; do
        install_package "$pkg"
    done
    log_success "Security tools installed."
}

harden_ssh() {
    log_step "Hardening SSH Configuration"
    execute_command "sudo passwd -l root" "Disabling root password login"

    local sshd_custom_config="/etc/ssh/sshd_config.d/90-hardening.conf"
    log_success "Applying hardened SSH configuration to $sshd_custom_config"
    sudo tee "$sshd_custom_config" > /dev/null <<'EOF'
# Hardened SSH settings
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
MaxAuthTries 3
MaxSessions 3
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
    
    execute_command "sudo systemctl restart ssh" "Restarting SSH service"
}

configure_firewall() {
    log_step "Configuring UFW Firewall for Kubernetes"
    install_package "ufw"
    
    execute_command "sudo ufw --force reset"
    execute_command "sudo ufw default deny incoming"
    execute_command "sudo ufw default allow outgoing"

    log_success "Allowing essential traffic (SSH, HTTP, HTTPS)..."
    execute_command "sudo ufw allow ssh"
    execute_command "sudo ufw allow http"
    execute_command "sudo ufw allow https"

    log_success "Allowing Kubernetes API and Kubelet ports..."
    execute_command "sudo ufw allow 6443/tcp"
    execute_command "sudo ufw allow 16443/tcp"
    execute_command "sudo ufw allow 10250/tcp"

    log_success "Allowing etcd ports..."
    execute_command "sudo ufw allow 2379/tcp"
    execute_command "sudo ufw allow 2380/tcp"

    log_success "Allowing Kubernetes overlay network traffic..."
    execute_command "sudo ufw allow 8472/udp   # Flannel/VXLAN"
    execute_command "sudo ufw allow 51820/udp  # WireGuard"

    log_success "Allowing internal Kubernetes traffic from ${K8S_NETWORK_CIDR}..."
    execute_command "sudo ufw allow from '${K8S_NETWORK_CIDR}' to any port 53 proto tcp"
    execute_command "sudo ufw allow from '${K8S_NETWORK_CIDR}' to any port 53 proto udp"
    execute_command "sudo ufw allow from '${K8S_NETWORK_CIDR}' to any port 30000:32767 proto tcp"
    execute_command "sudo ufw allow from '${K8S_NETWORK_CIDR}' to any port 30000:32767 proto udp"
    execute_command "sudo ufw allow from '${K8S_NETWORK_CIDR}' to any port 9100,10250,10255,10257,10259,2379,2380,25000,16443 proto tcp"

    log_success "Allowing MetalLB and NodePort traffic..."
    execute_command "sudo ufw allow 7472/tcp"
    execute_command "sudo ufw allow 7472/udp"
    execute_command "sudo ufw allow 30000:32767/tcp"

    read -p "Enable UFW firewall now? [y/N]: " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        execute_command "sudo ufw --force enable"
        log_success "UFW firewall is active."
    fi
    execute_command "sudo ufw status verbose"
}

configure_fail2ban() {
    log_step "Installing and configuring Fail2Ban"
    install_package "fail2ban"

    log_success "Configuring Fail2Ban jail.local..."
    sudo tee /etc/fail2ban/jail.local > /dev/null <<'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
destemail = your-email@example.com
sender = fail2ban@$(hostname)
action = %(action_mwl)s

[sshd]
enabled = true

[sshd-ddos]
enabled = true

[traefik]
enabled = true
port = http,https
filter = traefik
logpath = /var/log/traefik/access.log
maxretry = 10
findtime = 5m
bantime = 1h
EOF

    log_success "Creating Fail2Ban filter for Traefik..."
    sudo tee /etc/fail2ban/filter.d/traefik.conf > /dev/null <<'EOF'
[Definition]
failregex = ^.*"ClientIP":"<HOST>".*"Status":(4[0-9]{2}|5[0-9]{2}).*$
ignoreregex =
EOF

    sudo systemctl enable fail2ban
    sudo systemctl restart fail2ban
    log_success "Fail2Ban is installed and running."
}

enable_auto_updates() {
    log_step "Enabling Automatic Security Updates"
    install_package "unattended-upgrades"
    sudo tee /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
    log_success "Automatic security updates enabled."
}

harden_kernel() {
    log_step "Applying Kernel Hardening Settings (sysctl)"
    sudo tee /etc/sysctl.d/99-hardening.conf > /dev/null <<'EOF'
# General Security
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
kernel.randomize_va_space=2

# SYN Flood Protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Kubernetes Specific
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
fs.inotify.max_user_watches = 524288
EOF
    sudo sysctl --system
    log_success "Kernel parameters hardened."
}

configure_system_limits() {
    log_step "Configuring System Limits for Kubernetes"
    sudo tee /etc/security/limits.d/99-kubernetes.conf > /dev/null <<'EOF'
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
EOF
    log_success "System limits configured."
}

configure_login_banner() {
    log_step "Configuring SSH Login Banner..."
    local banner_file="/etc/issue.net"
    local motd_file="/etc/motd"

    sudo tee "$banner_file" > /dev/null <<'EOF'
***********************************************************************
*  PRIVATE SERVER OF THE ONE PERSON COMPANY                           *
*                                                                     *
*  Unauthorized access is strictly prohibited.                        *
*                                                                     *
*  This system is for the use of authorized users only. Individuals   *
*  using this computer system without authority, or in excess of their*
*  authority, are subject to having all their activities on this      *
*  system monitored and recorded by system personnel.                 *
*                                                                     *
*  Anyone using this system expressly consents to such monitoring and *
*  is advised that if such monitoring reveals possible evidence of    *
*  criminal activity, system personnel may provide the evidence of    *
*  such monitoring to law enforcement officials.                      *
*                                                                     *
*  Disconnect immediately if you are not an authorized user.          *
***********************************************************************
EOF

    # Configure sshd to use the banner
    sudo sed -i '/^#*Banner /c\Banner /etc/issue.net' /etc/ssh/sshd_config

    log_step "Restarting SSH service to apply changes..."
    sudo systemctl restart ssh
    
    log_success "SSH banner configured."
}

security_menu() {
    while true; do
        echo -e "\n${C_BOLD}System Hardening Menu${C_RESET}"
        echo "--------------------------"
        echo "1) Apply All Hardening Measures (Recommended)"
        echo "2) Configure Firewall (UFW)"
        echo "3) Harden SSH Configuration"
        echo "4) Install & Configure Fail2Ban"
        echo "5) Enable Automatic Security Updates"
        echo "6) Apply Kernel Hardening (sysctl)"
        echo "7) Configure System Limits"
        echo "8) Configure SSH Login Banner"
        echo "b) Back to Main Menu"
        echo "--------------------------"
        read -rp "Select a hardening option: " choice
        case $choice in
            1)
                install_security_tools
                configure_firewall
                harden_ssh
                configure_fail2ban
                enable_auto_updates
                harden_kernel
                configure_system_limits
                configure_login_banner
                ;;
            2) configure_firewall ;;
            3) harden_ssh ;;
            4) configure_fail2ban ;;
            5) enable_auto_updates ;;
            6) harden_kernel ;;
            7) configure_system_limits ;;
            8) configure_login_banner ;;
            b|B) break ;;
            *) log_warn "Invalid option." ;;
        esac
    done
}

# --- Main Execution ---
show_menu() {
    echo -e "${C_BOLD}\nServer Setup Main Menu${C_RESET}"
    echo "--------------------------"
    echo "1) Full Install & Configure (Recommended)"
    echo "2) Install System & CLI Tools"
    echo "3) Install Terminal Enhancements (Zsh, Oh My Zsh)"
    echo "4) Install Containerization Tools (Docker, MicroK8s, Helm)"
    echo "5) Run All Configurations"
    echo "6) System Hardening Menu"
    echo "q) Quit"
    echo "--------------------------"
}

main() {
    print_banner
    check_sudo
    
    # Non-interactive mode
    if [[ "${1-}" == "--full-install" ]]; then
        install_system_tools
        install_terminal_enhancements
        install_container_tools
        configure_docker
        configure_microk8s
        # Auto-apply all security measures in non-interactive mode
        install_security_tools; configure_firewall; harden_ssh; configure_fail2ban; enable_auto_updates; harden_kernel; configure_system_limits; configure_login_banner
    else # Interactive menu
        while true; do
            show_menu
            read -rp "Please select an option: " choice
            case $choice in
                1)
                    install_system_tools
                    install_terminal_enhancements
                    install_container_tools
                    configure_docker
                    configure_microk8s
                    security_menu
                    break
                    ;;
                2) install_system_tools ;;
                3) install_terminal_enhancements ;;
                4) install_container_tools ;;
                5) 
                   configure_docker
                   configure_microk8s
                   ;;
                6) security_menu ;;
                q|Q)
                    echo "Exiting."
                    break
                    ;;
                *) log_warn "Invalid option. Please try again." ;;
            esac
        done
    fi

    log_step "Setup script finished!"
    log_warn "You must log out and log back in for all changes to take effect."
    log_step "After logging back in, you can customize your Zsh prompt by running: p10k configure"
}

main "$@" 