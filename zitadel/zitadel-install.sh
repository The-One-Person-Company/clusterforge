#!/bin/bash
#===============================================================================
#
# FILE: zitadel-install.sh
#
# NAME: Zitadel Installer
#
# USAGE: ./zitadel-install.sh
#
# DESCRIPTION: Installation script for Zitadel identity platform on Kubernetes.
#              Deploys and configures Zitadel and its dependencies.
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

export ZITADEL_DOMAIN="${AUTH_SUBDOMAIN}.${DOMAIN_BASE}"
export AUTH_DOMAIN="${AUTH_SUBDOMAIN}.${DOMAIN_BASE}"

required_vars=(
  POSTGRES_HOST POSTGRES_USER POSTGRES_PASSWORD
  ZITADEL_POSTGRES_USER ZITADEL_POSTGRES_PASSWORD ZITADEL_DB_NAME
)
for v in "${required_vars[@]}"; do
  : "${!v:?Environment variable $v is not set – aborting install}"
done


# Function to generate Zitadel masterkey if not set
_generate_masterkey() {
    if [ -z "${ZITADEL_MASTER_KEY:-}" ]; then
        export ZITADEL_MASTER_KEY="$(openssl rand -hex 32)"
        log "INFO" "Generated new Zitadel masterkey"
        log "INFO" "$ZITADEL_MASTER_KEY"
        log "INFO" "----------------------------------------"
    else
        log "INFO" "Using existing Zitadel masterkey"
    fi
}

# --- Logging ---
# Uses log, log_step, log_info, log_success, log_error from 00-config.sh

# --- Banner ---
print_banner() {
    echo -e "\033[36m"
    cat << "EOF"
    ███████╗██╗████████╗ █████╗ ██████╗ ███████╗██╗     
    ╚══███╔╝██║╚══██╔══╝██╔══██╗██╔══██╗██╔════╝██║     
      ███╔╝ ██║   ██║   ███████║██║  ██║█████╗  ██║     
     ███╔╝  ██║   ██║   ██╔══██║██║  ██║██╔══╝  ██║     
    ███████╗██║   ██║   ██║  ██║██████╔╝███████╗███████╗
    ╚══════╝╚═╝   ╚═╝   ╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝
    Zitadel Installer (v2.0)
EOF
    echo -e "\033[0m"
}

create_namespace() {
    local namespace=$1
    if ! microk8s kubectl get namespace $namespace &> /dev/null; then
        log "INFO" "Creating namespace: $namespace"
        microk8s kubectl create namespace $namespace
    fi
}

# Function to clean up Zitadel resources
cleanup() {
    log STEP "Cleaning up Zitadel resources..."
    
    # Uninstall Helm releases first
    log INFO "Uninstalling Helm releases..."
    microk8s helm uninstall zitadel-app --namespace zitadel || true
    
    # Delete PVCs except database
    log INFO "Deleting PVCs..."
    microk8s kubectl delete pvc zitadel-storage --namespace zitadel || true
    
    # Delete secrets except database
    log INFO "Deleting secrets..."
    microk8s kubectl delete secret zitadel-secret zitadel-tls --namespace zitadel || true
    
    # Delete certificates
    log INFO "Deleting certificates..."
    microk8s kubectl delete certificate zitadel-tls --namespace zitadel || true
    
    # Delete namespace (will delete all remaining resources)
    log INFO "Deleting namespace..."
    microk8s kubectl delete namespace zitadel --ignore-not-found=true
    
    # Wait for namespace to be fully deleted
    log INFO "Waiting for namespace deletion..."
    while microk8s kubectl get namespace zitadel >/dev/null 2>&1; do
        sleep 2
    done
    
    log SUCCESS "Cleanup completed"
}

# Function to initialize YAML files from templates
init_yaml_files() {
    log STEP "Initializing YAML files from templates..."
    
    # Create namespace first
    create_namespace zitadel
    
    # List of template files to process
    local templates=(
        "zitadel/zitadel-values.yaml.template"
        "zitadel/zitadel-certificate.yaml.template"
        "zitadel/zitadel-pvc.yaml.template"
        "zitadel/zitadel-secret.yaml.template"
    )
    
    # Process each template
    for template in "${templates[@]}"; do
        local template_path="${WORKSPACE_DIR}/${template}"
        local output_path="${WORKSPACE_DIR}/${template%.template}"
        
        if [ ! -f "$template_path" ]; then
            log ERROR "Template file not found: $template_path"
            continue
        fi
        
        log INFO "Processing template: $template"
        envsubst < "$template_path" > "$output_path"
        log SUCCESS "Created: ${template%.template}"
    done
    
    log SUCCESS "All YAML files initialized"
}

install() {
    _generate_masterkey
    log STEP "Starting Zitadel installation"

    log STEP "Creating namespace..."
    # Create namespace if not exists
    microk8s kubectl create namespace zitadel || true

    # Add Helm repos
    log STEP "Adding Helm repos..."
    microk8s helm repo add zitadel https://charts.zitadel.com
    microk8s helm repo update

    log STEP "Applying Zitadel configurations..."
    # Apply supporting resources
    microk8s kubectl apply -n zitadel -f zitadel/zitadel-secret.yaml
    microk8s kubectl apply -n zitadel -f zitadel/zitadel-pvc.yaml
    microk8s kubectl apply -n zitadel -f zitadel/zitadel-certificate.yaml

    log STEP "Installing Zitadel..."
    # Install Zitadel with production values
    microk8s helm upgrade --install zitadel-app zitadel/zitadel \
    --namespace zitadel \
    --values zitadel/zitadel-values.yaml \
    --set masterkey="${ZITADEL_MASTER_KEY}" \
    --set database.postgres.host="${POSTGRES_HOST}" \
    --set database.postgres.port=5432 \
    --set database.postgres.database="${ZITADEL_DB_NAME}" \
    --set database.postgres.user.username="${ZITADEL_POSTGRES_USER}" \
    --set database.postgres.user.password="${ZITADEL_POSTGRES_PASSWORD}" \
    --set database.postgres.user.ssl.mode=disable \
    --set database.postgres.admin.username="${POSTGRES_USER}" \
    --set database.postgres.admin.password="${POSTGRES_PASSWORD}" \
    --set database.postgres.admin.ssl.mode=disable \
    --set defaultInstance.setup.username="${ZITADEL_ADMIN_USERNAME}" \
    --set defaultInstance.setup.password="${ZITADEL_ADMIN_PASSWORD}" \
    --set defaultInstance.setup.email="${ZITADEL_ADMIN_EMAIL}" \
    --set defaultInstance.setup.firstname="${ZITADEL_ADMIN_FIRSTNAME}" \
    --set defaultInstance.setup.lastname="${ZITADEL_ADMIN_LASTNAME}" \
    --set defaultInstance.setup.org.name="${ZITADEL_ORG_NAME}" \
    --set defaultInstance.setup.org.domain="${ZITADEL_ORG_DOMAIN}" \
    --set defaultInstance.setup.done=true \
    --set externalDomain="${AUTH_DOMAIN}" \
    --set externalSecure=true \
    --wait

    log INFO "Zitadel installation complete."
    echo "Check status: microk8s kubectl get pods -n zitadel"

    # Print access information
    echo "Zitadel Access Information:"
    echo "-------------------------"
    echo "URL: https://${ZITADEL_DOMAIN}"
    echo "Admin Username: ${ZITADEL_ADMIN_USERNAME}"
    echo "Admin Email: ${ZITADEL_ADMIN_EMAIL}"
}

show_menu() {
    clear
    print_banner
    while true; do
        echo
        echo "╔════════════════════════════════════════════════════════════════════╗"
        echo "║                      Zitadel Installation Manager                ║"
        echo "╠════════════════════════════════════════════════════════════════════╣"
        echo "║   ACTIONS                                                        ║"
        echo "║──────────────────────────────────────────────────────────────────║"
        echo "║  1) 🧹  Clean                                                    ║"
        echo "║  2) 📝  Generate YAML files                                      ║"
        echo "║  3) 🚀  Install                                                  ║"
        echo "║  4) 🧹  Clean & 🚀 Install                                       ║"
        echo "║  5) 🧹  Clean, 📝 Generate & 🚀 Install                           ║"
        echo "║──────────────────────────────────────────────────────────────────║"
        echo "║  i) ℹ️   Show Info & Version                                      ║"
        echo "║  q) ❌  Quit                                                     ║"
        echo "╚════════════════════════════════════════════════════════════════════╝"
        echo
        read -p "Select an option: " choice
        echo
        case $choice in
            1) cleanup ;;
            2) init_yaml_files ;;
            3) install ;;
            4) cleanup; install ;;
            5) cleanup; init_yaml_files; install ;;
            i|I)
                print_banner
                read -p "Press Enter to return to menu..."
                ;;
            q|Q)
                echo "Exiting..."; exit 0 ;;
            *)
                echo "Invalid option. Please try again." ;;
        esac
    done
}

# --- Main Execution ---
clear
print_banner
show_menu 