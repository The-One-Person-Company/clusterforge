#!/bin/bash
set -euo pipefail

# Get the absolute path of the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load shared config and env
source "${WORKSPACE_DIR}/00-config.sh"

# Function to wait for Grafana to be ready
wait_for_grafana() {
    log STEP "Waiting for Grafana to be ready..."
    until microk8s kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].status.phase}' | grep -q "Running"; do
        log INFO "Waiting for Grafana pod to be ready..."
        sleep 5
    done
    log SUCCESS "Grafana is ready!"
}

# Function to get Grafana admin credentials
get_grafana_credentials() {
    log STEP "Getting Grafana admin credentials..."
    export GRAFANA_USER="admin"
    export GRAFANA_PASSWORD="${GRAFANA_ADMIN_PASSWORD}"
    export GRAFANA_URL="https://${GRAFANA_DOMAIN}"
    log SUCCESS "Credentials retrieved"
}

# Function to install a dashboard
install_dashboard() {
    local dashboard_file="$1"
    local dashboard_name=$(basename "$dashboard_file" .json)
    
    log INFO "Installing dashboard: ${dashboard_name}"
    
    # Get the dashboard JSON content
    local dashboard_json=$(cat "$dashboard_file")
    
    # Create the dashboard using Grafana API
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
        "${GRAFANA_URL}/api/dashboards/db" \
        -d "{
            \"dashboard\": ${dashboard_json},
            \"overwrite\": true,
            \"inputs\": [],
            \"folderId\": 0
        }"
    
    if [ $? -eq 0 ]; then
        log SUCCESS "Dashboard ${dashboard_name} installed successfully"
    else
        log ERROR "Failed to install dashboard ${dashboard_name}"
    fi
}

# Main installation process
main() {
    log STEP "Starting dashboard installation"
    
    # Wait for Grafana to be ready
    wait_for_grafana
    
    # Get Grafana credentials
    get_grafana_credentials
    
    # Install each dashboard
    for dashboard in "${SCRIPT_DIR}/monitoring/dashboards"/*.json; do
        if [ -f "$dashboard" ]; then
            install_dashboard "$dashboard"
        fi
    done
    
    log SUCCESS "All dashboards installed successfully!"
}

# Execute main function
main 
