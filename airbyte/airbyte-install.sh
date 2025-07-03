#!/bin/bash
#===============================================================================
#
# FILE: airbyte-install.sh
#
# USAGE: ./airbyte-install.sh
#
# DESCRIPTION: Airbyte installation script for the TOPC Automation Server.
#              Deploys and configures Airbyte on a Kubernetes cluster.
#
# AUTHOR: Vivien Roggero LLC
# MODIFIED BY: Gemini
# CREATION DATE: 2024-08-01
# LAST MODIFIED: 2024-08-01
# VERSION: 2.0
#
#===============================================================================

# ██████╗     ██╗      █████╗ ██████╗ 
# ██╔══██╗    ██║     ██╔══██╗██╔══██╗
# ██████╔╝    ██║     ███████║██████╔╝
# ██╔══██╗    ██║     ██╔══██║██╔══██╗
# ██║  ██║    ███████╗██║  ██║██████╔╝
# ╚═╝  ╚═╝    ╚══════╝╚═╝  ╚═╝╚═════╝ 

set -euo pipefail

# Get the absolute path of the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load shared config and env
source "${WORKSPACE_DIR}/00-config.sh"

export AIRBYTE_DOMAIN="${AIRBYTE_SUBDOMAIN}.${DOMAIN_BASE}"


# Banner
print_banner() {
    echo -e "\033[36m"
    cat << "EOF"

     █████╗ ██╗██████╗ ██████╗ ████████╗██╗   ██╗███████╗
    ██╔══██╗██║██╔══██╗██╔══██╗╚══██╔══╝╚██╗ ██╔╝██╔════╝
    ███████║██║██████╔╝██████╔╝   ██║    ╚████╔╝ █████╗  
    ██╔══██║██║██╔══██╗██╔══██╗   ██║     ╚██╔╝  ██╔══╝  
    ██║  ██║██║██║  ██║██████╔╝   ██║      ██║   ███████╗
    ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═════╝    ╚═╝      ╚═╝   ╚══════╝
                                                     
         Airbyte Installer (v2.0)
EOF
    echo -e "\033[0m"
}

# Cleanup function
cleanup() {
    log_step "Cleaning up Airbyte resources..."
    local yaml_files=(
        "airbyte/airbyte-ingress.yaml"
        "airbyte/airbyte-certificate.yaml"
    )
    for file in "${yaml_files[@]}"; do
        local file_path="${WORKSPACE_DIR}/${file}"
        if [ -f "$file_path" ]; then
            log_info "Deleting file: $file"
            rm -f "$file_path"
        fi
    done
    microk8s kubectl delete secret airbyte-basic-auth -n airbyte --ignore-not-found=true
    microk8s kubectl delete namespace airbyte --ignore-not-found=true
    log_success "Cleanup completed."
}

# YAML generation
init_yaml_files() {
    log_step "Initializing YAML files from templates..."
    local templates=(
        "airbyte/airbyte-ingress.yaml.template"
        "airbyte/airbyte-certificate.yaml.template"
        "airbyte/airbyte-values.yaml.template"
        "airbyte/airbyte-certificate-pvc.yaml.template"
        "airbyte/airbyte-auth-secrets.yaml.template"
    )
    for template in "${templates[@]}"; do
        local template_path="${WORKSPACE_DIR}/${template}"
        local output_path="${WORKSPACE_DIR}/${template%.template}"
        if [ ! -f "$template_path" ]; then
            log_error "Template file not found: $template_path"
            continue
        fi
        log_info "Processing template: $template"
        envsubst < "$template_path" > "$output_path"
        log_success "Created: ${template%.template}"
    done
    log_success "All YAML files initialized"
}

# Install function
install() {
    log_step "Starting Airbyte installation..."
    init_yaml_files
    log_info "Creating Airbyte namespace..."
    microk8s kubectl create namespace airbyte --dry-run=client -o yaml | microk8s kubectl apply -f -
    log_info "Setting up Helm repository..."
    microk8s helm3 repo add airbyte https://airbytehq.github.io/helm-charts || true
    microk8s helm3 repo update
    log_info "Generating htpasswd..."
    log_info "Username: ${AIRBYTE_USERNAME}"
    log_info "Password: ${AIRBYTE_PASSWORD}"
    AIRBYTE_PASSWORD_HASH=$(htpasswd -nbB "${AIRBYTE_USERNAME}" "${AIRBYTE_PASSWORD}")
    log_info "Generated hash: ${AIRBYTE_PASSWORD_HASH}"
    if ! echo "${AIRBYTE_PASSWORD_HASH}" | grep -q "^${AIRBYTE_USERNAME}:"; then
        log_error "Invalid htpasswd format generated"
        exit 1
    fi
    log_info "Applying basic auth secret..."
    microk8s kubectl delete secret airbyte-basic-auth -n airbyte --ignore-not-found=true
    microk8s kubectl create secret generic airbyte-basic-auth \
        --from-literal=auth="${AIRBYTE_PASSWORD_HASH}" \
        -n airbyte
    if ! microk8s kubectl get secret airbyte-basic-auth -n airbyte; then
        log_error "Failed to create basic auth secret"
        exit 1
    fi
    log_info "Applying Airbyte auth secrets..."
    microk8s kubectl apply -f airbyte/airbyte-auth-secrets.yaml
    log_info "Creating certificate PVC..."
    microk8s kubectl apply -f airbyte/airbyte-certificate-pvc.yaml
    log_info "Installing/Upgrading Airbyte via Helm..."
    microk8s helm3 upgrade --install airbyte airbyte/airbyte \
        --namespace airbyte \
        --create-namespace \
        -f airbyte/airbyte-values.yaml \
        --wait
    log_info "Waiting for Airbyte server to be ready..."
    microk8s kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=server -n airbyte --timeout=300s
    log_info "Configuring certificates and ingress..."
    microk8s kubectl apply -f airbyte/airbyte-certificate.yaml
    log_info "Waiting for certificate to be ready..."
    microk8s kubectl wait --for=condition=ready certificate airbyte-certificate -n airbyte --timeout=300s
    log_info "Applying ingress configuration..."
    microk8s kubectl apply -f airbyte/airbyte-ingress.yaml
    log_info "Verifying ingress configuration..."
    if ! microk8s kubectl get ingress airbyte-ingress -n airbyte; then
        log_error "Ingress not found"
        exit 1
    fi
    log_info "Waiting for ingress to be ready..."
    sleep 30
    log_info "Checking certificate status..."
    microk8s kubectl get certificate airbyte-certificate -n airbyte -o jsonpath='{.status.conditions[0].status}'
    log_success "Airbyte installation completed successfully!"
    log_info "Access Airbyte at: https://${AIRBYTE_DOMAIN}"
}

# Menu
show_menu() {
    while true; do
        echo
        echo "╔════════════════════════════════════════════════════════════════════╗"
        echo "║                  Airbyte Installation Manager                    ║"
        echo "╠════════════════════════════════════════════════════════════════════╣"
        echo "║  1) 🧹  Clean (Full)                                             ║"
        echo "║  2) 📝  Create YAML files                                        ║"
        echo "║  3) 🚀  Install                                                  ║"
        echo "║  4) 🧹  Clean & 🚀 Install                                       ║"
        echo "║  5) 🧹  Clean, 📝 Create & 🚀 Install                             ║"
        echo "║                                                                  ║"
        echo "║  i) ℹ️   Show Info & Version                                      ║"
        echo "║  q) ❌  Quit                                                     ║"
        echo "╚════════════════════════════════════════════════════════════════════╝"
        echo
        read -p "Select an option: " choice
        echo
        case $choice in
            1)
                cleanup
                ;;
            2)
                init_yaml_files
                ;;
            3)
                install
                ;;
            4)
                cleanup
                install
                ;;
            5)
                cleanup
                init_yaml_files
                install
                ;;
            i|I)
                print_banner
                echo "Script Version: 2.0"
                echo "Author: Vivien Roggero LLC"
                echo "Last Modified: 2024-08-01"
                echo "Description: Airbyte installer for TOPC Automation Server."
                read -p "Press Enter to return to menu..."
                ;;
            q|Q)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid option. Please try again."
                ;;
        esac
    done
}
clear
print_banner
echo "Airbyte Installation Script"
echo "==========================="
show_menu
