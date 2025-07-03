#!/bin/bash
#===============================================================================
#
# FILE: monitoring-install.sh
#
# NAME: Monitoring Installer
#
# USAGE: ./monitoring-install.sh
#
# DESCRIPTION: Installation script for Prometheus, Grafana, Loki, and exporters
#              on Kubernetes. Deploys and configures the monitoring stack.
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
export GRAFANA_DOMAIN="${GRAFANA_SUBDOMAIN}.${DOMAIN_BASE}"
export PROMETHEUS_DOMAIN="${PROMETHEUS_SUBDOMAIN}.${DOMAIN_BASE}"

# --- Logging ---
# Uses log, log_step, log_info, log_success, log_error from 00-config.sh

# --- Banner ---
print_banner() {
    echo -e "\033[36m"
    cat << "EOF"
    ███╗   ███╗ ██████╗ ███╗   ██╗██╗████████╗ ██████╗ ██████╗ ██╗███╗   ██╗ ██████╗ 
    ████╗ ████║██╔═══██╗████╗  ██║██║╚══██╔══╝██╔═══██╗██╔══██╗██║████╗  ██║██╔════╝ 
    ██╔████╔██║██║   ██║██╔██╗ ██║██║   ██║   ██║   ██║██████╔╝██║██╔██╗ ██║██║  ███╗
    ██║╚██╔╝██║██║   ██║██║╚██╗██║██║   ██║   ██║   ██║██╔══██╗██║██║╚██╗██║██║   ██║
    ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║██║   ██║   ╚██████╔╝██║  ██║██║██║ ╚████║╚██████╔╝
    ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝ 
                        Monitoring Installer (v2.0)
EOF
    echo -e "\033[0m"
}

# Function to create namespace if it doesn't exist
create_namespace() {
    local namespace=$1
    if ! microk8s kubectl get namespace $namespace &> /dev/null; then
        log INFO "Creating namespace: $namespace"
        microk8s kubectl create namespace $namespace
    fi
}

# Function to apply configuration files
apply_config() {
    local file=$1
    log INFO "Applying configuration: $file"
    microk8s kubectl apply -f $file
}

# Function to create a secret for postgres-exporter
create_postgres_exporter_secret() {
    log INFO "Creating secret for postgres-exporter..."
    microk8s kubectl create secret generic postgres-exporter-secret \
        --from-literal=password="${POSTGRES_EXPORTER_PASSWORD}" \
        -n monitoring --dry-run=client -o yaml | microk8s kubectl apply -f -
}

# Function to clean up monitoring resources
cleanup() {
    log STEP "Cleaning up monitoring resources..."
    
    # Delete generated files
    local yaml_files=(
        "monitoring/monitoring-ingress.yaml"
        "monitoring/monitoring-certificate.yaml"
        "monitoring/monitoring-datasources.yaml"
        "monitoring/monitoring-dashboards.yaml"
        "monitoring/postgres-exporter-user-creation.yaml"
    )
    
    for file in "${yaml_files[@]}"; do
        local file_path="${WORKSPACE_DIR}/${file}"
        if [ -f "$file_path" ]; then
            log INFO "Deleting file: $file"
            rm -f "$file_path"
        fi
    done
    
    # Delete namespace without waiting
    log INFO "Deleting existing namespace..."
    microk8s kubectl delete namespace monitoring --ignore-not-found=true
    
    log SUCCESS "Cleanup initiated"
}

# Function to initialize YAML files from templates
init_yaml_files() {
    log STEP "Initializing YAML files from templates..."
    
    # List of template files to process
    local templates=(
        "monitoring/monitoring-datasources.yaml.template"
        "monitoring/monitoring-dashboards.yaml.template"
        "monitoring/monitoring-ingress.yaml.template"
        "monitoring/monitoring-certificate.yaml.template"
        "monitoring/postgres-exporter-user-creation.yaml.template"
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

# Function to install monitoring stack
install() {
    log STEP "Starting monitoring stack installation"

    # Create namespace
    log INFO "Creating monitoring namespace..."
    microk8s kubectl create namespace monitoring --dry-run=client -o yaml | microk8s kubectl apply -f -

    # Create postgres-exporter secret
    create_postgres_exporter_secret

    # Add and update Helm repositories
    log INFO "Setting up Helm repositories..."
    microk8s helm3 repo add prometheus-community https://prometheus-community.github.io/helm-charts
    microk8s helm3 repo add grafana https://grafana.github.io/helm-charts
    microk8s helm3 repo add kubecost https://kubecost.github.io/cost-analyzer/
    microk8s helm3 repo update

    # Install Prometheus
    log INFO "Installing Prometheus..."
    microk8s helm3 upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --set grafana.enabled=true \
        --set grafana.service.name=grafana-svc \
        --set prometheus-server.service.name=prometheus-svc \
        --set grafana.adminPassword=${GRAFANA_ADMIN_PASSWORD} \
        --set grafana.plugins[0]=redis-datasource \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.probeSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.retention=15d \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=microk8s-hostpath \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.accessModes[0]=ReadWriteOnce \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=10Gi \
        --set grafana.ingress.enabled=false \
        --set grafana.env.GF_SERVER_PROTOCOL=http \
        --set grafana.env.GF_SERVER_ROOT_URL=https://grafana.theoneperson.company \
        --set grafana.env.GF_SERVER_DOMAIN=grafana.theoneperson.company

    # Install Loki
    log INFO "Installing Loki..."
    microk8s helm3 upgrade --install loki grafana/loki-stack \
        --namespace monitoring \
        --set grafana.enabled=false,loki.persistence.enabled=true,loki.persistence.storageClassName=microk8s-hostpath,loki.persistence.size=10Gi

    # Install postgres-exporter
    log INFO "Installing postgres-exporter..."
    microk8s kubectl apply -f monitoring/postgres-exporter-user-creation.yaml
    microk8s helm3 upgrade --install postgres-exporter prometheus-community/prometheus-postgres-exporter \
        --namespace monitoring \
        --set config.datasource.host=postgres.database.svc.cluster.local \
        --set config.datasource.user=postgres-exporter \
        --set config.datasource.password.secretName=postgres-exporter-secret \
        --set config.datasource.password.secretKey=password \
        --set config.datasource.database=n8n \
        --set config.datasource.sslmode=disable \
        --set serviceMonitor.enabled=true

    # Install Kube-cost
    log INFO "Installing Kubecost..."
    microk8s helm3 upgrade --install kubecost kubecost/cost-analyzer \
        --namespace monitoring \
        --set kubecostToken="${KUBECOST_TOKEN}" \
        --set global.grafana.enabled=false \
        --set prometheus.enabled=false \
        --set global.prometheus.enabled=false \
        --set global.prometheus.server="http://prometheus-svc.monitoring.svc.cluster.local:9090" \
        --set network-cni.enabled=true,network-costs.enabled=true

    # Apply monitoring configurations
    log INFO "Applying monitoring configurations..."
    microk8s kubectl apply -f monitoring/monitoring-certificate.yaml
    microk8s kubectl apply -f monitoring/monitoring-ingress.yaml
    microk8s kubectl apply -f monitoring/monitoring-datasources.yaml
    microk8s kubectl apply -f monitoring/monitoring-dashboards.yaml

    # Wait for Grafana to be ready
    log INFO "Waiting for Grafana to be ready..."
    until microk8s kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].status.phase}' | grep -q "Running"; do
        log INFO "Waiting for Grafana pod to be ready..."
        sleep 5
    done

    # Install custom dashboards
    log INFO "Installing custom dashboards..."
    bash "${SCRIPT_DIR}/monitoring/install-dashboards.sh"

    log SUCCESS "Monitoring stack installation complete!"
    
    # Print access information
    echo "Monitoring Access:"
    echo "Grafana URL: https://${GRAFANA_DOMAIN}"
    echo "Prometheus URL: https://${PROMETHEUS_DOMAIN}"
    echo "Grafana Username: admin"
    echo "Grafana Password: ${GRAFANA_ADMIN_PASSWORD}"
}

# Display menu and handle user choice
show_menu() {
clear
    while true; do
        echo
        echo "╔════════════════════════════════════════════════════════════════════╗"
        echo "║                Monitoring Stack Installation Manager               ║"
        echo "╠════════════════════════════════════════════════════════════════════╣"
        echo "║   ACTIONS                                                          ║"
        echo "║────────────────────────────────────────────────────────────────────║"
        echo "║  1) 🧹  Clean                                                      ║"
        echo "║  2) 📝  Generate YAML files                                        ║"
        echo "║  3) 🚀  Install                                                    ║"
        echo "║  4) 🧹  Clean & 🚀 Install                                          ║"
        echo "║  5) 🧹  Clean, 📝 Generate & 🚀 Install                             ║"
        echo "║────────────────────────────────────────────────────────────────────║"
        echo "║  i) ℹ️   Show Info & Version                                       ║"
        echo "║  q) ❌  Quit                                                       ║"
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

# Main script execution
echo "Monitoring Stack Installation Script"
echo "==================================="
print_banner
# Start the menu
show_menu 
