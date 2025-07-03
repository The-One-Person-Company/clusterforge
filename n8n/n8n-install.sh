#!/bin/bash
#===============================================================================
#
# FILE: n8n-install.sh
#
# NAME: N8N Installer
#
# USAGE: ./n8n-install.sh
#
# DESCRIPTION: Installation script for n8n automation platform on Kubernetes.
#              Deploys and configures n8n and its dependencies.
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

export N8N_DOMAIN="${N8N_SUBDOMAIN}.${DOMAIN_BASE}"

# --- Logging ---
# Uses log, log_step, log_info, log_success, log_error from 00-config.sh

# --- Banner ---
print_banner() {
    echo -e "\033[36m"
    cat << "EOF"
    ███╗   ██╗ █████╗ ███╗   ██╗
    ████╗  ██║██╔══██╗████╗  ██║
    ██╔██╗ ██║╚█████╔╝██╔██╗ ██║
    ██║╚██╗██║██╔══██╗██║╚██╗██║
    ██║ ╚████║╚█████╔╝██║ ╚████║
    ╚═╝  ╚═══╝ ╚════╝ ╚═╝  ╚═══╝
    n8n Installer (v2.0)
EOF
    echo -e "\033[0m"
}

# Function to clean up N8N resources
cleanup() {
    log STEP "Cleaning up N8N resources..."
    
    log STEP "Deleting Generated .yaml files"
    local yaml_files=(
        "n8n/n8n-pvc.yaml"
        "n8n/n8n-configmap.yaml"
        "n8n/n8n-secret.yaml"
        "n8n/n8n-deployment.yaml"
        "n8n/n8n-worker.yaml"
        "n8n/n8n-hpa.yaml"
        "n8n/n8n-ingress.yaml"
        "n8n/n8n-certificate.yaml"
        "n8n/n8n-service.yaml"
    )
    
    for file in "${yaml_files[@]}"; do
        local file_path="${WORKSPACE_DIR}/${file}"
        if [ -f "$file_path" ]; then
            log INFO "Deleting file: $file"
            rm -f "$file_path"
        fi
    done
    
    # Delete PVCs and namespace without waiting
    log INFO "Deleting existing PVCs and namespace..."
    microk8s kubectl delete namespace n8n --ignore-not-found=true
    
    log SUCCESS "Cleanup completed"
}

# Function to perform soft cleanup (preserving TLS and namespace)
soft_cleanup() {
    log STEP "Performing soft cleanup of N8N resources..."
    
    # Delete generated YAML files except certificate
    log STEP "Deleting Generated .yaml files (except TLS-related)"
    local yaml_files=(
        "n8n/n8n-pvc.yaml"
        "n8n/n8n-configmap.yaml"
        "n8n/n8n-secret.yaml"
        "n8n/n8n-deployment.yaml"
        "n8n/n8n-worker.yaml"
        "n8n/n8n-hpa.yaml"
        "n8n/n8n-ingress.yaml"
        "n8n/n8n-service.yaml"
    )
    
    for file in "${yaml_files[@]}"; do
        local file_path="${WORKSPACE_DIR}/${file}"
        if [ -f "$file_path" ]; then
            log INFO "Deleting file: $file"
            rm -f "$file_path"
        fi
    done
    
    # Delete specific resources but keep namespace and TLS resources
    log INFO "Deleting n8n resources (preserving TLS and namespace)..."
    microk8s kubectl delete deployment,service,configmap,secret,pvc,hpa -l app=n8n -n n8n --ignore-not-found=true
    
    log SUCCESS "Soft cleanup completed"
}

# Function to initialize YAML files from templates
init_yaml_files() {
    log STEP "Initializing YAML files from templates..."
    
    # List of template files to process
    local templates=(
        "n8n/n8n-pvc.yaml.template"
        "n8n/n8n-configmap.yaml.template"
        "n8n/n8n-secret.yaml.template"
        "n8n/n8n-deployment.yaml.template"
        "n8n/n8n-worker.yaml.template"
        "n8n/n8n-hpa.yaml.template"
        "n8n/n8n-ingress.yaml.template"
        "n8n/n8n-certificate.yaml.template"
        "n8n/n8n-service.yaml.template"
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
    sed -i 's/__SCHEME__/\$scheme/g; s/__HOST__/\$host/g' n8n/n8n-ingress.yaml
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
    microk8s kubectl apply -f "$full_path" -n n8n
}

install() {
    log STEP "Starting N8N installation"

    echo "Creating N8N namespace..."
    microk8s kubectl create namespace n8n --dry-run=client -o yaml | microk8s kubectl apply -f -

    # Wait for namespace to be ready
    log INFO "Waiting for namespace to be ready..."
    #microk8s kubectl wait --for=condition=ready namespace/n8n --timeout=30s

    # PVCs
    apply_manifest "n8n/n8n-pvc.yaml"
    
    # ConfigMap and Secret
    apply_manifest "n8n/n8n-configmap.yaml"
    apply_manifest "n8n/n8n-secret.yaml"
    
    # Certificate (must be created before ingress)
    apply_manifest "n8n/n8n-certificate.yaml"
    
    # Wait for certificate to be ready
    log INFO "Waiting for certificate to be ready..."
    #microk8s kubectl wait --for=condition=ready certificate/n8n-cert -n n8n --timeout=300s
    
    # N8N app and worker
    apply_manifest "n8n/n8n-deployment.yaml"
    apply_manifest "n8n/n8n-worker.yaml"
    
    # Service
    apply_manifest "n8n/n8n-service.yaml"
    
    # HPA
    apply_manifest "n8n/n8n-hpa.yaml"
    
    # Ingress (after certificate is ready)
    apply_manifest "n8n/n8n-ingress.yaml"

    # Wait for pods to be ready
    log INFO "Waiting for n8n pods to be ready..."
    #microk8s kubectl wait --for=condition=ready pod -l app=n8n -n n8n --timeout=300s
    #microk8s kubectl wait --for=condition=ready pod -l app=n8n-worker -n n8n --timeout=300s

    log SUCCESS "N8N installation complete!"
    
    # Print credentials and access information
    echo "N8N Access Information:"
    echo "======================"
    echo "URL: https://${N8N_DOMAIN}"
    echo "Username: ${N8N_USERNAME}"
    echo "Password: ${N8N_PASSWORD}"
    echo
    echo "Note: It may take a few minutes for the TLS certificate to be fully provisioned."
    
    # Print pod status
    echo
    echo "Pod Status:"
    echo "==========="
    microk8s kubectl get pods -n n8n
}

# Display menu and handle user choice
show_menu() {
    clear
    while true; do
        echo
        echo "╔════════════════════════════════════════════════════════════════════╗"
        echo "║                        n8n Installation Manager                  ║"
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
        read -p "Select an option: " choice
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
