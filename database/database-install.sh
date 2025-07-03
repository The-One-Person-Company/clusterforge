#!/bin/bash
#===============================================================================
#
# FILE: database-install.sh
#
# NAME: Database Installer
#
# USAGE: ./database-install.sh
#
# DESCRIPTION: Installation script for core database services on Kubernetes,
#              including Postgres, Redis, and RabbitMQ.
#
# AUTHOR: Vivien Roggero LLC
# MODIFIED BY: Gemini
# CREATION DATE: 2024-08-01
# LAST MODIFIED: 2024-08-01
# VERSION: 2.0
#
#===============================================================================
set -euo pipefail

# Get the absolute path of the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load shared config and env
source "${WORKSPACE_DIR}/00-config.sh"

# --- Banner ---
print_banner() {
    echo -e "\033[36m"
    cat << "EOF"
    ██████╗  █████╗ ████████╗ █████╗ ██████╗  █████╗ ███████╗███████╗
    ██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔════╝
    ██║  ██║███████║   ██║   ███████║██████╔╝███████║███████╗███████╗
    ██║  ██║██╔══██║   ██║   ██╔══██║██╔══██╗██╔══██║╚════██║╚════██║
    ██████╔╝██║  ██║   ██║   ██║  ██║██████╔╝██║  ██║███████║███████║
    ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝
                     Database Installer (v2.0)
EOF
    echo -e "\033[0m"
}

# --- Core Functions ---

# Creates the 'database' namespace if it doesn't exist
create_namespace() {
    if ! microk8s kubectl get namespace database &> /dev/null; then
        log_info "Creating namespace: database"
        microk8s kubectl create namespace database
    fi
}

# Renders a YAML file from a template using envsubst
render_template() {
    local template_file="$1"
    local output_file="$2"
    log_info "Rendering template ${template_file}..."
    envsubst < "${WORKSPACE_DIR}/${template_file}" > "${WORKSPACE_DIR}/${output_file}"
    log_success "Created ${output_file}"
}

# Applies a Kubernetes manifest
apply_config() {
    log_info "Applying ${1}..."
    microk8s kubectl apply -f "${WORKSPACE_DIR}/${1}"
}

# Generates all necessary YAML files from their templates
init_yaml_files() {
    log_step "Initializing all YAML files from templates..."
    local templates=(
        "database/db-secret.yaml.template"
        "database/db-pvc.yaml.template"
        "database/postgres-deployment.yaml.template"
        "database/postgres-init-configmap.yaml.template"
        "database/redis-deployment.yaml.template"
        "database/rabbitmq-deployment.yaml.template"
        "database/rabbitmq-ingress.yaml.template"
        "database/rabbitmq-pvc.yaml.template"
        "database/rabbitmq-certificate.yaml.template"
        "database/minio-pvc.yaml.template"
        "database/minio-deployment.yaml.template"
        "database/minio-api-ingress.yaml.template"
        "database/minio-console-ingress.yaml.template"
        "database/minio-api-certificate.yaml.template"
        "database/minio-console-certificate.yaml.template"
    )
    for template in "${templates[@]}"; do
        render_template "$template" "${template%.template}"
    done
    log_success "All YAML files initialized."
}

# Apply only the RabbitMQ PVC
apply_rabbitmq_pvc() {
    render_template "database/rabbitmq-pvc.yaml.template" "database/rabbitmq-pvc.yaml"
    log_info "Applying RabbitMQ PVC..."
    microk8s kubectl apply -f "${WORKSPACE_DIR}/database/rabbitmq-pvc.yaml" -n database
    log_success "RabbitMQ PVC applied."
}

# Installs a specific database component
install() {
    local component=$1
    log_step "Installing ${component}..."
    create_namespace

    case $component in
        postgres)
            apply_config "database/postgres-deployment.yaml"
            apply_config "database/postgres-init-configmap.yaml"
            ;;
        redis)
            apply_config "database/redis-deployment.yaml"
            ;;
        rabbitmq)
            apply_rabbitmq_pvc
            apply_config "database/rabbitmq-certificate.yaml"
            apply_config "database/rabbitmq-deployment.yaml"
            apply_config "database/rabbitmq-ingress.yaml"
            ;;
        minio)
            apply_config "database/minio-pvc.yaml"
            apply_config "database/minio-deployment.yaml"
            apply_config "database/minio-api-certificate.yaml"
            apply_config "database/minio-api-ingress.yaml"
            apply_config "database/minio-console-certificate.yaml"
            apply_config "database/minio-console-ingress.yaml"
            ;;
        all)
            install postgres
            install redis
            apply_rabbitmq_pvc
            install rabbitmq
            install minio
            ;;
        *)
            log_error "Unknown component for install: $component"
            exit 1
            ;;
    esac
    log_success "Installation of ${component} complete."
}

# Cleans up resources for a specific component
cleanup() {
    local component=$1
    log_step "Cleaning up ${component} resources..."

    case $component in
        postgres)
            microk8s kubectl delete deployment postgres-deployment -n database --ignore-not-found=true
            microk8s kubectl delete service postgres-service -n database --ignore-not-found=true
            microk8s kubectl delete pvc postgres-pvc -n database --ignore-not-found=true
            microk8s kubectl delete configmap postgres-init-config -n database --ignore-not-found=true
            microk8s kubectl delete job postgres-init-job -n database --ignore-not-found=true
            ;;
        redis)
            microk8s kubectl delete deployment redis-deployment -n database --ignore-not-found=true
            microk8s kubectl delete service redis-service -n database --ignore-not-found=true
            microk8s kubectl delete pvc redis-pvc -n database --ignore-not-found=true
            ;;
        rabbitmq)
            microk8s kubectl delete deployment rabbitmq-deployment -n database --ignore-not-found=true
            microk8s kubectl delete service rabbitmq-service -n database --ignore-not-found=true
            microk8s kubectl delete pvc rabbitmq-pvc -n database --ignore-not-found=true
            microk8s kubectl delete ingress rabbitmq-ingress -n database --ignore-not-found=true
            microk8s kubectl delete certificate rabbitmq-tls -n database --ignore-not-found=true
            ;;
        minio)
            microk8s kubectl delete deployment minio-deployment -n database --ignore-not-found=true
            microk8s kubectl delete service minio-service -n database --ignore-not-found=true
            microk8s kubectl delete pvc minio-pvc -n database --ignore-not-found=true
            microk8s kubectl delete ingress minio-api-ingress -n database --ignore-not-found=true
            microk8s kubectl delete ingress minio-console-ingress -n database --ignore-not-found=true
            microk8s kubectl delete certificate minio-api-tls -n database --ignore-not-found=true
            microk8s kubectl delete certificate minio-console-tls -n database --ignore-not-found=true
            ;;
        all)
            log_info "Cleaning all database components..."
            cleanup postgres
            cleanup redis
            cleanup rabbitmq
            cleanup minio
            log_info "Deleting shared resources and namespace..."
            microk8s kubectl delete secret db-secret -n database --ignore-not-found=true
            microk8s kubectl delete namespace database --ignore-not-found=true
            ;;
        *)
            log_error "Unknown component for cleanup: $component"
            exit 1
            ;;
    esac
    log_success "Cleanup of ${component} complete."
}

# --- Menu ---
show_menu() {
    clear
    print_banner
    while true; do
        echo
        echo "╔════════════════════════════════════════════════════════════════════╗"
        echo "║                  Database Installation Manager                   ║"
        echo "╠════════════════════════════════════════════════════════════════════╣"
        echo "║   INSTALL                                                        ║"
        echo "║──────────────────────────────────────────────────────────────────║"
        echo "║  1) 💾  Postgres   2) 💾  Redis   3) 🐇  RabbitMQ   4) 🗄️  MinIO   ║"
        echo "║  5) 🚀  Install All Databases                                    ║"
        echo "║──────────────────────────────────────────────────────────────────║"
        echo "║   PVCs                                                           ║"
        echo "║──────────────────────────────────────────────────────────────────║"
        echo "║  p) 📦  Apply RabbitMQ PVC                                       ║"
        echo "║──────────────────────────────────────────────────────────────────║"
        echo "║   CLEANUP                                                        ║"
        echo "║──────────────────────────────────────────────────────────────────║"
        echo "║  c1) 🧹 Clean Postgres  c2) 🧹 Clean Redis  c3) 🧹 Clean RabbitMQ  ║"
        echo "║  c4) 🧹 Clean MinIO     c5) 🧹 Clean All                          ║"
        echo "║──────────────────────────────────────────────────────────────────║"
        echo "║   OTHER                                                          ║"
        echo "║──────────────────────────────────────────────────────────────────║"
        echo "║  y) 📝  Generate YAML files                                      ║"
        echo "║  i) ℹ️   Show Info & Version                                      ║"
        echo "║  q) ❌  Quit                                                     ║"
        echo "╚════════════════════════════════════════════════════════════════════╝"
        echo
        read -p "Select an option: " choice
        echo
        case $choice in
            1) install postgres ;;
            2) install redis ;;
            3) install rabbitmq ;;
            4) install minio ;;
            5) init_yaml_files; install all ;;
            p|P) apply_rabbitmq_pvc ;;
            c1) cleanup postgres ;;
            c2) cleanup redis ;;
            c3) cleanup rabbitmq ;;
            c4) cleanup minio ;;
            c5) cleanup all ;;
            y|Y) init_yaml_files ;;
            i|I)
                print_banner
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

# --- Main Execution ---
show_menu 