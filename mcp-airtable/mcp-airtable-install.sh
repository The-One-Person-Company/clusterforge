#!/bin/bash
#===============================================================================
#
# FILE: mcp-airtable-install.sh
#
# NAME: MCP Airtable Installer
#
# USAGE: ./mcp-airtable-install.sh
#
# DESCRIPTION: Installation script for MCP Airtable server on Kubernetes.
#              Deploys and configures the Airtable MCP server for AI integration.
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

# Prompt for client name
read -p "Enter client name for MCP Airtable (e.g., 'client1'): " MCP_CLIENT_NAME
if [ -z "$MCP_CLIENT_NAME" ]; then
    log ERROR "Client name is required"
    exit 1
fi

# Set service name based on client
export MCP_SERVICE_NAME="airtable-${MCP_CLIENT_NAME}"

# Prompt for Airtable API key if not set
if [ -z "${AIRTABLE_API_KEY:-}" ]; then
    read -s -p "Enter Airtable API Key: " AIRTABLE_API_KEY
    echo
    if [ -z "$AIRTABLE_API_KEY" ]; then
        log ERROR "Airtable API Key is required"
        exit 1
    fi
    export AIRTABLE_API_KEY
fi

# Required env vars
required_vars=(
    MCP_AIRTABLE_STORAGE_SIZE
)
for v in "${required_vars[@]}"; do
    : "${!v:?Environment variable $v is not set – aborting install}"
done

# Base64 encode the API key for Kubernetes secret
export AIRTABLE_API_KEY_B64=$(echo -n "${AIRTABLE_API_KEY}" | base64 | tr -d '\n')

# Debug: Show the base64 encoded value (first 10 chars)
log INFO "API Key base64 (first 10 chars): ${AIRTABLE_API_KEY_B64:0:10}..."

# --- Logging ---
# Uses log, log_step, log_info, log_success, log_error from 00-config.sh

# --- Banner ---
print_banner() {
    echo -e "\033[36m"
    cat << "EOF"
    ███╗   ███╗ ██████╗██████╗                                  
    ████╗ ████║██╔════╝██╔══██╗                                 
    ██╔████╔██║██║     ██████╔╝                                 
    ██║╚██╔╝██║██║     ██╔═══╝                                  
    ██║ ╚═╝ ██║╚██████╗██║                                      
    ╚═╝     ╚═╝ ╚═════╝╚═╝                                                                                                     
     █████╗ ██╗██████╗ ████████╗ █████╗ ██████╗ ██╗     ███████╗
    ██╔══██╗██║██╔══██╗╚══██╔══╝██╔══██╗██╔══██╗██║     ██╔════╝
    ███████║██║██████╔╝   ██║   ███████║██████╔╝██║     █████╗  
    ██╔══██║██║██╔══██╗   ██║   ██╔══██║██╔══██╗██║     ██╔══╝  
    ██║  ██║██║██║  ██║   ██║   ██║  ██║██████╔╝███████╗███████╗
    ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝
    MCP Airtable Installer (v2.0)
EOF
    echo -e "\033[0m"
}

# Function to clean up MCP Airtable resources
cleanup() {
    log STEP "Cleaning up MCP Airtable resources..."
    
    log STEP "Deleting Generated .yaml files"
    local yaml_files=(
        "mcp-airtable/mcp-airtable-pvc.yaml"
        "mcp-airtable/mcp-airtable-configmap.yaml"
        "mcp-airtable/mcp-airtable-secret.yaml"
        "mcp-airtable/mcp-airtable-deployment.yaml"
        "mcp-airtable/mcp-airtable-hpa.yaml"
        "mcp-airtable/mcp-airtable-service.yaml"
    )
    
    for file in "${yaml_files[@]}"; do
        local file_path="${WORKSPACE_DIR}/${file}"
        if [ -f "$file_path" ]; then
            log INFO "Deleting file: $file"
            rm -f "$file_path"
        fi
    done
    
    # Delete specific resources but keep namespace
    log INFO "Deleting mcp-airtable resources..."
    microk8s kubectl delete deployment,service,configmap,secret,pvc,hpa -l app=${MCP_SERVICE_NAME} -n mcp --ignore-not-found=true
    
    log SUCCESS "Cleanup completed"
}

# Function to perform soft cleanup (preserving namespace)
soft_cleanup() {
    log STEP "Performing soft cleanup of MCP Airtable resources..."
    
    # Delete generated YAML files
    log STEP "Deleting Generated .yaml files"
    local yaml_files=(
        "mcp-airtable/mcp-airtable-pvc.yaml"
        "mcp-airtable/mcp-airtable-configmap.yaml"
        "mcp-airtable/mcp-airtable-secret.yaml"
        "mcp-airtable/mcp-airtable-deployment.yaml"
        "mcp-airtable/mcp-airtable-hpa.yaml"
        "mcp-airtable/mcp-airtable-service.yaml"
    )
    
    for file in "${yaml_files[@]}"; do
        local file_path="${WORKSPACE_DIR}/${file}"
        if [ -f "$file_path" ]; then
            log INFO "Deleting file: $file"
            rm -f "$file_path"
        fi
    done
    
    # Delete specific resources but keep namespace
    log INFO "Deleting mcp-airtable resources (preserving namespace)..."
    microk8s kubectl delete deployment,service,configmap,secret,pvc,hpa -l app=${MCP_SERVICE_NAME} -n mcp --ignore-not-found=true
    
    log SUCCESS "Soft cleanup completed"
}

# Function to initialize YAML files from templates
init_yaml_files() {
    log STEP "Initializing YAML files from templates..."
    
    # List of template files to process
    local templates=(
        "mcp-airtable/mcp-airtable-pvc.yaml.template"
        "mcp-airtable/mcp-airtable-configmap.yaml.template"
        "mcp-airtable/mcp-airtable-secret.yaml.template"
        "mcp-airtable/mcp-airtable-deployment.yaml.template"
        "mcp-airtable/mcp-airtable-hpa.yaml.template"
        "mcp-airtable/mcp-airtable-service.yaml.template"
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
        
        # Validate YAML syntax for secret files
        if [[ "$template" == *"secret"* ]]; then
            log INFO "Validating YAML syntax for secret..."
            if ! microk8s kubectl apply -f "$output_path" --dry-run=client >/dev/null 2>&1; then
                log ERROR "Invalid YAML generated for $template"
                log ERROR "Generated content:"
                cat "$output_path"
                exit 1
            fi
        fi
        
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
    microk8s kubectl apply -f "$full_path" -n mcp
}

install() {
    log STEP "Starting MCP Airtable installation"

    echo "Creating MCP namespace..."
    microk8s kubectl create namespace mcp --dry-run=client -o yaml | microk8s kubectl apply -f -

    # Wait for namespace to be ready
    log INFO "Waiting for namespace to be ready..."
    #microk8s kubectl wait --for=condition=ready namespace/mcp --timeout=30s

    # PVCs
    apply_manifest "mcp-airtable/mcp-airtable-pvc.yaml"
    
    # ConfigMap and Secret
    apply_manifest "mcp-airtable/mcp-airtable-configmap.yaml"
    apply_manifest "mcp-airtable/mcp-airtable-secret.yaml"
    
    # MCP Airtable app
    apply_manifest "mcp-airtable/mcp-airtable-deployment.yaml"
    
    # Service
    apply_manifest "mcp-airtable/mcp-airtable-service.yaml"
    
    # HPA
    apply_manifest "mcp-airtable/mcp-airtable-hpa.yaml"

    # Wait for pods to be ready
    log INFO "Waiting for mcp-airtable pods to be ready..."
    #microk8s kubectl wait --for=condition=ready pod -l app=${MCP_SERVICE_NAME} -n mcp --timeout=300s

    log SUCCESS "MCP Airtable installation complete!"
    
    # Print access information
    echo "MCP Airtable Access Information:"
    echo "================================"
    echo "Service Name: ${MCP_SERVICE_NAME}"
    echo "Namespace: mcp"
    echo "Internal URL: http://${MCP_SERVICE_NAME}.mcp.svc.cluster.local:80"
    echo "API Key: ${AIRTABLE_API_KEY}"
    echo
    echo "Note: This service is only accessible within the Kubernetes cluster."
    echo "Use the internal URL for cluster-to-cluster communication."
    
    # Print pod status
    echo
    echo "Pod Status:"
    echo "==========="
    microk8s kubectl get pods -n mcp -l app=${MCP_SERVICE_NAME}
}

# Display menu and handle user choice
show_menu() {
    clear
    while true; do
        echo
        echo "╔════════════════════════════════════════════════════════════════════╗"
        echo "║                MCP Airtable Installation Manager                 ║"
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