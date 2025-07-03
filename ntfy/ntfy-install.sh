#!/bin/bash
#===============================================================================
#
# FILE: ntfy-install.sh
#
# NAME: NFTY
#
# USAGE: ./ntfy-install.sh
#
# DESCRIPTION: Installation script for NFTY notification service on Kubernetes.
#              Deploys and configures NFTY and its dependencies.
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


print_banner() {
    echo -e "\033[36m"
    cat << "EOF"
    ███╗   ██╗███████╗████████╗██╗   ██╗
    ████╗  ██║██╔════╝╚══██╔══╝╚██╗ ██╔╝
    ██╔██╗ ██║█████╗     ██║    ╚████╔╝ 
    ██║╚██╗██║██╔══╝     ██║     ╚██╔╝  
    ██║ ╚████║██║        ██║      ██║   
    ╚═╝  ╚═══╝╚═╝        ╚═╝      ╚═╝   
    NFTY Installer (v2.0)
EOF
    echo -e "\033[0m"
}

# Print banner at script start
clear
print_banner

# Get the absolute path of the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load shared config and env
source "${WORKSPACE_DIR}/00-config.sh"

export NTFY_DOMAIN="${NTFY_SUBDOMAIN}.${DOMAIN_BASE}"

# Function to generate Web Push configuration
# ------------------------------------------------------------------
# generate_ntfy_vapid – Pull ntfy VAPID keys and upsert them in .env
# • writes ONLY if both keys are found
# • never exits with a non-zero status (won't break a task chain)
# • relies on helper logger:  log INFO|WARNING|STEP|SUCCESS "<msg>"
# ------------------------------------------------------------------
generate_ntfy_vapid() {
  log STEP "🔑  Generating ntfy VAPID keys …"

  # Run container (discard stderr so awk sees clean stdout)
  local keys_output
  keys_output=$(docker run --rm binwiederhier/ntfy:latest webpush keys 2>/dev/null) || true

  # Parse keys
  local public_key private_key
  public_key=$(awk -F': ' '/web-push-public-key:/   {print $2}' <<<"$keys_output")
  private_key=$(awk -F': ' '/web-push-private-key:/ {print $2}' <<<"$keys_output")

  # Abort silently (but keep script flow) if anything is missing
  if [[ -z "$public_key" || -z "$private_key" ]]; then
    log WARN "⚠️  VAPID keys not found – skipping .env update"
    return 0            # keep the chain alive
  fi

  log INFO "✅  Keys extracted"
  log INFO "🔑 Public:  ${public_key:0:20}…"
  log INFO "🔐 Private: ${private_key:0:20}…"

  # Upsert into .env
  local env_file="${WORKSPACE_DIR:-.}/.env"
  touch "$env_file"     # ensure file exists

  # insert-or-replace helper
  _upsert() {
    local name="$1" value="$2"
    if grep -q "^${name}=" "$env_file"; then
      sed -i.bak "s|^${name}=.*|${name}=\"${value}\"|" "$env_file"
    else
      printf '%s="%s"\n' "$name" "$value" >>"$env_file"
    fi
  }

  _upsert "NTFY_WEB_PUSH_PUBLIC_KEY"  "$public_key"
  _upsert "NTFY_WEB_PUSH_PRIVATE_KEY" "$private_key"
  rm -f "${env_file}.bak" 2>/dev/null

  # Export for current shell (optional but handy)
  export NTFY_WEB_PUSH_PUBLIC_KEY="$public_key"
  export NTFY_WEB_PUSH_PRIVATE_KEY="$private_key"

  log SUCCESS "🎉  .env updated with ntfy VAPID keys"
  return 0
}

# Function to clean up ntfy resources
cleanup() {
    log STEP "Cleaning up ntfy resources..."
    
    log STEP "🗑️  Starting full cleanup of ntfy resources..."
    local yaml_files=(
        "ntfy/ntfy-pvc.yaml"
        "ntfy/ntfy-cache-pvc.yaml"
        "ntfy/ntfy-server-config.yaml"
        "ntfy/ntfy-admin-secret.yaml"
        "ntfy/ntfy-deployment.yaml"
        "ntfy/ntfy-service.yaml"
        "ntfy/ntfy-ingress.yaml"
        "ntfy/ntfy-certificate.yaml"
    )
    
    log STEP "📁 Removing generated YAML files..."
    
    for file in "${yaml_files[@]}"; do
        local file_path="${WORKSPACE_DIR}/${file}"
        if [ -f "$file_path" ]; then
            log INFO "Deleting file: $file"
            rm -f "$file_path"
        fi
    done
    log INFO "📊 Removed YAML files"
    # Delete namespace without waiting
    log STEP "🗂️  Removing Kubernetes namespace..."
    microk8s kubectl delete namespace ntfy --ignore-not-found=true
    
    log SUCCESS "🎉 Full cleanup completed successfully!"
    log INFO "🗑️  All ntfy resources removed"
    log INFO "📁 Generated files deleted"
    log INFO "🗂️  Kubernetes namespace cleaned"
}

# Function to perform soft cleanup (preserving TLS and namespace)
soft_cleanup() {
    log STEP "🔄 Soft Cleanup - ntfy Resources"
    
    log STEP "🔄 Starting soft cleanup of ntfy resources.. (preserving TLS)"
    local yaml_files=(
        "ntfy/ntfy-pvc.yaml"
        "ntfy/ntfy-cache-pvc.yaml"
        "ntfy/ntfy-server-config.yaml"
        "ntfy/ntfy-admin-secret.yaml"
        "ntfy/ntfy-deployment.yaml"
        "ntfy/ntfy-service.yaml"
        "ntfy/ntfy-ingress.yaml"
    )
    
    log STEP "📁 Removing application YAML files (preserving TLS)..."
    for file in "${yaml_files[@]}"; do
        local file_path="${WORKSPACE_DIR}/${file}"
        if [ -f "$file_path" ]; then
            log INFO "Deleting file: $file"
            rm -f "$file_path"
        fi
    done
    log INFO "📊 Removed application files"
    # Delete specific resources but keep namespace and TLS resources
    log STEP "🗂️  Removing Kubernetes resources (preserving TLS and namespace)..."
    microk8s kubectl delete deployment,service,configmap,pvc,secret -l app=ntfy -n ntfy --ignore-not-found=true

    log INFO "✅ Removed ntfy application resources"
    log INFO "🔒 TLS certificates and namespace preserved"
    
    log SUCCESS "🎉 Soft cleanup completed successfully!"
}

# Function to initialize YAML files from templates
init_yaml_files() {
    echo "📝 Creating YAML Files from Templates"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    
    log STEP "🚀 Starting YAML file generation..."
    
    # Export password for envsubst to use in the secret template
    export NTFY_INITIAL_PASSWORD="${NTFY_INITIAL_PASSWORD:-admin123}"
    export NTFY_INITIAL_USER="${NTFY_INITIAL_USER:-admin}"
    
    # List of template files to process
    local templates=(
        "ntfy/ntfy-pvc.yaml.template"
        "ntfy/ntfy-cache-pvc.yaml.template"
        "ntfy/ntfy-server-config.yaml.template"
        "ntfy/ntfy-admin-secret.yaml.template"
        "ntfy/ntfy-deployment.yaml.template"
        "ntfy/ntfy-service.yaml.template"
        "ntfy/ntfy-ingress.yaml.template"
        "ntfy/ntfy-certificate.yaml.template"
    )
    
    # Process each template
    for template in "${templates[@]}"; do
        local template_path="${WORKSPACE_DIR}/${template}"
        local output_path="${WORKSPACE_DIR}/${template%.template}"
        
        if [ ! -f "$template_path" ]; then
            log ERROR "Template file not found: $template_path"
            continue
        fi
        
        log STEP "Processing template: $template"
        envsubst < "$template_path" > "$output_path"
        log SUCCESS "Created: ${template%.template}"
    done
    
    # Clean up Web Push configuration if environment variables are not set
    log STEP "🔧 Post-processing configuration..."
    cleanup_web_push_config
    
    log SUCCESS "All YAML files initialized"
}

# Function to apply configuration files
apply_config() {
    local file=$1
    log STEP "Applying configuration: $file"
    microk8s kubectl apply -f $file
}

# Function to install ntfy
install() {
    echo "🚀 Installing ntfy to Kubernetes"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    
    log STEP "🚀 Starting ntfy installation..."
    
    # Create namespace
    log STEP "🗂️  Creating Kubernetes namespace..."
    microk8s kubectl create namespace ntfy --dry-run=client -o yaml | microk8s kubectl apply -f -
    log SUCCESS "✅ Namespace 'ntfy' ready"
    
    # Apply configurations in order
    log STEP "📦 Applying Kubernetes resources..."
    
    # PVCs first
    log STEP "💾 Setting up persistent volumes..."
    apply_config "ntfy/ntfy-pvc.yaml"
    apply_config "ntfy/ntfy-cache-pvc.yaml"
    log SUCCESS "✅ Storage volumes configured"
    
    # Configuration (ConfigMaps and Secret)
    log STEP "⚙️  Applying server configuration and secrets..."
    apply_config "ntfy/ntfy-server-config.yaml"
    apply_config "ntfy/ntfy-admin-secret.yaml"
    log SUCCESS "✅ Configuration applied"

    # Certificate (must be created before ingress)
    log STEP "🔒 Setting up TLS certificate..."
    apply_config "ntfy/ntfy-certificate.yaml"
    log SUCCESS "✅ Certificate request created"

    # Deployment and service
    log STEP "🐳 Deploying ntfy application..."
    apply_config "ntfy/ntfy-deployment.yaml"
    apply_config "ntfy/ntfy-service.yaml"
    log SUCCESS "✅ Application deployed"
    
    # Ingress (after certificate is ready)
    log STEP "🌐 Configuring ingress..."
    apply_config "ntfy/ntfy-ingress.yaml"
    log SUCCESS "✅ Ingress configured"
    
    # Verify ingress
    log STEP "🔍 Verifying installation..."
    if ! microk8s kubectl get ingress ntfy-ingress -n ntfy >/dev/null 2>&1; then
        log ERROR "❌ Ingress verification failed"
        log INFO "🔍 Checking ingress status..."
        microk8s kubectl get ingress -n ntfy
        exit 1
    fi
    log SUCCESS "✅ Ingress verified successfully"
    
    log SUCCESS "🎉 ntfy installation completed successfully!"
    
    log STEP "📊 Access Information:"
    log INFO "   🌐 Web Interface: https://${NTFY_DOMAIN}"
    log INFO "   📊 Metrics: http://ntfy-service.ntfy.svc.cluster.local:9000/metrics"
    log INFO "   🔗 Internal URL: http://ntfy-service.ntfy.svc.cluster.local"
    
    log STEP "⏰ Important Notes:"
    log INFO "   • TLS certificate may take 5-10 minutes to be provisioned"
    log INFO "   • Check certificate status: microk8s kubectl get certificate -n ntfy"
    log INFO "  • View logs: microk8s kubectl logs -n ntfy deployment/ntfy"
    
    # Print pod status
    log STEP "📊 Current Pod Status:"
    echo "======================"
    microk8s kubectl get pods -n ntfy
}

# Function to install ntfy (simple version - no certificate generation)
install_simple() {
    echo "⚡ Simple Install - ntfy (Existing YAML Files)"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    
    log STEP "⚡ Starting simple ntfy installation..."
    
    # Create namespace
    log STEP "🗂️  Creating Kubernetes namespace..."
    microk8s kubectl create namespace ntfy --dry-run=client -o yaml | microk8s kubectl apply -f -
    log SUCCESS "✅ Namespace 'ntfy' ready"
    
    # Apply configurations in order (skip certificate)
    log STEP "📦 Applying Kubernetes resources..."
    
    # PVCs first
    log STEP "💾 Setting up persistent volumes..."
    apply_config "ntfy/ntfy-pvc.yaml"
    apply_config "ntfy/ntfy-cache-pvc.yaml"
    log SUCCESS "✅ Storage volumes configured"
    
    # Configuration
    log STEP "⚙️  Applying server configuration and secrets..."
    apply_config "ntfy/ntfy-server-config.yaml"
    apply_config "ntfy/ntfy-admin-secret.yaml"
    log SUCCESS "✅ Configuration applied"

    # Deployment and service
    log STEP "🐳 Deploying ntfy application..."
    apply_config "ntfy/ntfy-deployment.yaml"
    apply_config "ntfy/ntfy-service.yaml"
    log SUCCESS "✅ Application deployed"
    
    # Apply ingress (if it exists)
    if [ -f "ntfy/ntfy-ingress.yaml" ]; then
        log STEP "🌐 Configuring ingress..."
        apply_config "ntfy/ntfy-ingress.yaml"
        log SUCCESS "✅ Ingress configured"
    else
        log INFO "ℹ️  No ingress file found, skipping external access"
    fi
    
    # Apply certificate (if it exists)
    if [ -f "ntfy/ntfy-certificate.yaml" ]; then
        log STEP "🔒 Setting up TLS certificate..."
        apply_config "ntfy/ntfy-certificate.yaml"
        log SUCCESS "✅ Certificate request created"
    else
        log INFO "ℹ️  No certificate file found, skipping TLS"
    fi
    
    log SUCCESS "🎉 Simple ntfy installation completed successfully!"
    
    log STEP "📊 Access Information:"
    log INFO "🔗 Internal URL: http://ntfy-service.ntfy.svc.cluster.local"
    if [ -f "ntfy/ntfy-ingress.yaml" ]; then
        log INFO "🌐 External URL: https://${NTFY_DOMAIN} (if ingress configured)"
    fi
    log INFO "📊 Metrics: http://ntfy-service.ntfy.svc.cluster.local:9000/metrics"
    
    log STEP "💡 Notes:"
    log INFO "   • No certificate waiting - fast deployment"
    log INFO "   • Check pod status for deployment progress"
    log INFO "   • View logs: microk8s kubectl logs -n ntfy deployment/ntfy"
    
    # Print pod status
    log STEP "📊 Current Pod Status:"
    echo "======================"
    microk8s kubectl get pods -n ntfy
}

# Function to clean up Web Push configuration from generated YAML
cleanup_web_push_config() {
    local config_file="${WORKSPACE_DIR}/ntfy/ntfy-server-config.yaml"
    
    if [ -f "$config_file" ]; then
        log STEP "🔧 Cleaning up Web Push configuration..."
        
        # Count lines before cleanup
        local lines_before=$(wc -l < "$config_file")
        
        # Remove lines that contain empty Web Push configurations
        sed -i.bak '/web-push-public-key: ""/d' "$config_file"
        sed -i.bak '/web-push-private-key: ""/d' "$config_file"
        sed -i.bak '/web-push-file: ""/d' "$config_file"
        sed -i.bak '/web-push-email-address: ""/d' "$config_file"
        sed -i.bak '/web-push-expiry-warning-duration: ""/d' "$config_file"
        sed -i.bak '/web-push-expiry-duration: ""/d' "$config_file"
        
        # Count lines after cleanup
        local lines_after=$(wc -l < "$config_file")
        local removed_lines=$((lines_before - lines_after))
        
        # Remove the backup file
        rm -f "${config_file}.bak"
        
        if [ $removed_lines -gt 0 ]; then
            log SUCCESS "✅ Removed $removed_lines empty Web Push configuration lines"
        else
            log INFO "ℹ️  No empty Web Push configurations found"
        fi
    else
        log INFO "ℹ️  No server config file found to clean"
    fi
}

# Function to create ntfy user with environment variables
create_ntfy_user_env() {
    echo "👤 Manually Create Admin User"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    
    log INFO "ℹ️  User creation is now a manual process."
    log STEP "   To create a user, the ntfy pod must be running."

    # Wait for ntfy pod to be ready
    log STEP "1. ⏳ Waiting for ntfy pod to be ready..."
    if ! microk8s kubectl wait --for=condition=ready pod -l app=ntfy -n ntfy --timeout=60s; then
        log ERROR "❌ ntfy pod not ready after 1 minute. Cannot create user."
        log INFO "🔍 Check pod status with: microk8s kubectl get pods -n ntfy"
        return 1
    fi
    log SUCCESS "✅ ntfy pod is ready."

    local user="${NTFY_INITIAL_USER:-admin}"
    local pass="${NTFY_INITIAL_PASSWORD:-admin123}"
    
    log STEP "2. 🔧 Running user creation command..."
    log INFO "   👤 User: $user"

    local cmd="NTFY_PASSWORD=\"$pass\" microk8s kubectl exec -i -n ntfy deployment/ntfy -- ntfy user add --role=admin --ignore-exists \"$user\""
    log INFO "   Command: $cmd"
    
    if eval "$cmd"; then
        log SUCCESS "✅ Admin user '$user' created or already exists."
    else
        log ERROR "❌ Failed to create admin user."
        log INFO "   This can happen for various reasons. Please check the ntfy pod logs."
        return 1
    fi
    
    log SUCCESS "🎉 Manual user creation process finished."
}

# Function to list all NTFY-related environment variables
list_ntfy_env_vars() {
    echo "🔧 NTFY Environment Variables"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    
    # Get all environment variables that start with NTFY_
    local ntfy_vars=$(env | grep -E '^NTFY_' | sort)
    
    if [ -z "$ntfy_vars" ]; then
        echo "❌ No NTFY environment variables found"
        echo
        echo "💡 To set NTFY environment variables:"
        echo "   export NTFY_INITIAL_USER=\"your_username\""
        echo "   export NTFY_INITIAL_PASSWORD=\"your_password\""
        echo "   export NTFY_WEB_PUSH_PUBLIC_KEY=\"your_public_key\""
        echo "   export NTFY_WEB_PUSH_PRIVATE_KEY=\"your_private_key\""
        echo
        echo "📝 Or add them to your .env file:"
        echo "   NTFY_INITIAL_USER=your_username"
        echo "   NTFY_INITIAL_PASSWORD=your_password"
        echo "   NTFY_WEB_PUSH_PUBLIC_KEY=your_public_key"
        echo "   NTFY_WEB_PUSH_PRIVATE_KEY=your_private_key"
    else
        echo "📋 Found NTFY environment variables:"
        echo
        
        # Parse and display each variable beautifully
        echo "$ntfy_vars" | while IFS='=' read -r var_name var_value; do
            # Determine the category and icon based on variable name
            local icon="🔧"
            local category="General"
            local description=""
            
            case $var_name in
                NTFY_INITIAL_USER)
                    icon="👤"
                    category="User Management"
                    description="Admin username for ntfy"
                    ;;
                NTFY_INITIAL_PASSWORD)
                    icon="🔐"
                    category="User Management"
                    description="Admin password for ntfy"
                    ;;
                NTFY_WEB_PUSH_PUBLIC_KEY)
                    icon="🔑"
                    category="Web Push"
                    description="VAPID public key for push notifications"
                    ;;
                NTFY_WEB_PUSH_PRIVATE_KEY)
                    icon="🔑"
                    category="Web Push"
                    description="VAPID private key for push notifications"
                    ;;
                NTFY_WEB_PUSH_FILE)
                    icon="📁"
                    category="Web Push"
                    description="Web push database file path"
                    ;;
                NTFY_WEB_PUSH_EMAIL_ADDRESS)
                    icon="📧"
                    category="Web Push"
                    description="Email address for push notifications"
                    ;;
                NTFY_WEB_PUSH_EXPIRY_WARNING_DURATION)
                    icon="⏰"
                    category="Web Push"
                    description="Warning duration before push expiry"
                    ;;
                NTFY_WEB_PUSH_EXPIRY_DURATION)
                    icon="⏰"
                    category="Web Push"
                    description="Push notification expiry duration"
                    ;;
                NTFY_DOMAIN)
                    icon="🌐"
                    category="Network"
                    description="Full ntfy domain (auto-generated)"
                    ;;
                *)
                    icon="🔧"
                    category="Other"
                    description="Custom NTFY variable"
                    ;;
            esac
            
            # Display the variable with formatting
            printf "  %s %-35s │ %s\n" "$icon" "$var_name" "$category"
            printf "     %-35s │ %s\n" "" "$description"
            
            # Show the value (masked for sensitive data)
            local display_value="$var_value"
            if [[ "$var_name" == *"PASSWORD"* ]] || [[ "$var_name" == *"PRIVATE_KEY"* ]]; then
                if [ ${#var_value} -gt 8 ]; then
                    display_value="${var_value:0:8}...${var_value: -4}"
                else
                    display_value="***"
                fi
            fi
            printf "     %-35s │ %s\n" "" "Value: $display_value"
            echo
        done
        
        echo "📊 Summary:"
        echo "   • Total NTFY variables: $(echo "$ntfy_vars" | wc -l)"
        echo "   • User Management: $(echo "$ntfy_vars" | grep -E "(USER|PASSWORD)" | wc -l)"
        echo "   • Web Push: $(echo "$ntfy_vars" | grep "WEB_PUSH" | wc -l)"
        echo "   • Network: $(echo "$ntfy_vars" | grep "DOMAIN" | wc -l)"
        echo "   • Other: $(echo "$ntfy_vars" | grep -vE "(USER|PASSWORD|WEB_PUSH|DOMAIN)" | wc -l)"
    fi
    
    echo
    echo "💡 Tips:"
    echo "   • Sensitive values (passwords, private keys) are masked"
    echo "   • Use 'env | grep NTFY_' to see raw values"
    echo "   • Set variables before running installation for automatic configuration"
    echo
    echo "🔗 Related Files:"
    echo "   • .env file: ${WORKSPACE_DIR}/.env"
    echo "   • Config: ${WORKSPACE_DIR}/00-config.sh"
    echo
}

# Display menu and handle user choice
show_menu() {
    while true; do
        clear
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║                    ntfy Installation Manager                 ║"
        echo "║                                                              ║"
        echo "║  🚀  Modern Notification Service for Kubernetes              ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo "📋  Current Status:"
        echo "    Domain: ${NTFY_DOMAIN}"
        echo "    Namespace: ntfy"
        echo
        echo "🔧  Installation Options:"
        echo "    ┌─ Quick Start ──────────────────────────────────────────┐"
        echo "    │  1) 🚀 Full Install (recommended)                    │"
        echo "    │     • Clean install with Web Push support             │"
        echo "    │     • Creates admin user automatically                │"
        echo "    │                                                       │"
        echo "    │  2) ⚡ Simple Install (existing YAML files)           │"
        echo "    │     • No certificate waiting                          │"
        echo "    │     • Fast deployment                                 │"
        echo "    └───────────────────────────────────────────────────────┘"
        echo
        echo "🛠️   Advanced Operations:"
        echo "    ┌─ Management ──────────────────────────────────────────┐"
        echo "    │  3) 🧹 Full Cleanup                                  │"
        echo "    │     • Removes all resources and files                │"
        echo "    │                                                      │"
        echo "    │  4) 🔄 Soft Cleanup                                  │"
        echo "    │     • Preserves TLS certificates and namespace       │"
        echo "    │                                                       │"
        echo "    │  5) 📝 Create YAML Files Only                        │"
        echo "    │     • Generate configuration without installing      │"
        echo "    │                                                       │"
        echo "    │  6) 👤 Create Admin User (Manual)                    │"
        echo "    │     • Manually trigger admin user creation           │"
        echo "    └───────────────────────────────────────────────────────┘"
        echo
        echo "🔐  Web Push Configuration:"
        echo "    ┌─ Push Notifications ─────────────────────────── ─────┐"
        echo "    │  7) 🔑 Generate Web Push Keys                        │"
        echo "    │     • Creates VAPID keys for push notifications      │"
        echo "    │     • Updates .env file automatically                │"
        echo "    │     • WARNING: Only needed for push notifications    │"
        echo "    └───────────────────────────────────────────────────────┘"
        echo
        echo "📊  Information:"
        echo "    ┌─ Status & Help ──────────────────────────────────────┐"
        echo "    │  8) 📊 Show Status                                   │"
        echo "    │     • Current pod status and logs                    │"
        echo "    │                                                       │"
        echo "    │  9) 🔧 Environment Variables                         │"
        echo "    │     • List all NTFY configuration variables          │"
        echo "    │                                                       │"
        echo "    │  10) ❓ Help & Documentation                          │"
        echo "    │     • Usage instructions and examples                │"
        echo "    │                                                       │"
        echo "    │  0) 🚪 Exit                                          │"
        echo "    └───────────────────────────────────────────────────────┘"
        echo
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║  💡 Tip: Use option 1 for a complete setup with Web Push   ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo
        read -p "🎯 Select an option (0-10): " choice
        echo

        case $choice in
            1)
                echo "🚀 Starting Quick Install..."
                echo "   This will:"
                echo "   • Clean existing resources"
                echo "   • Generate Web Push keys (if needed)"
                echo "   • Create YAML files"
                echo "   • Install ntfy"
                echo
                read -p "   Continue? (y/N): " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    cleanup
                    generate_ntfy_vapid
                    init_yaml_files
                    install
                    echo
                    echo "✅ Quick Install completed successfully!"
                    read -p "Press Enter to continue..."
                fi
                ;;
            2)
                echo "⚡ Starting Simple Install..."
                echo "   This will:"
                echo "   • Use existing YAML files"
                echo "   • Install without waiting for certificates"
                echo
                read -p "   Continue? (y/N): " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    install_simple
                    echo
                    echo "✅ Simple Install completed successfully!"
                    read -p "Press Enter to continue..."
                fi
                ;;
            3)
                echo "🧹 Starting Full Cleanup..."
                echo "   This will remove:"
                echo "   • All Kubernetes resources"
                echo "   • Generated YAML files"
                echo "   • TLS certificates"
                echo
                read -p "   Are you sure? This cannot be undone! (y/N): " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    cleanup
                    echo "✅ Full cleanup completed!"
                    read -p "Press Enter to continue..."
                fi
                ;;
            4)
                echo "🔄 Starting Soft Cleanup..."
                echo "   This will remove:"
                echo "   • Application resources"
                echo "   • Generated YAML files"
                echo "   • Preserve TLS certificates"
                echo
                read -p "   Continue? (y/N): " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    soft_cleanup
                    echo "✅ Soft cleanup completed!"
                    read -p "Press Enter to continue..."
                fi
                ;;
            5)
                echo "📝 Creating YAML Files..."
                init_yaml_files
                echo "✅ YAML files created successfully!"
                read -p "Press Enter to continue..."
                ;;
            6)
                echo "👤 Manually Creating Admin User..."
                create_ntfy_user_env
                read -p "Press Enter to continue..."
                ;;
            7)
                echo "🔑 Generating Web Push Keys..."
                echo "   This will:"
                echo "   • Generate VAPID keys using Docker"
                echo "   • Update .env file with new keys"
                echo "   • Enable push notifications"
                echo
                read -p "   Continue? (y/N): " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    generate_ntfy_vapid
                    echo "✅ Web Push keys generated and saved to .env file!"
                    read -p "Press Enter to continue..."
                fi
                ;;
            8)
                echo "📊 Current Status:"
                echo "=================="
                microk8s kubectl get pods -n ntfy 2>/dev/null || echo "No ntfy namespace found"
                echo
                echo "Recent logs (last 10 lines):"
                echo "============================"
                microk8s kubectl logs -n ntfy deployment/ntfy --tail=10 2>/dev/null || echo "No logs available"
                echo
                read -p "Press Enter to continue..."
                ;;
            9)
                echo "🔧 Environment Variables"
                echo "======================="
                list_ntfy_env_vars
                echo
                read -p "Press Enter to continue..."
                ;;
            10)
                echo "❓ Help & Documentation"
                echo "======================="
                echo
                echo "📖 Quick Start Guide:"
                echo "   1. Run option 1 for complete setup"
                echo "   2. Access ntfy at https://${NTFY_DOMAIN}"
                echo "   3. Login with admin credentials"
                echo
                echo "🔧 Environment Variables:"
                echo "   • NTFY_INITIAL_USER: Admin username (default: admin)"
                echo "   • NTFY_INITIAL_PASSWORD: Admin password (default: admin123)"
                echo "   • NTFY_WEB_PUSH_*: Web Push configuration (auto-generated)"
                echo
                echo "📱 Usage Examples:"
                echo "   • Send notification: ntfy publish mytopic 'Hello World!'"
                echo "   • Subscribe: ntfy subscribe mytopic"
                echo "   • Web interface: https://${NTFY_DOMAIN}"
                echo
                echo "🔗 Useful Commands:"
                echo "   • Check status: microk8s kubectl get pods -n ntfy"
                echo "   • View logs: microk8s kubectl logs -n ntfy deployment/ntfy"
                echo "   • Access shell: microk8s kubectl exec -it -n ntfy deployment/ntfy -- /bin/sh"
                echo
                read -p "Press Enter to continue..."
                ;;
            0)
                echo "🚪 Exiting ntfy Installation Manager..."
                echo "   Thank you for using ntfy! 🎉"
                exit 0
                ;;
            *)
                echo "❌ Invalid option. Please select 0-10."
                sleep 2
                ;;
        esac
    done
}

# Main script execution
echo "ntfy Installation Script"
echo "======================="

# Start the menu
show_menu 