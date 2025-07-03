#!/bin/bash
#===============================================================================
#
# FILE: get_config.sh
#
# USAGE: ./get_config.sh
#
# DESCRIPTION: Generates a kubeconfig file for remote access to the
#              MicroK8s cluster, replacing the local IP with the
#              publicly accessible domain.
#
# REQUIREMENTS: 00-config.sh, microk8s, and a configured .env file with
#               K8S_API_DOMAIN and K8S_API_PORT.
#
# AUTHOR: Vivien Roggero LLC
# MODIFIED BY: Gemini
# CREATION DATE: 2024-08-01
# LAST MODIFIED: 2024-08-01
# VERSION: 1.1
#
#===============================================================================

# ██████╗     ██╗      █████╗ ██████╗ 
# ██╔══██╗    ██║     ██╔══██╗██╔══██╗
# ██████╔╝    ██║     ███████║██████╔╝
# ██╔══██╗    ██║     ██╔══██║██╔══██╗
# ██║  ██║    ███████╗██║  ██║██████╔╝
# ╚═╝  ╚═╝    ╚══════╝╚═╝  ╚═╝╚═════╝ 

set -euo pipefail

# Source shared configuration and utilities
source "$(dirname "${BASH_SOURCE[0]}")/00-config.sh"

# --- Configuration ---
readonly KUBECONFIG_OUTPUT_FILE="kubeconfig"

# --- Main Logic ---
main() {
    log "STEP" "Generating kubeconfig for remote access"

    # Validate that the required environment variables are set
    if [ -z "${K8S_API_DOMAIN:-}" ] || [ -z "${K8S_API_PORT:-}" ]; then
        log "ERROR" "K8S_API_DOMAIN and K8S_API_PORT must be set in your .env file."
        log "INFO" "Example: K8S_API_DOMAIN=k8s.yourdomain.com"
        log "INFO" "Example: K8S_API_PORT=16443"
        exit 1
    fi

    local server_address="https://${K8S_API_DOMAIN}:${K8S_API_PORT}"
    log "INFO" "Generating config for server endpoint: ${server_address}"

    # Generate the kubeconfig file, replacing the server address
    local cmd="microk8s config | sed -E 's|^(\\s*server: )https://[^:]+(:[0-9]+)?|\\1${server_address}|' > '${KUBECONFIG_OUTPUT_FILE}'"
    execute_command "Generating kubeconfig" bash -c "${cmd}"

    log "SUCCESS" "kubeconfig file generated successfully."

    # --- Display Output ---
    echo
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}[INFO] kubeconfig generated to file: ${BOLD}${KUBECONFIG_OUTPUT_FILE}${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
    cat "${KUBECONFIG_OUTPUT_FILE}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
    echo
    log "WARN" "For remote access, save this output as ~/.kube/config on your local machine."
    log "WARN" "Ensure port ${K8S_API_PORT} is allowed through your firewall."
}

# --- Run Script ---
main
