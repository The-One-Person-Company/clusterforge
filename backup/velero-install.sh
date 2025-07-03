#!/bin/bash
#===============================================================================
#
# FILE: velero-install.sh
#
# NAME: Velero
#
# USAGE: ./velero-install.sh
#
# DESCRIPTION: Installation script for Velero backup and restore on Kubernetes.
#              Deploys and configures Velero and its dependencies.
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

VELERO_UI_DOMAIN=${VELERO_SUBDOMAIN}.${DOMAIN_BASE}

# Banner
print_banner() {
    echo -e "\033[36m"
    cat << "EOF"
    ██╗   ██╗███████╗██╗     ███████╗██████╗  ██████╗ 
    ██║   ██║██╔════╝██║     ██╔════╝██╔══██╗██╔═══██╗
    ██║   ██║█████╗  ██║     █████╗  ██████╔╝██║   ██║
    ╚██╗ ██╔╝██╔══╝  ██║     ██╔══╝  ██╔══██╗██║   ██║
     ╚████╔╝ ███████╗███████╗███████╗██║  ██║╚██████╔╝
      ╚═══╝  ╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝                                                       
         Velero Installer (v2.0)
EOF
    echo -e "\033[0m"
}

clear
print_banner

# Function to create namespace if it doesn't exist
create_namespace() {
    local namespace=$1
    if ! microk8s kubectl get namespace $namespace &> /dev/null; then
        log "Creating namespace: $namespace"
        microk8s kubectl create namespace $namespace
    fi
}

# Function to apply configuration files
apply_config() {
    local file=$1
    log "Applying configuration: $file"
    microk8s kubectl apply -f $file
}

# Function to clean up Velero resources
cleanup() {
    log STEP "Cleaning up Velero resources..."
    
    # Delete namespace without waiting
    log INFO "Deleting existing namespace..."
    microk8s kubectl delete namespace velero --ignore-not-found=true

    # Clean up temp directory if it exists
    TMP_DIR="${SCRIPT_DIR}/backup/tmp"
    if [ -d "$TMP_DIR" ]; then
        log INFO "Removing temp directory: $TMP_DIR"
        rm -rf "$TMP_DIR"
    fi
    
    log SUCCESS "Cleanup initiated"
}

# Function to initialize YAML files from templates
init_yaml_files() {
    log STEP "Initializing YAML files from templates..."
    
    # List of template files to process
    local templates=(
        "backup/velero-credentials.yaml.template"
        "backup/velero-schedule.yaml.template"
        "backup/velero-retention.yaml.template"
        "backup/vui-single-cluster.yaml.template"
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

# Function to install Velero
install() {
    log STEP "Starting Velero installation"

    # Create temp directory for sensitive files
    TMP_DIR="${SCRIPT_DIR}/backup/tmp"
    mkdir -p "$TMP_DIR"

    # Create namespace
    log INFO "Creating velero namespace..."
    microk8s kubectl create namespace velero --dry-run=client -o yaml | microk8s kubectl apply -f -

    # Fetch latest Velero CLI version
    log INFO "Fetching latest Velero CLI version..."
    VELERO_VERSION=$(curl -s https://api.github.com/repos/vmware-tanzu/velero/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    log INFO "Latest Velero version is v${VELERO_VERSION}"

    # Download Velero CLI
    log INFO "Downloading Velero CLI..."
    wget "https://github.com/vmware-tanzu/velero/releases/download/v${VELERO_VERSION}/velero-v${VELERO_VERSION}-linux-amd64.tar.gz"
    tar -xvf "velero-v${VELERO_VERSION}-linux-amd64.tar.gz"
    sudo mv "velero-v${VELERO_VERSION}-linux-amd64/velero" /usr/local/bin/
    rm -rf "velero-v${VELERO_VERSION}-linux-amd64"*

    # Create credentials file from template
    log INFO "Creating MinIO credentials file from template..."
    envsubst < "${SCRIPT_DIR}/backup/minio-credentials.template" > "$TMP_DIR/minio-credentials"

    # Apply Velero configurations
    log INFO "Applying Velero configurations..."
    microk8s kubectl apply -f "backup/velero-credentials.yaml"

    # Get MicroK8s kubeconfig
    log INFO "Getting MicroK8s kubeconfig..."
    microk8s config > "$TMP_DIR/kubeconfig"

    # Install Velero
    log INFO "Installing Velero..."
    KUBECONFIG="$TMP_DIR/kubeconfig" velero install \
        --provider aws \
        --plugins velero/velero-plugin-for-aws:v1.7.0 \
        --bucket ${MINIO_BUCKET} \
        --backup-location-config region=${MINIO_REGION},s3ForcePathStyle=true,s3Url=https://${MINIO_DOMAIN} \
        --secret-file "$TMP_DIR/minio-credentials" \
        --namespace velero \
        --wait \
        --image velero/velero:v${VELERO_VERSION} \
        --upgrade

    # Apply backup schedules
    log INFO "Applying backup schedules..."
    microk8s kubectl apply -f "backup/velero-schedule.yaml"

    # Create initial backup
    log INFO "Creating initial backup..."
    if ! KUBECONFIG="$TMP_DIR/kubeconfig" velero backup get initial-backup --namespace velero &> /dev/null; then
        KUBECONFIG="$TMP_DIR/kubeconfig" velero backup create initial-backup --wait
    else
        log INFO "Initial backup already exists, skipping creation."
    fi

    # Clean up temporary files and folder
    rm -rf "$TMP_DIR"

    # Install VUI via Helm
    log INFO "Installing VUI via Helm..."
    microk8s helm3 repo add seriohub https://seriohub.github.io/velero-helm || true
    microk8s helm3 repo update
    microk8s helm3 upgrade --install vui seriohub/vui \
      -n velero \
      --create-namespace \
      -f backup/vui-single-cluster.yaml

    log SUCCESS "Velero installation complete!"
    
    # Print backup information
    echo "Backup Information:"
    echo "------------------"
    echo "Storage Location: MinIO (${MINIO_DOMAIN})"
    echo "Bucket: ${MINIO_BUCKET}"
    echo "Backup Schedule:"
    echo "  - Daily: 1 AM (retention: 7 days)"
    echo "  - Weekly: 1 AM every Sunday (retention: 7 weeks)"
    echo "  - Monthly: 1 AM on 1st of month (retention: 12 months)"
    echo "Included Namespaces: all"
}

# Display menu and handle user choice
show_menu() {
    while true; do
        echo
        echo "╔════════════════════════════════════════════════════════════════════╗"
        echo "║                  Velero Installation Manager                     ║"
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
                echo "Description: Velero installer for TOPC Automation Server."
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

# Main script execution
echo "Velero Installation Script"
echo "========================="

# Start the menu
show_menu 