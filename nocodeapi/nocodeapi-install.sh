#!/bin/bash
set -euo pipefail

# Get the absolute path of the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load shared config and env
source "${WORKSPACE_DIR}/00-config.sh"
export NOCODEAPI_DOMAIN="${NOCODEAPI_SUBDOMAIN}.${DOMAIN_BASE}"

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to clean up resources
cleanup() {
    log "Cleaning up resources..."
    
    # Delete generated files
    local yaml_files=(
        "nocodeapi/nocodeapi-ingress.yaml"
        "nocodeapi/nocodeapi-certificate.yaml"
        "nocodeapi/nocodeapi-deployement.yaml"
        "nocodeapi/nocodeapi-service.yaml"
        "nocodeapi/nocodeapi-configmap.yaml"
        "nocodeapi/nocodeapi-secret.yaml"
    )
    
    for file in "${yaml_files[@]}"; do
        local file_path="${WORKSPACE_DIR}/${file}"
        if [ -f "$file_path" ]; then
            log "Deleting file: $file"
            rm -f "$file_path"
        fi
    done
    
    # Delete namespace
    log "Deleting namespace..."
    microk8s kubectl delete namespace nocodeapi --ignore-not-found=true
    
    log "Cleanup completed"
}

# Function to initialize YAML files from templates
init_yaml_files() {
    log "Initializing YAML files from templates..."
    
    # List of template files to process
    local templates=(
        "nocodeapi/nocodeapi-ingress.yaml.template"
        "nocodeapi/nocodeapi-certificate.yaml.template"
        "nocodeapi/nocodeapi-deployement.yaml.template"
        "nocodeapi/nocodeapi-service.yaml.template"
        "nocodeapi/nocodeapi-configmap.yaml.template"
        "nocodeapi/nocodeapi-secret.yaml.template"
    )
    
    # Process each template
    for template in "${templates[@]}"; do
        local template_path="${WORKSPACE_DIR}/${template}"
        local output_path="${WORKSPACE_DIR}/${template%.template}"
        
        if [ ! -f "$template_path" ]; then
            log "Template file not found: $template_path"
            continue
        fi
        
        log "Processing template: $template"
        envsubst < "$template_path" > "$output_path"
        log "Created: ${template%.template}"
    done
    
    log "All YAML files initialized"
}

# Function to install the API
install() {
    log "Starting API installation..."
    
    # Create namespace
    log "Creating namespace..."
    microk8s kubectl create namespace nocodeapi --dry-run=client -o yaml | microk8s kubectl apply -f -
    
    git clone https://github.com/stephengpope/no-code-architects-toolkit.git
    cd no-code-architects-toolkit
    docker build -t nca-toolkit:latest .
    # Apply configurations
    log "Applying configurations..."
    microk8s kubectl apply -f nocodeapi/nocodeapi-certificate.yaml
    microk8s kubectl apply -f nocodeapi/nocodeapi-configmap.yaml
    microk8s kubectl apply -f nocodeapi/nocodeapi-secret.yaml
    microk8s kubectl apply -f nocodeapi/nocodeapi-deployement.yaml
    microk8s kubectl apply -f nocodeapi/nocodeapi-service.yaml
    microk8s kubectl apply -f nocodeapi/nocodeapi-ingress.yaml
    
    # Wait for deployment
    log "Waiting for deployment to be ready..."
    microk8s kubectl rollout status deployment/nca-api -n nocodeapi
    
    log "Installation completed successfully!"
    
    # Print access information
    echo "API Access:"
    echo "URL: https://${NOCODEAPI_DOMAIN}"
}

# Display menu and handle user choice
show_menu() {
    while true; do
        echo
        echo "No-Code API Installation Menu"
        echo "============================"
        echo "1) Clean"
        echo "2) Create YAML files"
        echo "3) Install"
        echo "4) Clean & Install"
        echo "5) Clean, Create & Install"
        echo "q) Quit"
        echo
        read -p "Please select an option: " choice
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

# Main script execution
echo "No-Code API Installation Script"
echo "=============================="

# Start the menu
show_menu