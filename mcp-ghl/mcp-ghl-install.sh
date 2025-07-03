#!/bin/bash
#===============================================================================
#
# FILE: mcp-ghl-install.sh
#
# NAME: MCP-GHL Installer
#
# USAGE: ./mcp-ghl-install.sh
#
# DESCRIPTION: Installation script for GoHighLevel MCP on Kubernetes.
#              Builds Docker image, generates YAML, and deploys via Helm.
#
# AUTHOR: Vivien Roggero LLC
# MODIFIED BY: Gemini
# CREATION DATE: 2024-08-01
# LAST MODIFIED: 2024-08-01
# VERSION: 2.0
#
#===============================================================================
set -euo pipefail

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
REPO_DIR="${SCRIPT_DIR}/mcp-ghl/GoHighLevel-MCP"

# Load shared configuration
source "${WORKSPACE_DIR}/00-config.sh"

# Prompt for client name
read -p "Enter client name for MCP GHL (e.g., 'client1'): " MCP_CLIENT_NAME
if [ -z "$MCP_CLIENT_NAME" ]; then
    echo "Error: Client name is required"
    exit 1
fi

# Set service name based on client
export MCP_SERVICE_NAME="ghl-${MCP_CLIENT_NAME}"

# Prompt for GHL API key if not set
if [ -z "${GHL_API_KEY:-}" ]; then
    read -s -p "Enter GHL API Key: " GHL_API_KEY
    echo
    if [ -z "$GHL_API_KEY" ]; then
        echo "Error: GHL API Key is required"
        exit 1
    fi
    export GHL_API_KEY
fi

# Prompt for GHL Location ID if not set
if [ -z "${GHL_LOCATION_ID:-}" ]; then
    read -p "Enter GHL Location ID: " GHL_LOCATION_ID
    if [ -z "$GHL_LOCATION_ID" ]; then
        echo "Error: GHL Location ID is required"
        exit 1
    fi
    export GHL_LOCATION_ID
fi

# --- Banner ---
print_banner() {
    echo -e "\033[36m"
    cat << "EOF"
    ███╗   ███╗ ██████╗██████╗        ██████╗ ██╗  ██╗██╗     
    ████╗ ████║██╔════╝██╔══██╗      ██╔════╝ ██║  ██║██║     
    ██╔████╔██║██║     ██████╔╝█████╗██║  ███╗███████║██║     
    ██║╚██╔╝██║██║     ██╔═══╝ ╚════╝██║   ██║██╔══██║██║     
    ██║ ╚═╝ ██║╚██████╗██║           ╚██████╔╝██║  ██║███████╗
    ╚═╝     ╚═╝ ╚═════╝╚═╝            ╚═════╝ ╚═╝  ╚═╝╚══════╝
    MCP-GHL Installer (v2.0)
EOF
    echo -e "\033[0m"
}

# Function to build Docker image
build_docker_image() {
    echo "Building Docker image..."
    
    # Clone or update the repository
    if [ ! -d "${REPO_DIR}" ]; then
        echo "Cloning GoHighLevel-MCP repository..."
        git clone https://github.com/mastanley13/GoHighLevel-MCP.git "${REPO_DIR}"
    else
        echo "Updating GoHighLevel-MCP repository..."
        cd "${REPO_DIR}" && git pull
    fi
    
    # Replace the Dockerfile
    echo "Replacing Dockerfile..."
    cat > "${REPO_DIR}/Dockerfile" << 'EOF'
# Use Node.js 18 LTS
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install full dependencies (incl. dev for tsc)
RUN npm ci

# Copy the rest of the app
COPY . .

# Build the app (needs tsc from devDependencies)
RUN npm run build

# Now prune devDependencies
RUN npm prune --production

# Expose the port
EXPOSE 8000

# Set environment
ENV NODE_ENV=production

# Start the app
CMD ["npm", "start"]
EOF
    
    # Build the Docker image from the cloned repository
    echo "Building Docker image from repository..."
    sudo docker build -t "local/mcp-ghl:${MCP_GHL_IMAGE_TAG}" "${REPO_DIR}"
    echo "Docker image built successfully"
}

# Function to create namespace
create_namespace() {
    echo "Creating namespace mcp..."
    if ! microk8s kubectl get namespace "mcp" &>/dev/null; then
        microk8s kubectl create namespace "mcp"
    fi
}

# Function to clean up resources
cleanup() {
    echo "Cleaning up resources..."
    microk8s kubectl delete deployment,service,configmap,secret,pvc,hpa -l app=${MCP_SERVICE_NAME} -n mcp --ignore-not-found=true
}

# Function to initialize YAML files from templates
init_yaml_files() {
    echo "Initializing YAML files from templates..."
    # Process each template file
    for template in "${SCRIPT_DIR}"/mcp-ghl/*.template; do
        if [ -f "$template" ]; then
            base_name="$(basename "$template" .template)"
            # If it's custom-values.yaml.template, output as custom-values.yaml
            if [[ "$base_name" == "custom-values.yaml" ]]; then
                output_file="${SCRIPT_DIR}/mcp-ghl/custom-values.yaml"
            else
                output_file="${SCRIPT_DIR}/mcp-ghl/${base_name}"
            fi
            echo "Processing template: $(basename "$template") -> $(basename "$output_file")"
            envsubst < "$template" > "$output_file"
        fi
    done
}

# Function to install mcp-ghl
install() {
    echo "Installing mcp-ghl for client: $MCP_CLIENT_NAME (service: $MCP_SERVICE_NAME) ..."
    build_docker_image
    create_namespace
    init_yaml_files
    
    # Render custom-values.yaml from template
    envsubst < "${SCRIPT_DIR}/mcp-ghl/custom-values.yaml.template" > "${SCRIPT_DIR}/mcp-ghl/custom-values.yaml"
    TEMP_CHART_DIR="${SCRIPT_DIR}/mcp-ghl/chart"
    mkdir -p "${TEMP_CHART_DIR}"
    
    # Copy Chart.yaml to the temporary chart directory
    cp "${SCRIPT_DIR}/mcp-ghl/Chart.yaml" "${TEMP_CHART_DIR}/"
    
    # Create templates directory
    mkdir -p "${TEMP_CHART_DIR}/templates"
    # Copy all non-template YAML files to templates directory
    for yaml in "${SCRIPT_DIR}"/mcp-ghl/*.yaml; do
        if [ -f "$yaml" ] && [[ "$yaml" != *.template ]]; then
            cp "$yaml" "${TEMP_CHART_DIR}/templates/"
        fi
    done
    # Install using Helm
    microk8s helm upgrade --install mcp-ghl "${TEMP_CHART_DIR}" \
        --namespace "${MCP_GHL_NAMESPACE}" \
        -f "${SCRIPT_DIR}/mcp-ghl/custom-values.yaml" \
        --set-string image.repository="local/mcp-ghl" \
        --set-string image.tag="${MCP_GHL_IMAGE_TAG}" \
        --set-string image.pullPolicy="Never" \
        --set-string env.GHL_API_KEY="${GHL_API_KEY}" \
        --set-string env.GHL_CLIENT_NAME="${MCP_CLIENT_NAME}" \
        --set-string env.GHL_LOCATION_ID="${GHL_LOCATION_ID}" \
        --set-string env.GHL_BASE_URL="${GHL_BASE_URL}" \
        --set-string env.NODE_ENV="production" \
        --set-string env.PORT="8000" \
        --set-string env.LOG_LEVEL="info" \
        --set-string env.CORS_ORIGINS="*" \
        --set-string autoscaling.enabled=true \
        --set-string autoscaling.minReplicas=1 \
        --set-string autoscaling.maxReplicas=3 \
        --set-string autoscaling.targetCPUUtilizationPercentage=80 \
        --set-string resources.limits.cpu="${MCP_GHL_CPU_LIMIT}" \
        --set-string resources.limits.memory="${MCP_GHL_MEMORY_LIMIT}" \
        --set-string resources.requests.cpu="${MCP_GHL_CPU_REQUEST}" \
        --set-string resources.requests.memory="${MCP_GHL_MEMORY_REQUEST}"
    rm -rf "${SCRIPT_DIR}/mcp-ghl/${TEMP_CHART_DIR}"
    echo "MCP GHL installation complete!"
    echo "Service Name: ${MCP_SERVICE_NAME}"
    echo "Namespace: mcp"
    echo "Internal URL: http://${MCP_SERVICE_NAME}.mcp.svc.cluster.local:80"
    echo "Note: This service is only accessible within the Kubernetes cluster."
    echo
    echo "Pod Status:"
    microk8s kubectl get pods -n mcp -l app=${MCP_SERVICE_NAME}
}

# Function to show menu
show_menu() {
    clear
    print_banner
    while true; do
        echo
        echo "╔════════════════════════════════════════════════════════════════════╗"
        echo "║                    MCP-GHL Installation Manager                  ║"
        echo "╠════════════════════════════════════════════════════════════════════╣"
        echo "║   ACTIONS                                                        ║"
        echo "║──────────────────────────────────────────────────────────────────║"
        echo "║  1) 🧹  Clean (Delete namespace)                                 ║"
        echo "║  2) 📝  Generate YAML files                                      ║"
        echo "║  3) 🚀  Install                                                  ║"
        echo "║  4) ❌  Quit                                                     ║"
        echo "║  5) 🧹📝🚀 Clean, Generate & Install All                          ║"
        echo "╚════════════════════════════════════════════════════════════════════╝"
        echo
        read -p "Select an option: " choice
        echo
        case $choice in
            1) cleanup ;;
            2) init_yaml_files ;;
            3) install ;;
            4) exit 0 ;;
            5) cleanup; init_yaml_files; install ;;
            *) echo "Invalid option. Please try again." ;;
        esac
    done
}

# --- Main Execution ---
clear
print_banner
if [ $# -eq 0 ]; then
    show_menu
else
    case "$1" in
        "clean") cleanup ;;
        "init") init_yaml_files ;;
        "install") install ;;
        "all") cleanup; init_yaml_files; install ;;
        *) echo "Usage: $0 [clean|init|install|all]" ;;
    esac
fi 