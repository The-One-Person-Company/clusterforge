#!/bin/bash
#===============================================================================
#
# FILE: uptime-kuma-install.sh
#
# NAME: Uptime Kuma Installer
#
# USAGE: ./uptime-kuma-install.sh
#
# DESCRIPTION: Installation script for Uptime Kuma monitoring tool on Kubernetes.
#              Deploys and configures Uptime Kuma with production-ready settings.
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${WORKSPACE_DIR}/00-config.sh"

# Required env vars
required_vars=(
    UPTIME_KUMA_SUBDOMAIN
    DOMAIN_BASE
    UPTIME_KUMA_STORAGE_SIZE
    UPTIME_KUMA_STORAGE_CLASS
)
for v in "${required_vars[@]}"; do
    : "${!v:?Environment variable $v is not set – aborting install}"
done

export UPTIME_KUMA_DOMAIN="${UPTIME_KUMA_SUBDOMAIN}.${DOMAIN_BASE}"

print_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
    ██╗   ██╗██████╗ ████████╗██╗███╗   ███╗███████╗    
    ██║   ██║██╔══██╗╚══██╔══╝██║████╗ ████║██╔════╝    
    ██║   ██║██████╔╝   ██║   ██║██╔████╔██║█████╗      
    ██║   ██║██╔═══╝    ██║   ██║██║╚██╔╝██║██╔══╝      
    ╚██████╔╝██║        ██║   ██║██║ ╚═╝ ██║███████╗    
     ╚═════╝ ╚═╝        ╚═╝   ╚═╝╚═╝     ╚═╝╚══════╝    
                                                        
    ██╗  ██╗██╗   ██╗███╗   ███╗ █████╗                 
    ██║ ██╔╝██║   ██║████╗ ████║██╔══██╗                
    █████╔╝ ██║   ██║██╔████╔██║███████║                
    ██╔═██╗ ██║   ██║██║╚██╔╝██║██╔══██║                
    ██║  ██╗╚██████╔╝██║ ╚═╝ ██║██║  ██║                
    ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝                
    Uptime Kuma Installer (v2.0)
EOF
    echo -e "${NC}"
}

# Function to clean up Uptime Kuma resources
cleanup() {
    log STEP "Cleaning up Uptime Kuma resources..."
    
    log STEP "Deleting Generated .yaml files"
    local yaml_files=(
        "uptime-kuma/uptime-kuma-pvc.yaml"
        "uptime-kuma/uptime-kuma-certificate.yaml"
        "uptime-kuma/uptime-kuma-ingress.yaml"
        "uptime-kuma/uptime-kuma-values.yaml"
    )
    
    for file in "${yaml_files[@]}"; do
        local file_path="${WORKSPACE_DIR}/${file}"
        if [ -f "$file_path" ]; then
            log INFO "Deleting file: $file"
            rm -f "$file_path"
        fi
    done
    
    # Uninstall Helm release
    log INFO "Uninstalling Helm release..."
    microk8s helm uninstall uptime-kuma -n uptime-kuma || true
    
    # Delete PVCs and namespace
    log INFO "Deleting existing PVCs and namespace..."
    microk8s kubectl delete namespace uptime-kuma --ignore-not-found=true
    
    log SUCCESS "Cleanup completed"
}

# Function to perform soft cleanup (preserving TLS and namespace)
soft_cleanup() {
    log STEP "Performing soft cleanup of Uptime Kuma resources..."
    
    # Delete generated YAML files except certificate
    log STEP "Deleting Generated .yaml files (except TLS-related)"
    local yaml_files=(
        "uptime-kuma/uptime-kuma-pvc.yaml"
        "uptime-kuma/uptime-kuma-ingress.yaml"
        "uptime-kuma/uptime-kuma-values.yaml"
    )
    
    for file in "${yaml_files[@]}"; do
        local file_path="${WORKSPACE_DIR}/${file}"
        if [ -f "$file_path" ]; then
            log INFO "Deleting file: $file"
            rm -f "$file_path"
        fi
    done
    
    # Uninstall Helm release but preserve namespace and TLS
    log INFO "Uninstalling Helm release..."
    microk8s helm uninstall uptime-kuma -n uptime-kuma || true
    
    log SUCCESS "Soft cleanup completed"
}

# Function to initialize YAML files from templates
init_yaml_files() {
    log STEP "Initializing YAML files from templates..."
    
    # Create namespace first
    microk8s kubectl create namespace uptime-kuma --dry-run=client -o yaml | microk8s kubectl apply -f -
    
    # List of template files to process
    local templates=(
        "uptime-kuma/uptime-kuma-pvc.yaml.template"
        "uptime-kuma/uptime-kuma-certificate.yaml.template"
        "uptime-kuma/uptime-kuma-ingress.yaml.template"
        "uptime-kuma/uptime-kuma-values.yaml.template"
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

# Render and apply manifests in order
apply_manifest() {
    local manifest="$1"
    local full_path="${SCRIPT_DIR}/${manifest}"
    log INFO "Applying $manifest"
    if [ ! -f "$full_path" ]; then
        log ERROR "Manifest file not found: $full_path"
        log ERROR "Current directory: $(pwd)"
        log ERROR "Script directory: ${SCRIPT_DIR}"
        log ERROR "Workspace directory: ${WORKSPACE_DIR}"
        exit 1
    fi
    microk8s kubectl apply -f "$full_path" -n uptime-kuma
}

install() {
    log STEP "Starting Uptime Kuma installation"

    # Add Helm repo
    log INFO "Adding Helm repository..."
    microk8s helm repo add uptime-kuma https://helm.irsigler.cloud
    microk8s helm repo update

    # Apply PVC and Certificate first
    apply_manifest "uptime-kuma/uptime-kuma-pvc.yaml"
    apply_manifest "uptime-kuma/uptime-kuma-certificate.yaml"
    
    # Wait for certificate to be ready
    log INFO "Waiting for certificate to be ready..."
    sleep 10

    # Install Uptime Kuma using Helm
    log INFO "Installing Uptime Kuma via Helm..."
    microk8s helm upgrade --install uptime-kuma uptime-kuma/uptime-kuma \
        --namespace uptime-kuma \
        --values uptime-kuma/uptime-kuma-values.yaml \
        --wait

    # If using microk8s-hostpath, fix permissions
    if grep -q 'storageClassName: microk8s-hostpath' "${WORKSPACE_DIR}/uptime-kuma/uptime-kuma-pvc.yaml"; then
        log INFO "Detected microk8s-hostpath storage class. Attempting to fix PVC permissions..."
        VOLUME_NAME=$(microk8s kubectl get pvc -n uptime-kuma uptime-kuma-storage -o jsonpath='{.spec.volumeName}')
        VOLUME_PATH="/var/snap/microk8s/common/default-storage/$VOLUME_NAME"
        if [ -n "$VOLUME_NAME" ] && [ -d "$VOLUME_PATH" ]; then
            sudo chown -R 1000:1000 "$VOLUME_PATH"
            log SUCCESS "Fixed permissions on $VOLUME_PATH"
            log INFO "Restarting Uptime Kuma pod(s)..."
            microk8s kubectl delete pod -n uptime-kuma -l app.kubernetes.io/name=uptime-kuma || true
        else
            log WARN "Could not find volume path $VOLUME_PATH for PVC $VOLUME_NAME. Skipping chown."
        fi
    fi

    # Apply ingress after Helm install
    apply_manifest "uptime-kuma/uptime-kuma-ingress.yaml"

    log SUCCESS "Uptime Kuma installation complete!"
    
    # Print access information
    echo "Uptime Kuma Access Information:"
    echo "=============================="
    echo "URL: https://${UPTIME_KUMA_DOMAIN}"
    echo
    echo "Note: It may take a few minutes for the TLS certificate to be fully provisioned."
    
    # Print pod status
    echo
    echo "Pod Status:"
    echo "==========="
    microk8s kubectl get pods -n uptime-kuma
}

# Display menu and handle user choice
show_menu() {
    clear
    print_banner
    while true; do
        echo
        echo "╔════════════════════════════════════════════════════════════════════╗"
        echo "║                  Uptime Kuma Installation Manager                ║"
        echo "╠════════════════════════════════════════════════════════════════════╣"
        echo "║   ACTIONS                                                        ║"
        echo "║──────────────────────────────────────────────────────────────────║"
        echo "║  1) 🧹  Clean (Full)                                             ║"
        echo "║  2) 🧹  Clean (Soft - preserves TLS and namespace)               ║"
        echo "║  3) 📝  Generate YAML files                                      ║"
        echo "║  4) 🚀  Install                                                  ║"
        echo "║  5) 🧹  Soft Clean, 📝 Generate & 🚀 Install                      ║"
        echo "║  6) 🧹  Clean, 📝 Generate & 🚀 Install                           ║"
        echo "║──────────────────────────────────────────────────────────────────║"
        echo "║  i) ℹ️   Show Info & Version                                      ║"
        echo "║  q) ❌  Quit                                                     ║"
        echo "╚════════════════════════════════════════════════════════════════════╝"
        echo
        read -rp "Select an option: " choice
        echo
        case $choice in
            1) cleanup ;;
            2) soft_cleanup ;;
            3) init_yaml_files ;;
            4) install ;;
            5) soft_cleanup; init_yaml_files; install ;;
            6) cleanup; init_yaml_files; install ;;
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