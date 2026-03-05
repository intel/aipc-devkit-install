
#####################################################################################
# Dynatrace Setup and Configuartion script for Linux
# This script can be used to install and configure Dynatrace OneAgent on a Linux system.
# It accepts the following parameters:  
#   install_dt    - Installs Dynatrace OneAgent using the provided installation script
#   config_dt     - Configures Dynatrace OneAgent by setting the host group and monitoring mode
#   all           - Runs both installation and configuration steps in sequence  
# Usage:
#   ./setup.sh install_dt    # To install Dynatrace OneAgent
#   ./setup.sh config_dt     # To configure Dynatrace OneAgent (host group and monitoring mode)
#   ./setup.sh all           # To run both installation and configuration steps in sequence
# Pre-Requsities:
# 1) Ensure that the installation script 'Prod-amr-Dynatrace-OneAgent-Linux-latest.sh' is present in the same directory as this setup script before running with 'install_dt' or 'all' parameters.   
# 2) The script must be run with sudo privileges or as root to successfully install and configure Dynatrace OneAgent. If running without sudo, ensure that passwordless sudo is configured for the user executing the script.
# 3) The script is designed to be idempotent, meaning that running it multiple times will not cause issues or duplicate installations/configurations. It will check for existing installations and configurations before attempting to make changes.
# 4) This script is tested on Linux systems on AI PC Cloud and the Dynatrace versions that are running on cloud hosts
# 5) Make sure Dynatrace installation is complete and succesful before you jump directy to config_dt option.


# For any questions or issues, please contact vijay.chandrashekar@intel.com or cammeron.johnson@intel.com
#################################################################################################################################################################################################################################################

#!/bin/bash

# Exit on any kind of errors
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Error handler
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# Success message
success_msg() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

# Warning message
warning_msg() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

install_dynatrace() {
    echo "Installing Dynatrace OneAgent..."
    
    # if installation script exists
    if [ ! -f "./Prod-amr-Dynatrace-OneAgent-Linux-latest.sh" ]; then
        error_exit "Installation script 'Prod-amr-Dynatrace-OneAgent-Linux-latest.sh' not found in current directory"
    fi
    
    # if script has permissions to execute if not make it executable
    if [ ! -x "./Prod-amr-Dynatrace-OneAgent-Linux-latest.sh" ]; then
        warning_msg "Installation script is not executable. Making it executable..."
        chmod +x ./Prod-amr-Dynatrace-OneAgent-Linux-latest.sh || error_exit "Failed to make installation script executable"
    fi
    
    # if script runs as root or with sudo privileges
    if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
        error_exit "This script requires sudo privileges. Please run with sudo or ensure passwordless sudo is configured"
    fi
    
    # If installation is successful else error out
    if sudo ./Prod-amr-Dynatrace-OneAgent-Linux-latest.sh; then
        success_msg "Dynatrace OneAgent installed successfully"
    else
        error_exit "Dynatrace OneAgent installation failed"
    fi
}

configure_dynatrace() {
    echo "Configuring Dynatrace OneAgent..."
    
    # Check if oneagent is installed
    if [ ! -d "/opt/dynatrace/oneagent" ]; then
        error_exit "Dynatrace OneAgent not found. Please install it first using 'install_dt' parameter"
    fi
    
    # Check if oneagentctl tool exists
    if [ ! -f "/opt/dynatrace/oneagent/agent/tools/oneagentctl" ]; then
        error_exit "oneagentctl tool not found at /opt/dynatrace/oneagent/agent/tools/oneagentctl"
    fi
    
    # Check if running as root or with sudo privileges
    if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
        error_exit "This script requires sudo privileges. Please run with sudo or ensure passwordless sudo is configured"
    fi
    
    # Setting host group as per AI PC Cloud IAP and restart service
    echo "Setting host group to 43139_prod and restarting service..."
    if sudo /opt/dynatrace/oneagent/agent/tools/oneagentctl --set-host-group=43139_prod --restart-service; then
        success_msg "Host group set to 43139_prod and service restarted"
    else
        error_exit "Failed to set host group or restart service"
    fi
    
    # Set Dynatrave monitoring mode to infraonly as per AI PC Cloud.
    echo "Setting monitoring mode to infra-only..."
    if sudo /opt/dynatrace/oneagent/agent/tools/oneagentctl --set-monitoring-mode=infra-only; then
        success_msg "Monitoring mode set to infra-only"
    else
        error_exit "Failed to set monitoring mode"
    fi
    
    success_msg "Dynatrace OneAgent configured successfully"
}

# Check parameter
case "$1" in
    install_dt)
        install_dynatrace
        ;;
    config_dt)
        configure_dynatrace
        ;;
    all)
        install_dynatrace
        echo ""
        configure_dynatrace
        echo ""
        success_msg "All operations completed successfully"
        ;;
    *)
        echo "Usage: $0 {install_dt|config_dt|all}"
        echo ""
        echo "Available parameters:"
        echo "  install_dt    Install Dynatrace OneAgent"
        echo "  config_dt     Configure Dynatrace OneAgent (host group and monitoring mode)"
        echo "  all           Run both installation and configuration"
        exit 1
        ;;
esac

exit 0
