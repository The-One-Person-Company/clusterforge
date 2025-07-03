#!/usr/bin/env bash
#===============================================================================
#
# FILE: rustdesk-install.sh
#
# USAGE: ./rustdesk-install.sh
#
# DESCRIPTION: Installs the RustDesk self-hosted remote desktop server.
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

# Source shared configuration and utilities
source "${WORKSPACE_DIR}/00-config.sh"

# --- Banner ---
print_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
    ██████╗ ██╗   ██╗███████╗████████╗██████╗ ███████╗███████╗██╗  ██╗
    ██╔══██╗██║   ██║██╔════╝╚══██╔══╝██╔══██╗██╔════╝██╔════╝██║ ██╔╝
    ██████╔╝██║   ██║███████╗   ██║   ██║  ██║█████╗  ███████╗█████╔╝ 
    ██╔══██╗██║   ██║╚════██║   ██║   ██║  ██║██╔══╝  ╚════██║██╔═██╗ 
    ██║  ██║╚██████╔╝███████║   ██║   ██████╔╝███████╗███████║██║  ██╗
    ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝   ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝
                                                                      
         Self-Hosted Remote Desktop
EOF
    echo -e "${NC}"
}

# Function to clean up RustDesk resources
cleanup() {
    log STEP "Cleaning up RustDesk resources..."
    
    log STEP "Deleting Generated .yaml files"
    local yaml_files=(
        "rust-desk/rustdesk-namespace.yaml"
        "rust-desk/rustdesk-pvc.yaml"
        "rust-desk/rustdesk-configmap.yaml"
        "rust-desk/rustdesk-deployment.yaml"
        "rust-desk/rustdesk-web-service.yaml"
        "rust-desk/rustdesk-client-lb-service.yaml"
        "rust-desk/rustdesk-ingress.yaml"
        "rust-desk/rustdesk-certificate.yaml"
    )
    
    for file in "${yaml_files[@]}"; do
        local file_path="${WORKSPACE_DIR}/${file}"
        if [ -f "$file_path" ]; then
            log INFO "Deleting file: $file"
            rm -f "$file_path"
        fi
    done
    
    log INFO "Deleting RustDesk namespace..."
    execute_command "Deleting RustDesk namespace" "microk8s kubectl delete namespace rustdesk --ignore-not-found=true"
    
    log SUCCESS "Cleanup completed"
}

# Function to perform soft cleanup (preserving TLS and namespace)
soft_cleanup() {
    log STEP "Performing soft cleanup of RustDesk resources..."
    
    # Delete generated YAML files except certificate
    log STEP "Deleting Generated .yaml files (except TLS-related)"
    local yaml_files=(
        "rust-desk/rustdesk-namespace.yaml"
        "rust-desk/rustdesk-pvc.yaml"
        "rust-desk/rustdesk-configmap.yaml"
        "rust-desk/rustdesk-deployment.yaml"
        "rust-desk/rustdesk-web-service.yaml"
        "rust-desk/rustdesk-client-lb-service.yaml"
        "rust-desk/rustdesk-ingress.yaml"
    )
    
    for file in "${yaml_files[@]}"; do
        local file_path="${WORKSPACE_DIR}/${file}"
        if [ -f "$file_path" ]; then
            log INFO "Deleting file: $file"
            rm -f "$file_path"
        fi
    done
    
    # Delete specific resources but keep namespace and TLS resources
    log INFO "Deleting RustDesk resources (preserving TLS and namespace)..."
    microk8s kubectl delete deployment,service,configmap,pvc -l app=rustdesk -n rustdesk --ignore-not-found=true
    
    log SUCCESS "Soft cleanup completed"
}

# Function to initialize YAML files from templates
init_yaml_files() {
    log STEP "Initializing RustDesk YAML files from templates..."

    local required_vars=(
        "RUSTDESK_SUBDOMAIN"
        "DOMAIN_BASE"
        "RUSTDESK_STORAGE_SIZE"
        "RUSTDESK_STORAGE_CLASS"
        "RUSTDESK_ALWAYS_USE_RELAY"
    )

    
    local templates=(
        "rust-desk/rustdesk-namespace.yaml.template"
        "rust-desk/rustdesk-pvc.yaml.template"
        "rust-desk/rustdesk-configmap.yaml.template"
        "rust-desk/rustdesk-deployment.yaml.template"
        "rust-desk/rustdesk-web-service.yaml.template"
        "rust-desk/rustdesk-client-lb-service.yaml.template"
        "rust-desk/rustdesk-ingress.yaml.template"
        "rust-desk/rustdesk-certificate.yaml.template"
    )
    
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
    
    log SUCCESS "All RustDesk YAML files initialized"
}

# --- Firewall Setup ---
setup_firewall() {
    log "STEP" "Configuring firewall rules..."
    if ! command -v ufw &> /dev/null; then
        log "WARN" "ufw command not found. Skipping firewall configuration."
        return
    fi

    if ! ufw status | grep -q "Status: active"; then
        log "WARN" "ufw is not active. Skipping firewall configuration."
        return
    fi

    local ports=( "21115/tcp" "21116/tcp" "21116/udp" "21117/tcp" "21119/tcp" )
    for port in "${ports[@]}"; do
        if ufw status | grep -qw "$port"; then
            log "INFO" "ufw rule for $port already exists. Skipping."
        else
            execute_command "Allowing $port through ufw" "sudo ufw allow $port"
        fi
    done
    log "SUCCESS" "Firewall rules configured."
}

# Render and apply manifests in order
apply_manifest() {
    local manifest="$1"
    local full_path="${WORKSPACE_DIR}/${manifest}"
    log INFO "Applying $manifest"
    if [ ! -f "$full_path" ]; then
        log ERROR "Manifest file not found: $full_path"
        log ERROR "Current directory: $(pwd)"
        log ERROR "Script directory: ${SCRIPT_DIR}"
        log ERROR "Workspace directory: ${WORKSPACE_DIR}"
        exit 1
    fi
    microk8s kubectl apply -f "$full_path"
}

# --- Install RustDesk ---
install_rustdesk() {
    log "STEP" "Installing RustDesk..."
    
    # PVCs
    apply_manifest "rust-desk/rustdesk-pvc.yaml"
    
    # ConfigMap
    apply_manifest "rust-desk/rustdesk-configmap.yaml"
    
    # Certificate (must be created before ingress)
    apply_manifest "rust-desk/rustdesk-certificate.yaml"
    
    # Deployment
    apply_manifest "rust-desk/rustdesk-deployment.yaml"
    
    # Services
    apply_manifest "rust-desk/rustdesk-web-service.yaml"
    apply_manifest "rust-desk/rustdesk-client-lb-service.yaml"
    
    # Ingress (after certificate is ready)
    apply_manifest "rust-desk/rustdesk-ingress.yaml"
    
    log "SUCCESS" "RustDesk installation commands executed."
}

# --- Wait for Deployment ---
wait_for_deployment() {
    log "STEP" "Waiting for RustDesk to be ready..."
    
    execute_command "Waiting for RustDesk deployment" "microk8s kubectl wait --for=condition=available deployment/rustdesk-server -n rustdesk --timeout=600s"
    
    log "SUCCESS" "RustDesk is ready."
}

# --- Display Access Information ---
display_access_info() {
    log "STEP" "RustDesk Access Information"
    echo
    log "SUCCESS" "RustDesk has been successfully installed!"
    echo
    log "INFO" "Access Information:"
    log "INFO" "  Web UI: https://${RUSTDESK_SUBDOMAIN}.${DOMAIN_BASE}"
    
    ClientIp=$(microk8s kubectl get svc rustdesk-client-lb-service -n rustdesk -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    
    log "INFO" "  Client Server Hostname: ${RUSTDESK_SUBDOMAIN}.${DOMAIN_BASE}"
    log "INFO" "  Client Server IP: ${ClientIp}"
    echo
    log "IMPORTANT" "Ensure your subdomain '${RUSTDESK_SUBDOMAIN}.${DOMAIN_BASE}' points to the Client Server IP: ${ClientIp}"
    log "IMPORTANT" "You must also retrieve the public key to configure your clients."
    log "IMPORTANT" "Run this command to get the key:"
    echo
    log "COMMAND" "microk8s kubectl exec -n rustdesk deployment/rustdesk-server -- cat /root/id_ed25519.pub"
    echo
    log "INFO" "In your RustDesk client, use '${RUSTDESK_SUBDOMAIN}.${DOMAIN_BASE}' for 'ID Server' and the public key for 'Key'."
    echo
}

# --- Cleanup ---
cleanup_temp_files() {
    log "STEP" "Cleaning up temporary YAML files..."
    local yaml_files=(
        "rust-desk/rustdesk-namespace.yaml"
        "rust-desk/rustdesk-pvc.yaml"
        "rust-desk/rustdesk-configmap.yaml"
        "rust-desk/rustdesk-deployment.yaml"
        "rust-desk/rustdesk-web-service.yaml"
        "rust-desk/rustdesk-client-lb-service.yaml"
        "rust-desk/rustdesk-ingress.yaml"
        "rust-desk/rustdesk-certificate.yaml"
    )
    
    for file in "${yaml_files[@]}"; do
        local file_path="${WORKSPACE_DIR}/${file}"
        if [ -f "$file_path" ]; then
            log INFO "Deleting file: $file"
            rm -f "$file_path"
        fi
    done
    log "SUCCESS" "Cleanup complete."
}

# --- Install Function ---
install() {
    log STEP "Starting RustDesk installation"

    # Check prerequisites
    if ! microk8s kubectl get namespace rustdesk >/dev/null 2>&1; then
        log INFO "Creating RustDesk namespace..."
        microk8s kubectl create namespace rustdesk --dry-run=client -o yaml | microk8s kubectl apply -f -
    fi

    # Initialize YAML files
    init_yaml_files
    
    # Setup firewall
    setup_firewall
    
    # Install RustDesk
    install_rustdesk
    
    # Wait for deployment
    wait_for_deployment
    
    # Display access information
    display_access_info
    
    # Cleanup temporary files
    cleanup_temp_files
    
    log SUCCESS "RustDesk installation completed successfully!"
    
    # Print pod status
    echo
    echo "Pod Status:"
    echo "==========="
    microk8s kubectl get pods -n rustdesk
}

# Display menu and handle user choice
show_menu() {
    clear
    while true; do
        echo
        echo "╔════════════════════════════════════════════════════════════════════╗"
        echo "║                    RustDesk Installation Manager                   ║"
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