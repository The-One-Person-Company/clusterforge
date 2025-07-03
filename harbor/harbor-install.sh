#!/bin/bash
#===============================================================================
#
# FILE: harbor-install.sh
#
# NAME: Harbor Private Registry Installer (Helm-based)
#
# USAGE: ./harbor-install.sh
#
# DESCRIPTION: Installs Harbor as a private container registry using Helm.
#              Generates values.yaml from template and runs helm install.
#
# AUTHOR: Vivien Roggero LLC
# CREATION DATE: 2024-12-19
# VERSION: 2.1
#
#===============================================================================

# ██████╗     ██╗      █████╗ ██████╗ 
# ██╔══██╗    ██║     ██╔══██╗██╔══██╗
# ██████╔╝    ██║     ███████║██████╔╝
# ██╔══██╗    ██║     ██╔══██║██╔══██╗
# ██║  ██║    ███████╗██║  ██║██████╔╝
# ╚═╝  ╚═╝    ╚══════╝╚═╝  ╚═╝╚═════╝ 

set -euo pipefail

# Get the absolute path of the script directory (harbor directory)
# This handles the case where the script is called from the root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source shared configuration and utilities
source "${WORKSPACE_DIR}/00-config.sh"

# --- Banner ---
print_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
    ██╗  ██╗ █████╗ ██████╗ ██████╗  ██████╗ ██████╗ 
    ██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔═══██╗██╔══██╗
    ███████║███████║██████╔╝██████╔╝██║   ██║██████╔╝
    ██╔══██║██╔══██║██╔══██╗██╔══██╗██║   ██║██╔══██╗
    ██║  ██║██║  ██║██║  ██║██████╔╝╚██████╔╝██║  ██║
    ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝         
         Private Registry Installer (Helm)
EOF
    echo -e "${NC}"
}

# Function to clean up Harbor resources
cleanup() {
    log STEP "Cleaning up Harbor resources..."
    log STEP "Deleting generated values.yaml and any old manifests."
    local yaml_files=(
        "harbor/harbor-values.yaml"
        "harbor/harbor-namespace.yaml"
        "harbor/harbor-pvc.yaml"
        "harbor/harbor-secret.yaml"        
        "harbor/harbor-service.yaml"
        "harbor/harbor-ingress.yaml"
        "harbor/harbor-certificate.yaml"
        "harbor/harbor-postgres-init-configmap.yaml"
        "harbor/harbor-postgres-init-job.yaml"

    )
    
    for file in "${yaml_files[@]}"; do
        local file_path="${WORKSPACE_DIR}/${file}"
        if [ -f "$file_path" ]; then
            log INFO "Deleting file: $file"
            rm -f "$file_path"
        fi
    done
    log INFO "Deleting Harbor release via Helm (if exists)..."
    microk8s helm uninstall harbor || true
    if microk8s kubectl get namespace "harbor" &>/dev/null; then
        microk8s kubectl delete namespace "harbor"
    fi
    log SUCCESS "Cleanup completed."
}

# Function to perform soft cleanup (preserving TLS and namespace)
soft_cleanup() {
    log STEP "Performing soft cleanup of Harbor resources..."
        
    # Delete generated YAML files except certificate
    log STEP "Deleting Generated .yaml files (except TLS-related)"
    local yaml_files=(
        "harbor/harbor-namespace.yaml"
        "harbor/harbor-pvc.yaml"
        "harbor/harbor-values.yaml"
        "harbor/harbor-service.yaml"
        "harbor/harbor-ingress.yaml"
        "harbor/harbor-postgres-init-configmap.yaml"
        "harbor/harbor-postgres-init-job.yaml"
        "harbor/harbor-secret.yaml"  
    )
    
    for file in "${yaml_files[@]}"; do
        local file_path="${WORKSPACE_DIR}/${file}"
        if [ -f "$file_path" ]; then
            log INFO "Deleting file: $file"
            rm -f "$file_path"
        fi
    done
    log INFO "Deleting generated values.yaml only."
    rm -f "${WORKSPACE_DIR}/harbor/values.yaml"
    log INFO "Deleting Harbor release via Helm (if exists)..."
    helm uninstall harbor || true
    log SUCCESS "Soft cleanup completed."
}

# Function to initialize YAML files from templates
init_yaml_files() {
    log STEP "Initializing YAML files from templates..."
    
    # Debug: Check if Harbor environment variables are loaded
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "DEBUG" "Checking Harbor environment variables:"
        log "DEBUG" "HARBOR_SUBDOMAIN: ${HARBOR_SUBDOMAIN:-NOT_SET}"
        log "DEBUG" "DOMAIN_BASE: ${DOMAIN_BASE:-NOT_SET}"
        log "DEBUG" "HARBOR_ADMIN_PASSWORD: ${HARBOR_ADMIN_PASSWORD:+SET}"
        log "DEBUG" "HARBOR_SECRET_KEY: ${HARBOR_SECRET_KEY:+SET}"
        log "DEBUG" "HARBOR_DATABASE_NAME: ${HARBOR_DATABASE_NAME:-NOT_SET}"
        log "DEBUG" "HARBOR_DATABASE_USER: ${HARBOR_DATABASE_USER:-NOT_SET}"
        log "DEBUG" "HARBOR_DATABASE_PASSWORD: ${HARBOR_DATABASE_PASSWORD:+SET}"
        log "DEBUG" "HARBOR_DATABASE_HOST: ${HARBOR_DATABASE_HOST:-NOT_SET}"
        log "DEBUG" "HARBOR_DATABASE_PORT: ${HARBOR_DATABASE_PORT:-NOT_SET}"
        log "DEBUG" "HARBOR_REDIS_HOST: ${HARBOR_REDIS_HOST:-NOT_SET}"
        log "DEBUG" "HARBOR_REDIS_PORT: ${HARBOR_REDIS_PORT:-NOT_SET}"
        log "DEBUG" "HARBOR_REDIS_PASSWORD: ${HARBOR_REDIS_PASSWORD:+SET}"
        log "DEBUG" "HARBOR_STORAGE_SIZE: ${HARBOR_STORAGE_SIZE:-NOT_SET}"
        log "DEBUG" "HARBOR_STORAGE_CLASS: ${HARBOR_STORAGE_CLASS:-NOT_SET}"
    fi
    
    # Validate required environment variables
    local required_vars=(
        "HARBOR_SUBDOMAIN"
        "DOMAIN_BASE"
        "HARBOR_ADMIN_PASSWORD"
        "HARBOR_SECRET_KEY"
        "HARBOR_DATABASE_NAME"
        "HARBOR_DATABASE_USER"
        "HARBOR_DATABASE_PASSWORD"
        "HARBOR_DATABASE_HOST"
        "HARBOR_DATABASE_PORT"
        "HARBOR_REDIS_HOST"
        "HARBOR_REDIS_PORT"
        "HARBOR_STORAGE_SIZE"
        "HARBOR_STORAGE_CLASS"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log "ERROR" "Missing required environment variables: ${missing_vars[*]}"
        log "ERROR" "Please check your .env file and ensure all Harbor variables are set."
        exit 1
    fi
    
    # Generate base64 encoded values for secrets
    export HARBOR_ADMIN_PASSWORD_B64=$(echo -n "${HARBOR_ADMIN_PASSWORD}" | base64)
    export HARBOR_SECRET_KEY_B64=$(echo -n "${HARBOR_SECRET_KEY}" | base64)
    export HARBOR_DATABASE_PASSWORD_B64=$(echo -n "${HARBOR_DATABASE_PASSWORD}" | base64)
    
    # List of template files to process
    local templates=(
        "harbor/harbor-namespace.yaml.template"
        "harbor/harbor-values.yaml.template"
        "harbor/harbor-pvc.yaml.template"
        "harbor/harbor-service.yaml.template"
        "harbor/harbor-ingress.yaml.template"
        "harbor/harbor-certificate.yaml.template"
        "harbor/harbor-postgres-init-configmap.yaml.template"
        "harbor/harbor-postgres-init-job.yaml.template"
        "harbor/harbor-secret.yaml.template"
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
    
    envsubst < "${WORKSPACE_DIR}/harbor/harbor-values.yaml.template" > "${WORKSPACE_DIR}/harbor/harbor-values.yaml"
    
    log SUCCESS "All YAML files initialized"
}

# --- Prerequisite Checks ---
check_prerequisites() {
    log "STEP" "Checking Harbor prerequisites..."
    
    # Check if database stack is installed
    if ! microk8s kubectl get namespace database >/dev/null 2>&1; then
        log "ERROR" "Database namespace not found. Please install the database stack first."
        exit 1
    fi
    
    # Check if PostgreSQL is running
    if ! microk8s kubectl get pods -n database -l app=postgres --field-selector=status.phase=Running | grep -q postgres; then
        log "ERROR" "PostgreSQL is not running. Please ensure the database stack is properly installed."
        exit 1
    fi
    
    # Check if Redis is running
    if ! microk8s kubectl get pods -n database -l app=redis --field-selector=status.phase=Running | grep -q redis; then
        log "ERROR" "Redis is not running. Please ensure the database stack is properly installed."
        exit 1
    fi
    
    if ! command -v helm >/dev/null 2>&1; then
        log "ERROR" "Helm is not installed. Please install Helm to continue."
        exit 1
    fi
    
    log "SUCCESS" "Prerequisites met."
}

# --- Database Setup ---
setup_database() {
    log "STEP" "Setting up Harbor database..."
    
    # Debug: Check if Harbor database variables are loaded
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "DEBUG" "Checking Harbor database environment variables:"
        log "DEBUG" "HARBOR_DATABASE_NAME: ${HARBOR_DATABASE_NAME:-NOT_SET}"
        log "DEBUG" "HARBOR_DATABASE_USER: ${HARBOR_DATABASE_USER:-NOT_SET}"
        log "DEBUG" "HARBOR_DATABASE_PASSWORD: ${HARBOR_DATABASE_PASSWORD:+SET}"
    fi
    
    # Validate required Harbor database variables
    if [ -z "${HARBOR_DATABASE_NAME:-}" ]; then
        log "ERROR" "HARBOR_DATABASE_NAME is not set. Please check your .env file."
        exit 1
    fi
    
    if [ -z "${HARBOR_DATABASE_USER:-}" ]; then
        log "ERROR" "HARBOR_DATABASE_USER is not set. Please check your .env file."
        exit 1
    fi
    
    if [ -z "${HARBOR_DATABASE_PASSWORD:-}" ]; then
        log "ERROR" "HARBOR_DATABASE_PASSWORD is not set. Please check your .env file."
        exit 1
    fi
    
    # Create Harbor database and user using PostgreSQL initialization job
    log "INFO" "Creating Harbor database and user via initialization job..."
    
    # Clean up any existing job first (jobs are immutable)
    if microk8s kubectl get job harbor-postgres-init -n harbor >/dev/null 2>&1; then
        log "INFO" "Removing existing PostgreSQL initialization job..."
        execute_command "Removing existing PostgreSQL init job" "microk8s kubectl delete job harbor-postgres-init -n harbor"
    fi
    
    # Clean up any existing ConfigMap
    if microk8s kubectl get configmap harbor-postgres-init-script -n harbor >/dev/null 2>&1; then
        log "INFO" "Removing existing PostgreSQL initialization ConfigMap..."
        execute_command "Removing existing PostgreSQL init ConfigMap" "microk8s kubectl delete configmap harbor-postgres-init-script -n harbor"
    fi
    
    # Generate the PostgreSQL initialization files
    envsubst < "${SCRIPT_DIR}/harbor/harbor-postgres-init-configmap.yaml.template" > "${SCRIPT_DIR}/harbor/harbor-postgres-init-configmap.yaml"
    envsubst < "${SCRIPT_DIR}/harbor/harbor-postgres-init-job.yaml.template" > "${SCRIPT_DIR}/harbor/harbor-postgres-init-job.yaml"
    
    # Apply the ConfigMap
    execute_command "Creating Harbor PostgreSQL init ConfigMap" "microk8s kubectl apply -n harbor -f ${SCRIPT_DIR}/harbor/harbor-postgres-init-configmap.yaml"
    
    # Apply the initialization job
    execute_command "Creating Harbor PostgreSQL init job" "microk8s kubectl apply -n harbor -f ${SCRIPT_DIR}/harbor/harbor-postgres-init-job.yaml"
    
    # Wait for the job to complete
    log "INFO" "Waiting for PostgreSQL initialization job to complete..."
    execute_command "Waiting for PostgreSQL init job" "microk8s kubectl wait --for=condition=complete job/harbor-postgres-init -n harbor --timeout=300s"
    
    # Check if the job was successful
    local job_status
    job_status=$(microk8s kubectl get job harbor-postgres-init -n harbor -o jsonpath="{.status.conditions[?(@.type=='Complete')].status}")

if [ "$job_status" != "True" ]; then
    log "ERROR" "PostgreSQL initialization job failed or not completed yet. Check logs for details."
    microk8s kubectl logs job/harbor-postgres-init -n harbor
    exit 1
fi

log "SUCCESS" "Harbor database setup complete."
}

# --- Install Harbor ---
install_harbor() {
    log STEP "Installing Harbor via Helm..."
    log INFO "Running: helm install harbor -n harbor -f harbor/harbor-values.yaml harbor/harbor"
    microk8s helm repo add harbor https://helm.goharbor.io
    microk8s helm repo update
    microk8s helm install harbor -n harbor -f "${WORKSPACE_DIR}/harbor/harbor-values.yaml" harbor/harbor
    log SUCCESS "Harbor installation complete."
}

# --- Wait for Deployment ---
wait_for_deployment() {
    log "STEP" "Waiting for Harbor to be ready..."
    
    # Wait for deployment to be available
    execute_command "Waiting for Harbor deployment" "microk8s kubectl wait --for=condition=available -l app.kubernetes.io/instance=harbor -n harbor deployment --timeout=600s"
    
    # Wait for all pods to be ready
    execute_command "Waiting for Harbor pods" "microk8s kubectl wait --for=condition=ready pod -l app=harbor -n harbor --timeout=300s"
    
    log "SUCCESS" "Harbor is ready."
}

# --- Display Access Information ---
display_access_info() {
    log "STEP" "Harbor Access Information"
    echo
    log "SUCCESS" "Harbor has been successfully installed!"
    echo
    log "INFO" "Access Information:"
    log "INFO" "  Web UI: https://${HARBOR_SUBDOMAIN}.${DOMAIN_BASE}"
    log "INFO" "  Registry: ${HARBOR_SUBDOMAIN}.${DOMAIN_BASE}"
    echo
    log "INFO" "Default Credentials:"
    log "INFO" "  Username: admin"
    log "INFO" "  Password: ${HARBOR_ADMIN_PASSWORD}"
    echo
    log "INFO" "Docker Login Command:"
    log "INFO" "  docker login ${HARBOR_SUBDOMAIN}.${DOMAIN_BASE}"
    echo
    log "WARN" "Please change the default admin password after first login."
    echo
}

# --- Cleanup ---
cleanup_temp_files() {
    log "STEP" "Cleaning up temporary files..."
    rm -f "${WORKSPACE_DIR}/harbor/harbor-service.yaml"
    rm -f "${WORKSPACE_DIR}/harbor/harbor-certificate.yaml"
    rm -f "${WORKSPACE_DIR}/harbor/harbor-ingress.yaml" 
    rm -f "${WORKSPACE_DIR}/harbor/values.yaml"
    rm -f "${WORKSPACE_DIR}/harbor/harbor-postgres-init-configmap.yaml" "${WORKSPACE_DIR}/harbor/harbor-postgres-init-job.yaml"
    log "SUCCESS" "Cleanup complete."
}

# --- Delete Harbor Database and User ---
delete_harbor_database() {
    echo
    echo "WARNING: This will DELETE the Harbor database and user in Postgres."
    echo "All Harbor data will be lost."
    read -p "Are you sure you want to continue? (yes/NO): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Aborted."
        return
    fi
    POSTGRES_POD=$(microk8s kubectl get pod -n database -l app=postgres -o jsonpath='{.items[0].metadata.name}')
    if [[ -z "$POSTGRES_POD" ]]; then
        echo "Could not find Postgres pod in 'database' namespace."
        return 1
    fi
    echo "Dropping Harbor database and user..."
    microk8s kubectl exec -n database "$POSTGRES_POD" -- bash -c "psql -U postgres -c \"DROP DATABASE IF EXISTS $HARBOR_DATABASE_NAME; DROP USER IF EXISTS $HARBOR_DATABASE_USER;\""
    echo "Database and user deleted. You may now re-run the install to re-create them."
}

# --- Force Clear Dirty Migration Flag ---
force_clear_dirty_migration() {
    echo
    echo "This will clear the 'dirty' flag in the Harbor database migration table."
    echo "Use this only if you see a 'Dirty database version' error."
    read -p "Are you sure you want to continue? (yes/NO): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Aborted."
        return
    fi
    POSTGRES_POD=$(microk8s kubectl get pod -n database -l app=postgres -o jsonpath='{.items[0].metadata.name}')
    if [[ -z "$POSTGRES_POD" ]]; then
        echo "Could not find Postgres pod in 'database' namespace."
        return 1
    fi
    echo "Connecting to Harbor database to clear dirty flag..."
    microk8s kubectl exec -n database "$POSTGRES_POD" -- bash -c "psql -U $HARBOR_DATABASE_USER -d $HARBOR_DATABASE_NAME -c \"UPDATE schema_migrations SET dirty = false WHERE dirty = true;\""
    echo "Dirty flag cleared. You may now restart Harbor pods."
}

# --- Install Function ---
install() {
    log STEP "Starting Harbor installation (Helm)"
    check_prerequisites
    init_yaml_files
    log "INFO" "Creating Harbor namespace..."
    execute_command "Creating Harbor namespace" "microk8s kubectl apply -f ${SCRIPT_DIR}/harbor/harbor-namespace.yaml"
    log "INFO" "Creating Harbor secret..."
    execute_command "Creating Harbor secret" "microk8s kubectl apply -f ${SCRIPT_DIR}/harbor/harbor-secret.yaml"
    setup_database
    log "INFO" "Applying Harbor PVC..."
    microk8s kubectl apply -n harbor -f "${WORKSPACE_DIR}/harbor/harbor-pvc.yaml"
    log "INFO" "Creating Harbor service..."
    execute_command "Creating Harbor service" "microk8s kubectl apply -n harbor -f ${SCRIPT_DIR}/harbor/harbor-service.yaml"
    log "INFO" "Creating Harbor certificate..."
    execute_command "Creating Harbor certificate" "microk8s kubectl apply -n harbor -f ${SCRIPT_DIR}/harbor/harbor-certificate.yaml"
    install_harbor
    wait_for_deployment
    display_access_info
    cleanup_temp_files
    log SUCCESS "Harbor installation completed successfully!"
    echo
    echo "Pod Status:"
    echo "==========="
    microk8s kubectl get pods -n harbor
}

# --- Print Harbor Status ---
print_harbor_status() {
    echo -e "\n\033[1;36mCurrent Harbor Status:\033[0m"
    if microk8s kubectl get ns harbor &>/dev/null; then
        echo -e "  \U1F4C2 Namespace:      \033[1;32mExists\033[0m"
        echo -e "  \U1F4E6 Pods:           $(microk8s kubectl get pods -n harbor --no-headers | wc -l)"
        microk8s kubectl get pods -n harbor --no-headers | awk '{print "    • "$1, $2, $3}'
        echo -e "  \U1F310 Ingress:        $(microk8s kubectl get ingress -n harbor --no-headers | wc -l)"
        microk8s kubectl get ingress -n harbor --no-headers | awk '{print "    • "$1, $3}'
        echo -e "  \U1F512 Certificate:    $(microk8s kubectl get certificate -n harbor --no-headers | wc -l)"
        microk8s kubectl get certificate -n harbor --no-headers | awk '{print "    • "$1, $2, $3}'
    else
        echo -e "  \U274C Harbor namespace does not exist."
    fi
    echo
}

# --- Modernized Menu ---
show_menu() {
    clear
    print_banner
    print_harbor_status
    while true; do
        echo -e "\033[1;34m╔══════════════════════════════════════════════════════════════════════════════╗\033[0m"
        echo -e "\033[1;34m║                        \U1F680  Harbor Installation Manager  \U1F680                      ║\033[0m"
        echo -e "\033[1;34m╠══════════════════════════════════════════════════════════════════════════════╣\033[0m"
        echo -e "\033[1;33m║  \U1F527  INSTALLATION ACTIONS                                              ║\033[0m"
        echo -e "\033[1;34m║──────────────────────────────────────────────────────────────────────────────║\033[0m"
        echo -e "║  1) 🧹  Full Clean (delete everything, including namespace)                  ║"
        echo -e "║  2) 🧹  Soft Clean (preserve TLS and namespace)                             ║"
        echo -e "║  3) 📝  Generate YAML from templates                                        ║"
        echo -e "║  4) 🚀  Install/Upgrade Harbor (Helm)                                       ║"
        echo -e "║  5) 🧹  Soft Clean, 📝 Generate & 🚀 Install                                 ║"
        echo -e "║  6) 🧹  Full Clean, 📝 Generate & 🚀 Install                                 ║"
        echo -e "\033[1;33m║  \U1F6E1  RECOVERY & MAINTENANCE                                            ║\033[0m"
        echo -e "\033[1;34m║──────────────────────────────────────────────────────────────────────────────║\033[0m"
        echo -e "║  7) ❌  Delete Harbor database and user (DANGEROUS)                         ║"
        echo -e "║  8) 🛠️   Force clear dirty migration flag                                   ║"
        echo -e "\033[1;33m║  \U1F4D6  INFORMATION                                                      ║\033[0m"
        echo -e "\033[1;34m║──────────────────────────────────────────────────────────────────────────────║\033[0m"
        echo -e "║  i) ℹ️   Show Info & Version                                               ║"
        echo -e "║  q) ❌  Quit                                                               ║"
        echo -e "\033[1;34m╚══════════════════════════════════════════════════════════════════════════════╝\033[0m"
        echo
        read -p $'\033[1;32mSelect an option:\033[0m ' choice
        echo
        case $choice in
            1) cleanup ;;
            2) soft_cleanup ;;
            3) init_yaml_files ;;
            4) install ;;
            5) soft_cleanup; init_yaml_files; install ;;
            6) cleanup; init_yaml_files; install ;;
            7) delete_harbor_database ;;
            8) force_clear_dirty_migration ;;
            i|I)
                print_banner
                read -p $'\033[1;36mPress Enter to return to menu...\033[0m'
                ;;
            q|Q)
                echo -e "\033[1;31mExiting...\033[0m"; exit 0 ;;
            *)
                echo -e "\033[1;31mInvalid option. Please try again.\033[0m" ;;
        esac
    done
}

# --- Main Execution ---
clear
print_banner
show_menu 