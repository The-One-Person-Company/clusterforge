#!/bin/bash
#===============================================================================
#
# FILE: install.sh
#
# NAME: Clusterforge
#
# USAGE: ./install.sh
#
# DESCRIPTION: Main installation script for the TOPC Automation Server.
#
#              This script orchestrates the deployment of various application
#              stacks onto a pre-configured Kubernetes cluster. It should be
#              run after the server has been prepared with setup-server.sh.
#
# AUTHOR: Vivien Roggero LLC
# MODIFIED BY: Vivien Roggero
# CREATION DATE: 2025-06-01
# LAST MODIFIED: 2025-07-03
# VERSION: 2.2.0
#
#===============================================================================


# ██████╗     ██╗      █████╗ ██████╗ 
# ██╔══██╗    ██║     ██╔══██╗██╔══██╗
# ██████╔╝    ██║     ███████║██████╔╝
# ██╔══██╗    ██║     ██╔══██║██╔══██╗
# ██║  ██║    ███████╗██║  ██║██████╔╝
# ╚═╝  ╚═╝    ╚══════╝╚═╝  ╚═╝╚═════╝ 

#      █████████  ████                      █████                       ███████████                                     
#     ███░░░░░███░░███                     ░░███                       ░░███░░░░░░█                                     
#   ███     ░░░  ░███  █████ ████  █████  ███████    ██████  ████████  ░███   █ ░   ██████  ████████   ███████  ██████ 
#   ░███          ░███ ░░███ ░███  ███░░  ░░░███░    ███░░███░░███░░███ ░███████    ███░░███░░███░░███ ███░░███ ███░░███
#   ░███          ░███  ░███ ░███ ░░█████   ░███    ░███████  ░███ ░░░  ░███░░░█   ░███ ░███ ░███ ░░░ ░███ ░███░███████ 
#   ░░███     ███ ░███  ░███ ░███  ░░░░███  ░███ ███░███░░░   ░███      ░███  ░    ░███ ░███ ░███     ░███ ░███░███░░░  
#    ░░█████████  █████ ░░████████ ██████   ░░█████ ░░██████  █████     █████      ░░██████  █████    ░░███████░░██████ 
#     ░░░░░░░░░  ░░░░░   ░░░░░░░░ ░░░░░░     ░░░░░   ░░░░░░  ░░░░░     ░░░░░        ░░░░░░  ░░░░░      ░░░░░███ ░░░░░░  
#                                                                                                      ███ ░███         
#                                                                                                     ░░██████          
#                                                                                                      ░░░░░░           

set -euo pipefail

# Source shared configuration and utilities
source "$(dirname "${BASH_SOURCE[0]}")/00-config.sh"

# --- Banner ---
print_banner() {
read -r -d '' INTRO << 'EOF'
\Z3 Z2Clusterforge
\Zn

\Z2Clusterforge\Zn is your gateway to enterprise-grade infrastructure for one-person companies and small teams. It's a comprehensive toolkit that democratizes high-end server deployment and management, enabling you to focus on your business, not your infrastructure.

\ZbSetup Script by Vivien Roggero\Zn
EOF

# Display with dialog using colors

dialog --clear \
       --backtitle "\Z2Clusterforge Setup\Zn" \
       --title "\Zb\Z2Clusterforge\Zn" \
       --colors \
       --msgbox "$INTRO" 20 85
clear

}

# --- Prerequisite & Helper Functions ---

check_prerequisites() {
    log "STEP" "Checking prerequisites..."
    if ! command_exists microk8s; then
        log "ERROR" "MicroK8s is not installed. Please run 'setup-server.sh' first."
        exit 1
    fi
    log "SUCCESS" "Prerequisites met."
}

get_dashboard_token() {
    log "STEP" "Retrieving Kubernetes Dashboard Token..."
    local secret_name
    secret_name=$(microk8s kubectl -n kube-system get secret | grep "default-token" | awk '{print $1}')
    
    if [ -z "$secret_name" ]; then
        log "ERROR" "Could not find the default-token secret for the dashboard."
        return 1
    fi
    
    local token
    token=$(microk8s kubectl -n kube-system describe secret "$secret_name" | grep 'token:' | awk '{print $2}')
    
    echo
    log "SUCCESS" "Kubernetes Dashboard Token:"
    log "INFO" "${token}"
    echo
    log "WARN" "Save this token to access the dashboard."
}

# --- Core Setup and Installation Functions ---

generate_core_yamls() {
    log "STEP" "Generating core configurations from templates..."
    envsubst < metallb-config.yaml.template > metallb-config.yaml
    envsubst < cloudflare-issuer.yml.template > cloudflare-issuer.yml
    envsubst < dashboard-ingress.yaml.template > dashboard-ingress.yaml
    log "SUCCESS" "Core YAML configuration files generated."
}

initial_cluster_setup() {
    log "STEP" "Performing Initial Cluster Setup..."
    
    read -p "This will configure core addons, secrets, and ingresses. It may re-configure existing settings. Continue? (y/N) " -n 1 -r
    echo
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        log "WARN" "Skipping initial cluster setup."
        return
    fi

    log "INFO" "Enabling required MicroK8s addons..."
    execute_command "Enabling MicroK8s addons" "microk8s enable dashboard metrics-server"

    log "INFO" "Creating Cloudflare API token secret..."
    microk8s kubectl delete secret generic cloudflare-api-token-secret -n cert-manager --ignore-not-found=true
    execute_command "Creating Cloudflare API token secret" "microk8s kubectl create secret generic cloudflare-api-token-secret --from-literal=api-token='${CLOUDFLARE_API_TOKEN}' -n cert-manager"

    # Generate the YAML files before applying them
    generate_core_yamls

    log "INFO" "Applying MetalLB configuration..."
    execute_command "Applying MetalLB configuration" "microk8s kubectl apply -f metallb-config.yaml"

    log "INFO" "Applying Cloudflare issuer..."
    execute_command "Applying Cloudflare issuer" "microk8s kubectl apply -f cloudflare-issuer.yml"
    
    log "INFO" "Applying Kubernetes dashboard ingress..."
    execute_command "Applying dashboard ingress" "microk8s kubectl apply -f dashboard-ingress.yaml"

    execute_command "Getting cluster configuration" "bash get_config.sh"
    get_dashboard_token
    log "SUCCESS" "Initial cluster setup complete."
}

install_database() {
    log "STEP" "Installing Database Stack (Postgres & Redis)..."
    execute_command "Installing Database Stack" "bash database/database-install.sh"
}

install_monitoring() {
    log "STEP" "Installing Monitoring Stack..."
    execute_command "Installing Monitoring Stack" "cd monitoring && bash monitoring-install.sh && cd .."
}

install_n8n() {
    log "STEP" "Installing n8n..."
    execute_command "Installing n8n" "bash n8n/n8n-install.sh"
}

install_airbyte() {
    log "STEP" "Installing Airbyte..."
    execute_command "Installing Airbyte" "bash airbyte/airbyte-install.sh"
}

install_ntfy() {
    log "STEP" "Installing Ntfy..."
    execute_command "Installing Ntfy" "bash ntfy/ntfy-install.sh"
}

install_uptime_kuma() {
    log "STEP" "Installing Uptime Kuma..."
    execute_command "Installing Uptime Kuma" "bash uptime-kuma/uptime-kuma-install.sh"
}

install_harbor() {
    log "STEP" "Installing Harbor..."
    execute_command "Installing Harbor" "bash harbor/harbor-install.sh"
}

install_backup() {
    log "STEP" "Installing Velero (Backup)..."
    execute_command "Installing Velero" "cd backup && bash velero-install.sh && cd .."
}

install_all_services() {
    log "STEP" "Installing all application stacks..."
    install_database
    install_monitoring
    install_n8n
    install_airbyte
    install_ntfy
    install_uptime_kuma
    install_harbor
    install_backup
    log "SUCCESS" "All application stacks installed."
}

# --- Main Execution ---
show_menu() {
    local BOLD='\033[1m'
    echo -e "\n${CYAN}┌───────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${BOLD}${WHITE}       TOPC Automation Server Installer      ${CYAN}│${NC}"
    echo -e "${CYAN}├───────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${YELLOW} 1) Initial Cluster Setup (Run this first!)  ${CYAN}│${NC}"
    echo -e "${CYAN}├───────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${BLUE}           Application Stacks              ${CYAN}│${NC}"
    echo -e "${CYAN}├───────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC} 2) Database (Postgres & Redis)                ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} 3) Monitoring                                 ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} 4) n8n                                        ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} 5) Airbyte                                    ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} 6) Ntfy                                       ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} 7) Velero (Backups)                           ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} 8) Uptime Kuma                                 ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} 9) Harbor (Private Registry)                  ${CYAN}│${NC}"
    echo -e "${CYAN}├───────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${GREEN} 10) Install ALL Application Stacks           ${CYAN}│${NC}"
    echo -e "${CYAN}├───────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${BLUE}                 Utilities                 ${CYAN}│${NC}"
    echo -e "${CYAN}├───────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC} g) Generate Core YAML files                 ${CYAN}│${NC}"
    echo -e "${CYAN}├───────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${RED} q) Quit                                     ${CYAN}│${NC}"
    echo -e "${CYAN}└───────────────────────────────────────────────┘${NC}"
}

main() {
    check_prerequisites
    while true; do
        show_menu
        read -rp "Please select an option: " choice
        case $choice in
            1) initial_cluster_setup ;;
            2) install_database ;;
            3) install_monitoring ;;
            4) install_n8n ;;
            5) install_airbyte ;;
            6) install_ntfy ;;
            7) install_backup ;;
            8) install_uptime_kuma ;;
            9) install_harbor ;;
            10) install_all_services ;;
            g|G) generate_core_yamls ;;
            q|Q)
                log "INFO" "Exiting installer."
                break
                ;;
            *) log "WARN" "Invalid option. Please try again." ;;
        esac
    done
}

print_banner
main

