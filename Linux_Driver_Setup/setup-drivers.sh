#!/bin/bash

# Copyright (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e

# BKC
OS_ID="ubuntu"
OS_VERSION="24.04"
CURRENT_KERNEL_VERSION=$(uname -r)
# symbol
S_VALID="✓"
#S_INVALID="✗"

# Variables for compatibility checking
COMPATIBLE_IGC_TAG=""
COMPATIBLE_COMPUTE_RUNTIME_TAG=""
COMPATIBLE_NPU_DRIVER_TAG=""
COMPATIBLE_LEVEL_ZERO_TAG=""

# Function to get latest release tag from GitHub
get_latest_github_release() {
    local repo="$1"
    local version=$(curl -s "https://api.github.com/repos/$repo/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$version" ]; then
        echo "Error: Failed to get latest release for $repo"
        echo "Troubleshooting: Run './verify_connectivity.sh' to diagnose GitHub API connectivity issues"
        exit 1
    fi
    echo "$version"
}

# Function to get latest release assets from GitHub
get_github_release_assets() {
    local repo="$1"
    local tag="$2"
    local filter="$3"
    local assets=$(curl -s "https://api.github.com/repos/$repo/releases/tags/$tag" | grep '"browser_download_url":' | grep "$filter" | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$assets" ]; then
        echo "Error: Failed to get release assets for $repo tag $tag with filter $filter"
        echo "Troubleshooting: Run './verify_connectivity.sh' to diagnose GitHub API connectivity issues"
        exit 1
    fi
    echo "$assets"
}

# verify current user
if [ ! "$EUID" -eq 0 ]; then
    echo "Please run with sudo or root user"
    exit 1
fi


install_packages(){
    local PACKAGES=("$@")
    local INSTALL_REQUIRED=0
    for PACKAGE in "${PACKAGES[@]}"; do
        INSTALLED_VERSION=$(dpkg-query -W -f='${Version}' "$PACKAGE" 2>/dev/null || true)
        LATEST_VERSION=$(apt-cache policy "$PACKAGE" | grep Candidate | awk '{print $2}')
        
        if [ -z "$INSTALLED_VERSION" ] || [ "$INSTALLED_VERSION" != "$LATEST_VERSION" ]; then
            echo "$PACKAGE is not installed or not the latest version."
            INSTALL_REQUIRED=1
        fi
    done
    if [ $INSTALL_REQUIRED -eq 1 ]; then
        apt update
        apt install -y "${PACKAGES[@]}"
    fi
}



verify_dependencies(){
    echo -e "# Verifying dependencies"
    DEPENDENCIES_PACKAGES=(
        git
        clinfo
        curl
        wget
        gpg-agent
        libtbb12
        dpkg-dev
    )
    install_packages "${DEPENDENCIES_PACKAGES[@]}"
    echo "$S_VALID Dependencies installed"
}

verify_intel_gpu_package_repo(){
    if [ ! -e /etc/apt/sources.list.d/intel-gpu-noble.list ]; then
        echo "Adding Intel GPU repository"
        wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | \
        gpg --yes --dearmor --output /usr/share/keyrings/intel-graphics.gpg
        echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu noble client" | \
        tee /etc/apt/sources.list.d/intel-gpu-noble.list
        apt update
        apt-get install -y libze-intel-gpu1 libze1 intel-opencl-icd clinfo intel-gsc
        apt update
        apt -y dist-upgrade

    fi

}

verify_igpu_driver(){
    echo -e "Verifying iGPU driver"

    if [ -z "$(clinfo | grep 'Driver Version' | awk '{print $NF}')" ] && [ ! -e /etc/apt/sources.list.d/intel-gpu-noble.list ]; then
        verify_intel_gpu_package_repo
        IGPU_PACKAGES=(
        libze1
        intel-level-zero-gpu
        intel-opencl-icd
        clinfo
	    vainfo
	    hwinfo
        )
        install_packages "${IGPU_PACKAGES[@]}"
        FIRMWARE=(linux-firmware)
        install_packages "${FIRMWARE[@]}"

         # $USER here is root
        if ! id -nG "$USER" | grep -q -w '\<video\>'; then
            echo "Adding current user ($USER) to 'video' group"
            usermod -aG video "$USER"
        fi
        if ! id -nG "$USER" | grep -q '\<render\>'; then
            echo "Adding current user ($USER) to 'render' group"
            usermod -aG render "$USER"
        fi

        # Get the native user who invoked sudo
        NATIVE_USER="$(logname)"
        
        if ! id -nG "$NATIVE_USER" | grep -q -w '\<video\>'; then
            echo "Adding native user ($NATIVE_USER) to 'video' group"
            usermod -aG video "$NATIVE_USER"
        fi
        if ! id -nG "$NATIVE_USER" | grep -q '\<render\>'; then
            echo "Adding native user ($NATIVE_USER) to 'render' group"
            usermod -aG render "$NATIVE_USER"
        fi
    fi
}

verify_compute_runtime(){
    echo -e "\n# Verifying Intel(R) Compute Runtime drivers"

    CURRENT_DIR=$(pwd)
    
    # Get compatible versions using compatibility checking
    if [ -z "$COMPATIBLE_IGC_TAG" ] || [ -z "$COMPATIBLE_COMPUTE_RUNTIME_TAG" ]; then
        echo "🔍 Running compatibility analysis..."
        get_compatible_driver_versions
    fi
    
    IGC_VERSION="$COMPATIBLE_IGC_TAG"
    COMPUTE_RUNTIME_VERSION="$COMPATIBLE_COMPUTE_RUNTIME_TAG"
    
    echo -e "✅ Install Intel(R) Graphics Compiler version: $IGC_VERSION (compatibility verified)"
    echo -e "✅ Install Intel(R) Compute Runtime drivers version: $COMPUTE_RUNTIME_VERSION"
    
    if [ -d /tmp/neo_temp ];then
        echo -e "Found existing folder in path /tmp/neo_temp. Removing the folder"
        rm -rf /tmp/neo_temp
    fi
    
    echo -e "Downloading compute runtime packages"
    mkdir -p /tmp/neo_temp
    cd /tmp/neo_temp
    
    # Download Intel Graphics Compiler packages
    get_github_release_assets "intel/intel-graphics-compiler" "$IGC_VERSION" "intel-igc-core.*amd64.deb" | head -1 | xargs wget
    get_github_release_assets "intel/intel-graphics-compiler" "$IGC_VERSION" "intel-igc-opencl.*amd64.deb" | head -1 | xargs wget
    
    # Download Intel Compute Runtime packages
    get_github_release_assets "intel/compute-runtime" "$COMPUTE_RUNTIME_VERSION" "intel-ocloc_.*amd64.deb" | head -1 | xargs wget
    get_github_release_assets "intel/compute-runtime" "$COMPUTE_RUNTIME_VERSION" "libze-intel-gpu1-dbgsym.*amd64.ddeb" | head -1 | xargs wget
    get_github_release_assets "intel/compute-runtime" "$COMPUTE_RUNTIME_VERSION" "libze-intel-gpu1_.*amd64.deb" | head -1 | xargs wget
    get_github_release_assets "intel/compute-runtime" "$COMPUTE_RUNTIME_VERSION" "intel-opencl-icd-dbgsym.*amd64.ddeb" | head -1 | xargs wget
    get_github_release_assets "intel/compute-runtime" "$COMPUTE_RUNTIME_VERSION" "intel-opencl-icd_.*amd64.deb" | head -1 | xargs wget
    get_github_release_assets "intel/compute-runtime" "$COMPUTE_RUNTIME_VERSION" "libigdgmm12.*amd64.deb" | head -1 | xargs wget
    
    echo -e "Verify sha256 sums for packages (if available)"
    CHECKSUM_URL=$(get_github_release_assets "intel/compute-runtime" "$COMPUTE_RUNTIME_VERSION" ".*\.sum" | head -1)
    if [ ! -z "$CHECKSUM_URL" ]; then
        wget "$CHECKSUM_URL"
        sha256sum -c *.sum || echo "Warning: Checksum verification failed or not available"
    else
        echo "No checksum file found, skipping verification"
    fi

    echo -e "\nInstalling compute runtime as root"
    apt remove -y intel-ocloc libze-intel-gpu1 || true
    dpkg -i ./*.deb 

    cd ..
    echo -e "Cleaning up /tmp/neo_temp folder after installation"
    rm -rf neo_temp
    cd "$CURRENT_DIR"
    
}

verify_os() {
    echo -e "\n# Verifying operating system"
    if [ ! -e /etc/os-release ]; then
        echo "Error: /etc/os-release file not found"
        exit 1
    fi
    CURRENT_OS_ID=$(grep -E '^ID=' /etc/os-release | cut -d'=' -f2- | tr -d '"')
    CURRENT_OS_VERSION=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d'=' -f2- | tr -d '"')
    if [ "$OS_ID" != "$CURRENT_OS_ID" ] || [ "$OS_VERSION" != "$CURRENT_OS_VERSION" ]; then
        echo "Error: OS is not supported. Please make sure $OS_ID $OS_VERSION is installed"
        exit 1
    fi
    echo "$S_VALID OS version: $CURRENT_OS_ID $CURRENT_OS_VERSION"
}

verify_npu_driver(){
    echo -e "Verifying NPU drivers"

    CURRENT_DIR=$(pwd)
    COMPILER_PKG=$(dpkg-query -l "intel-driver-compiler-npu" 2>/dev/null || true)
    LEVEL_ZERO_PKG=$(dpkg-query -l "intel-level-zero-npu" 2>/dev/null || true)

    if [[ -z $COMPILER_PKG || -z $LEVEL_ZERO_PKG ]]; then
        echo -e "NPU Driver is not installed. Proceed installing"
        dpkg --purge --force-remove-reinstreq intel-driver-compiler-npu intel-fw-npu intel-level-zero-npu || true
        apt install --fix-broken
        apt update

        # Get compatible versions using compatibility checking
        if [ -z "$COMPATIBLE_NPU_DRIVER_TAG" ] || [ -z "$COMPATIBLE_LEVEL_ZERO_TAG" ]; then
            echo "🔍 Running compatibility analysis..."
            get_compatible_driver_versions
        fi
        
        NPU_DRIVER_VERSION="$COMPATIBLE_NPU_DRIVER_TAG"
        LEVEL_ZERO_VERSION="$COMPATIBLE_LEVEL_ZERO_TAG"
        
        echo -e "✅ Installing NPU Driver version: $NPU_DRIVER_VERSION (compatibility verified)"
        echo -e "✅ Installing Level Zero version: $LEVEL_ZERO_VERSION"

        if [ -d /tmp/npu_temp ];then
            rm -rf /tmp/npu_temp
        fi
        
        mkdir /tmp/npu_temp
        cd /tmp/npu_temp

        # Download NPU driver packages
        get_github_release_assets "intel/linux-npu-driver" "$NPU_DRIVER_VERSION" "intel-driver-compiler-npu.*ubuntu24.04.*amd64.deb" | head -1 | xargs wget
        get_github_release_assets "intel/linux-npu-driver" "$NPU_DRIVER_VERSION" "intel-fw-npu.*ubuntu24.04.*amd64.deb" | head -1 | xargs wget
        get_github_release_assets "intel/linux-npu-driver" "$NPU_DRIVER_VERSION" "intel-level-zero-npu.*ubuntu24.04.*amd64.deb" | head -1 | xargs wget
        
        # Download Level Zero package
        get_github_release_assets "oneapi-src/level-zero" "$LEVEL_ZERO_VERSION" "level-zero_.*u24.04.*amd64.deb" | head -1 | xargs wget
        
        dpkg -i ./*.deb
                                                                                                                                                                                             
        cd ..
        rm -rf npu_temp
        cd "$CURRENT_DIR"
        
        chown root:render /dev/accel/accel0
        chmod g+rw /dev/accel/accel0
        bash -c "echo 'SUBSYSTEM==\"accel\", KERNEL==\"accel*\", GROUP=\"render\", MODE=\"0660\"' > /etc/udev/rules.d/10-intel-vpu.rules"
        udevadm control --reload-rules
        udevadm trigger --subsystem-match=accel
    fi
}

verify_gpu() {
    echo -e "\n# Verifying GPU"
    DGPU="$(lspci | grep VGA | grep Intel -c)"

    if [ "$DGPU" -ge 1 ]; then
        if [ ! -e "/dev/dri" ]; then
            IGPU=1
        else
            IGPU="$(find /dev/dri -maxdepth 1 -type c -name 'renderD128*' | wc -l)"
        fi
    fi
    if [ -e "/dev/dri" ]; then
        IGPU="$(find /dev/dri -maxdepth 1 -type c -name 'renderD128*' | wc -l)"
    fi

    if [ "$DGPU" -ge 2 ]; then
        GPU_STAT_LABEL="- iGPU\n-dGPU (default)"
    else
        if [ "$IGPU" -lt 1 ]; then
            GPU_STAT_LABEL="- n/a"
        else
            GPU_STAT_LABEL="- iGPU (default)"   
        fi
    fi
    echo -e "$GPU_STAT_LABEL"
}

verify_kernel() {
    echo -e "\n# Verifying kernel version"
    CURRENT_KERNEL_VERSION=$(uname -r)
    echo "$S_VALID Kernel version: $CURRENT_KERNEL_VERSION"
    
    # Check if running a recent enough kernel for Intel GPU/NPU support
    KERNEL_MAJOR=$(echo "$CURRENT_KERNEL_VERSION" | cut -d'.' -f1)
    KERNEL_MINOR=$(echo "$CURRENT_KERNEL_VERSION" | cut -d'.' -f2)
    
    if [ "$KERNEL_MAJOR" -lt 6 ] || ([ "$KERNEL_MAJOR" -eq 6 ] && [ "$KERNEL_MINOR" -lt 8 ]); then
        echo "Warning: Kernel version $CURRENT_KERNEL_VERSION may not fully support Intel GPU/NPU drivers."
        echo "Consider upgrading to kernel 6.8 or newer for optimal compatibility."
    fi
}

verify_platform() {
    echo -e "\n# Verifying platform"
    CPU_MODEL=$(< /proc/cpuinfo grep -m1 "model name" | cut -d: -f2 | sed 's/^[ \t]*//')
    echo "- CPU model: $CPU_MODEL"
}

verify_drivers(){
    echo -e "\n#Verifying drivers"
    verify_igpu_driver
    
    # Check if GPU driver is properly installed
    GPU_DRIVER_VERSION="$(clinfo | grep 'Driver Version' | awk '{print $NF}' 2>/dev/null || echo 'Not detected')"
    if [ "$GPU_DRIVER_VERSION" = "Not detected" ]; then
        echo "Warning: GPU driver not detected or clinfo not available"
    else
        echo "$S_VALID Intel GPU Drivers: $GPU_DRIVER_VERSION"
    fi

    verify_npu_driver
    
    NPU_DRIVER_VERSION="$(sudo dmesg | grep vpu | awk 'NR==3{ print; }' | awk -F " " '{print $5" "$6" "$7}' 2>/dev/null || echo 'Not detected')"
    if [ "$NPU_DRIVER_VERSION" = "Not detected" ]; then
        echo "Warning: NPU driver not detected in dmesg"
    else
        echo "$S_VALID Intel NPU Drivers: $NPU_DRIVER_VERSION"
    fi
}

# Function to download and inspect compute-runtime .deb for IGC dependencies
find_compatible_igc_version() {
    local compute_runtime_tag="$1"
    echo "  Analyzing compute runtime $compute_runtime_tag for IGC dependencies..." >&2
    
    # Create temporary directory for inspection
    local temp_dir=$(mktemp -d)
    cleanup() { rm -rf "$temp_dir"; }
    trap cleanup EXIT
    
    # Get the compute runtime .deb download URL
    local response=$(curl -s "https://api.github.com/repos/intel/compute-runtime/releases/tags/$compute_runtime_tag")
    
    # Find intel-opencl-icd package (contains IGC dependency)
    local opencl_icd_url=$(echo "$response" | grep '"browser_download_url":' | grep 'intel-opencl-icd_.*amd64\.deb"' | sed -E 's/.*"([^"]+)".*/\1/' | head -1)
    
    if [ -z "$opencl_icd_url" ]; then
        echo "  Could not find intel-opencl-icd package in compute runtime release" >&2
        return 1
    fi
    
    echo "  Downloading package for dependency analysis..." >&2
    cd "$temp_dir"
    
    # Download the package
    if ! wget -q "$opencl_icd_url"; then
        echo "  Failed to download package for analysis" >&2
        return 1
    fi
    
    local deb_file=$(basename "$opencl_icd_url")
    
    # Extract package control information
    if ! dpkg-deb --field "$deb_file" Depends > depends.txt 2>/dev/null; then
        echo "  Failed to extract package dependencies" >&2
        return 1
    fi
    
    echo "  Package dependencies:" >&2
    cat depends.txt >&2
    echo >&2
    
    # Look for IGC dependency pattern - try multiple patterns
    local igc_dep=""
    
    # Pattern 1: intel-igc-opencl (>= version)
    igc_dep=$(grep -o 'intel-igc-opencl[[:space:]]*([^)]*' depends.txt 2>/dev/null | sed 's/.*(//' | sed 's/[[:space:]]*$//' || echo "")
    
    if [ -z "$igc_dep" ]; then
        # Pattern 2: intel-igc-opencl = version
        igc_dep=$(grep -o 'intel-igc-opencl[[:space:]]*=[[:space:]]*[^,[:space:]]*' depends.txt 2>/dev/null | sed 's/.*=[[:space:]]*//' || echo "")
    fi
    
    if [ -z "$igc_dep" ]; then
        # Pattern 3: Look for any intel-igc reference
        igc_dep=$(grep -o 'intel-igc[^,[:space:]]*[[:space:]]*([^)]*' depends.txt 2>/dev/null | sed 's/.*(//' | sed 's/[[:space:]]*$//' || echo "")
    fi
    
    if [ -z "$igc_dep" ]; then
        echo "  No specific IGC version dependency found" >&2
        return 1
    fi
    
    echo "  Found IGC dependency: $igc_dep" >&2
    
    # Extract version number from dependency (format: >= 1.0.15136.24)
    local igc_version=$(echo "$igc_dep" | grep -o '[0-9][0-9.]*[0-9]' | head -1)
    
    if [ -z "$igc_version" ]; then
        echo "  Could not parse IGC version from dependency" >&2
        return 1
    fi
    
    echo "$igc_version"
    return 0
}

# Function to find IGC GitHub tag matching a specific version
find_igc_tag_for_version() {
    local required_version="$1"
    echo "  Searching for IGC tag matching version $required_version..." >&2
    
    # Get list of IGC releases
    local response=$(curl -s "https://api.github.com/repos/intel/intel-graphics-compiler/releases?per_page=50")
    
    if [ -z "$response" ]; then
        echo "  Failed to get IGC releases" >&2
        return 1
    fi
    
    # Look for tags that contain or match the required version
    local matching_tag=$(echo "$response" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | grep -E "^(igc-|v)?${required_version}" | head -1)
    
    if [ -z "$matching_tag" ]; then
        # Try more flexible matching - look for tags containing the version
        matching_tag=$(echo "$response" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | grep "$required_version" | head -1)
    fi
    
    if [ -z "$matching_tag" ]; then
        echo "  No IGC tag found for version $required_version" >&2
        echo "  Available recent tags:" >&2
        echo "$response" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | head -5 | sed 's/^/    /' >&2
        return 1
    fi
    
    echo "  Found matching IGC tag: $matching_tag" >&2
    echo "$matching_tag"
    return 0
}

# Function to get compatible driver versions
get_compatible_driver_versions() {
    echo "🔍 Determining compatible driver versions..." >&2
    
    # First, get the latest compute runtime version
    echo "📡 Getting latest compute runtime version..." >&2
    local compute_runtime_tag=$(get_latest_github_release "intel/compute-runtime")
    echo "  Latest compute runtime: $compute_runtime_tag" >&2
    
    # Find compatible IGC version
    echo "🔍 Finding compatible IGC version..." >&2
    local compatible_igc_version=$(find_compatible_igc_version "$compute_runtime_tag")
    if [ $? -ne 0 ]; then
        echo "⚠️  Could not determine compatible IGC version, using latest..." >&2
        COMPATIBLE_IGC_TAG=$(get_latest_github_release "intel/intel-graphics-compiler")
        echo "  Using latest IGC: $COMPATIBLE_IGC_TAG" >&2
    else
        echo "  Required IGC version: $compatible_igc_version" >&2
        COMPATIBLE_IGC_TAG=$(find_igc_tag_for_version "$compatible_igc_version")
        if [ $? -ne 0 ]; then
            echo "⚠️  Could not find IGC tag for version $compatible_igc_version, using latest..." >&2
            COMPATIBLE_IGC_TAG=$(get_latest_github_release "intel/intel-graphics-compiler")
        else
            echo "  ✅ Found compatible IGC tag: $COMPATIBLE_IGC_TAG" >&2
        fi
    fi
    
    # Set compatible versions
    COMPATIBLE_COMPUTE_RUNTIME_TAG="$compute_runtime_tag"
    COMPATIBLE_NPU_DRIVER_TAG=$(get_latest_github_release "intel/linux-npu-driver")
    COMPATIBLE_LEVEL_ZERO_TAG=$(get_latest_github_release "oneapi-src/level-zero")
    
    echo >&2
    echo "📋 Selected compatible versions:" >&2
    echo "  IGC: $COMPATIBLE_IGC_TAG" >&2
    echo "  Compute Runtime: $COMPATIBLE_COMPUTE_RUNTIME_TAG" >&2
    echo "  NPU Driver: $COMPATIBLE_NPU_DRIVER_TAG" >&2
    echo "  Level Zero: $COMPATIBLE_LEVEL_ZERO_TAG" >&2
    echo >&2
}

setup(){
    echo "# Intel AI PC Linux Setup - Driver Installation with Compatibility Checking"
    echo "# This script automatically determines compatible driver versions to prevent conflicts"
    echo "# If installation fails due to download issues, run './verify_connectivity.sh' for diagnostics"
    echo
    
    # Initialize compatibility checking
    echo "🔍 Analyzing driver compatibility..."
    get_compatible_driver_versions
    
    verify_dependencies
    verify_platform
    verify_gpu
    verify_os
    verify_drivers
    verify_kernel
    verify_compute_runtime
    

    echo -e "\n# Status"
    echo "$S_VALID Platform configured"

}

setup
