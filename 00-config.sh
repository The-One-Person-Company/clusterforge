#!/bin/bash
#===============================================================================
#
#  FILE: 00-config.sh
#
#  DESCRIPTION: Shared configuration, environment loading, logging, and utility
#               functions for all automation scripts in this project.
#
#  This script loads environment variables from .env, provides colorized logging,
#  and defines helper functions for robust, consistent scripting.
#
#  AUTHOR: Vivien Roggero LLC
#  MODIFIED BY: Gemini
#  CREATION DATE: 2024-08-01
#  LAST MODIFIED: 2024-08-01
#  VERSION: 1.1
#
#===============================================================================

# ██████╗     ██╗      █████╗ ██████╗ 
# ██╔══██╗    ██║     ██╔══██╗██╔══██╗
# ██████╔╝    ██║     ███████║██████╔╝
# ██╔══██╗    ██║     ██╔══██║██╔══██╗
# ██║  ██║    ███████╗██║  ██║██████╔╝
# ╚═╝  ╚═╝    ╚══════╝╚═╝  ╚═╝╚═════╝ 

#
# 00-config.sh
#
# Shared constants, logging functions, and utility helpers for every stage.
#
#─────────────────────────────────────────────────────────────────────────────────────
# 1) Load environment variables from .env file
#─────────────────────────────────────────────────────────────────────────────────────
# SPDX-FileCopyrightText: © 2025 Vivien Roggero
# All rights reserved.

# Color codes for logging (optional but convenient)
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[1;37m'
export NC='\033[0m' # No Color

# Timestamp helper
TIMESTAMP() { date '+%Y-%m-%d %H:%M:%S'; }

# Where we store generated passwords and logs
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PASSWORD_FILE="${SCRIPT_DIR}/.password"
export LOG_FILE="${SCRIPT_DIR}/deployment.log"

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#─────────────────────────────────────────────────────────────────────────────────────
# 2) LOGGING / UTILITY FUNCTIONS
#─────────────────────────────────────────────────────────────────────────────────────

log() {
    local level=$1
    local message=$2
    local color=""
    case $level in
      "INFO")    color=$BLUE  ;;
      "WARN")    color=$YELLOW;;
      "ERROR")   color=$RED   ;;
      "SUCCESS") color=$GREEN ;;
      "DEBUG")   color=$PURPLE;;
      "STEP")    color=$CYAN  ;;
      *)         color=$WHITE ;;
    esac

    local ts
    ts="$(TIMESTAMP)"
    local formatted_message="[${ts}] [${level}] ${message}"

    # Print to console with color
    echo -e "${color}${formatted_message}${NC}"
    # Also append to logfile (no colors)
    echo "${formatted_message}" >> "${LOG_FILE}"
}

debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "DEBUG" "$1"
    fi
}

error_exit() {
    local error_message="$1"
    local exit_code="${2:-1}"
    log "ERROR" "❌ ${error_message}"
    log "ERROR" "💥 Exiting at step: ${CURRENT_STEP:-unknown}"
    log "ERROR" "📋 Check log file: ${LOG_FILE}"
    exit "${exit_code}"
}

set_current_step() {
    local step="$1"
    log "=== $step ==="
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

#─────────────────────────────────────────────────────────────────────────────────────
# 3) USER‐CONFIGURABLE PARAMETERS — edit these if needed
#─────────────────────────────────────────────────────────────────────────────────────
# Check if .env file exists and load variables
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    log "STEP" "Loading environment variables from .env"
    # Read the .env file line by line
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ $line =~ ^#.*$ ]] && continue
        [[ -z $line ]] && continue
        
        # Extract variable name and value
        if [[ $line =~ ^([^=]+)=(.*)$ ]]; then
            var_name="${BASH_REMATCH[1]}"
            var_value="${BASH_REMATCH[2]}"
            
            # Remove any quotes from the value
            var_value="${var_value%\"}"
            var_value="${var_value#\"}"
            var_value="${var_value%\'}"
            var_value="${var_value#\'}"
            
            # Export the variable
            export "$var_name"="$var_value"
        fi
    done < "${SCRIPT_DIR}/.env"

    # Display loaded environment variables only in debug mode
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "INFO" "Loaded environment variables:"
        log "INFO" "----------------------------------------"
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip comments and empty lines
            [[ $line =~ ^#.*$ ]] && continue
            [[ -z $line ]] && continue
            
            # Extract variable name and value
            if [[ $line =~ ^([^=]+)=(.*)$ ]]; then
                var_name="${BASH_REMATCH[1]}"
                # Get the actual value from the environment
                var_value="${!var_name:-}"
                # Mask sensitive values
                if [[ "$var_name" =~ (PASSWORD|KEY|TOKEN|SECRET) ]]; then
                    var_value="********"
                fi
                log "INFO" "${var_name}=${var_value}"
            fi
        done < "${SCRIPT_DIR}/.env"
        log "INFO" "----------------------------------------"
    fi
else
    error_exit "❌ .env file not found. Please create it with required credentials."
fi

#─────────────────────────────────────────────────────────────────────────────────────
# 4) EXECUTE_COMMAND WRAPPER (with dry-run support)
#─────────────────────────────────────────────────────────────────────────────────────

execute_command() {
    local description="$1"
    shift
    local command="$*"
    
    debug "Executing: ${command}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "INFO" "🔍 DRY-RUN: Would execute: ${command}"
        return 0
    fi
    
    if ! eval "${command}"; then
        error_exit "Failed to ${description}"
    fi
    
    log "SUCCESS" "✅ ${description}"
}

# Validate required environment variables
validate_env() {
    local required_vars=("CLOUDFLARE_API_TOKEN" "DOMAIN_BASE")
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -ne 0 ]; then
        log "ERROR" "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            log "ERROR" "  - $var"
        done
        log "ERROR" "Please set these variables in your .env file"
        exit 1
    fi
}

# Validate environment variables
validate_env

#─────────────────────────────────────────────────────────────────────────────────────
# 5) Additional functions
#─────────────────────────────────────────────────────────────────────────────────────

# Function to check if microk8s is running
check_microk8s() {
    if ! command_exists microk8s; then
        echo "Error: microk8s is not installed"
        exit 1
    fi

    if ! microk8s status | grep -q "microk8s is running"; then
        echo "Error: microk8s is not running"
        exit 1
    fi
}

# Function to check if helm is available
check_helm() {
    if ! command_exists helm; then
        echo "Error: helm is not installed"
        exit 1
    fi
}

# Function to check if wget is available
check_wget() {
    if ! command_exists wget; then
        echo "Error: wget is not installed"
        exit 1
    fi
}

# Function to check if all required commands are available
check_requirements() {
    check_microk8s
    check_helm
    check_wget
}

# Check requirements
check_requirements
