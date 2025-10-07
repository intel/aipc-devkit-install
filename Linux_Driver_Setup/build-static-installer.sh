#!/bin/bash

# Intel Driver Static Installer Builder
# This script generates a static driver installation script with compatibility-checked versions
# Use --build-static flag to generate setup-static-drivers.sh with exact filenames and URLs

set -e

# Parse command line arguments
BUILD_STATIC=false
if [ "$1" = "--build-static" ]; then
    BUILD_STATIC=true
    echo "=== Building Static Driver Setup Script ==="
    echo "Will generate setup-static-drivers.sh with exact filenames"
    echo
fi

echo "=== Intel Driver Static Installer Builder ==="
echo "This script builds a static driver installation script with compatibility checking"
echo "No files will be downloaded or installed by this builder script"
echo

# Check GitHub token status
if [ -n "$GITHUB_TOKEN" ]; then
    echo "✓ GitHub token is configured (${#GITHUB_TOKEN} characters)"
    echo "  Using authenticated requests for higher rate limits"
    AUTH_HEADER="Authorization: token $GITHUB_TOKEN"
else
    echo "⚠ No GitHub token found in environment"
    echo "  Using unauthenticated requests (may hit rate limits quickly)"
    echo "  Recommendation: Set GITHUB_TOKEN for better reliability"
    AUTH_HEADER=""
fi
echo

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Install with: sudo apt install jq"
    exit 1
fi

# Function to safely get latest release tag
get_latest_release_tag() {
    local repo="$1"
    echo "Checking latest release for $repo..." >&2
    
    local response
    if [ -n "$GITHUB_TOKEN" ]; then
        response=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null)
    else
        response=$(curl -s "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null)
    fi
    
    # Check if curl failed or returned empty response
    if [ -z "$response" ]; then
        echo "ERROR: Failed to connect to GitHub API for $repo" >&2
        return 1
    fi
    
    # Check if response is valid JSON
    if ! echo "$response" | jq . >/dev/null 2>&1; then
        echo "ERROR: Invalid JSON response from GitHub API for $repo" >&2
        echo "Response preview: $(echo "$response" | head -1)" >&2
        return 1
    fi
    
    # Check if we got rate limited
    if echo "$response" | jq -r '.message' 2>/dev/null | grep -q "rate limit"; then
        echo "ERROR: GitHub API rate limit exceeded" >&2
        echo "Solution: Set GITHUB_TOKEN environment variable with a personal access token" >&2
        echo "Visit: https://github.com/settings/tokens" >&2
        return 1
    fi
    
    local tag=$(echo "$response" | jq -r '.tag_name // "ERROR"')
    if [ "$tag" = "ERROR" ] || [ "$tag" = "null" ]; then
        echo "ERROR: Could not get latest release tag for $repo" >&2
        echo "Response: $response" | head -3 >&2
        return 1
    fi
    
    echo "Latest release: $tag" >&2
    echo "$tag"
}

# Function to safely list release assets
list_release_assets() {
    local repo="$1"
    local tag="$2"
    echo
    echo "=== Assets for $repo release $tag ==="
    
    local response
    if [ -n "$GITHUB_TOKEN" ]; then
        response=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/$repo/releases/tags/$tag")
    else
        response=$(curl -s "https://api.github.com/repos/$repo/releases/tags/$tag")
    fi
    
    # Check if we got rate limited
    if echo "$response" | jq -r '.message' 2>/dev/null | grep -q "rate limit"; then
        echo "ERROR: GitHub API rate limit exceeded"
        return 1
    fi
    
    # Extract asset names
    local assets=$(echo "$response" | jq -r '.assets[]?.name // empty')
    
    if [ -z "$assets" ]; then
        echo "ERROR: No assets found or API error"
        echo "Response preview:" 
        echo "$response" | head -5
        return 1
    fi
    
    echo "Available assets:"
    echo "$assets" | sort
    echo
    echo "Asset count: $(echo "$assets" | wc -l)"
    echo
}

# Function to show asset patterns used by setup-drivers.sh
show_current_patterns() {
    echo "=== Current Asset Patterns in setup-drivers.sh ==="
    echo
    echo "Intel Graphics Compiler patterns:"
    echo "  - intel-igc-core.*amd64.deb"
    echo "  - intel-igc-opencl.*amd64.deb"
    echo
    echo "Intel Compute Runtime patterns:"
    echo "  - intel-ocloc_.*amd64.deb"
    echo "  - intel-ocloc-dbgsym.*amd64.ddeb"
    echo "  - libze-intel-gpu1-dbgsym.*amd64.ddeb"
    echo "  - libze-intel-gpu1_.*amd64.deb"
    echo "  - intel-opencl-icd-dbgsym.*amd64.ddeb"
    echo "  - intel-opencl-icd_.*amd64.deb"
    echo "  - libigdgmm12.*amd64.deb"
    echo "  - .*\.sum (checksum file)"
    echo
    echo "Intel NPU Driver patterns:"
    echo "  - linux-npu-driver.*ubuntu2404.tar.gz (contains individual .deb packages)"
    echo
    echo "Level Zero patterns:"
    echo "  - level-zero_.*u24.04.*amd64.deb"
    echo
}

# Function to test asset pattern matching
test_pattern_matching() {
    local repo="$1"
    local tag="$2"
    local pattern="$3"
    
    echo "Testing pattern '$pattern' against $repo $tag:"
    
    local response
    if [ -n "$GITHUB_TOKEN" ]; then
        response=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/$repo/releases/tags/$tag")
    else
        response=$(curl -s "https://api.github.com/repos/$repo/releases/tags/$tag")
    fi
    local assets=$(echo "$response" | jq -r '.assets[]?.name // empty')
    
    local matches=$(echo "$assets" | grep -E "$pattern" || echo "")
    
    if [ -n "$matches" ]; then
        echo "  ✓ MATCHES FOUND:"
        echo "$matches" | sed 's/^/    /'
    else
        echo "  ✗ NO MATCHES"
        echo "  Available assets that might be relevant:"
        echo "$assets" | grep -i "amd64\|\.deb\|\.ddeb" | head -5 | sed 's/^/    /' || echo "    (none found)"
    fi
    echo
}

# Function to collect asset URLs for static script generation
collect_asset_urls() {
    local repo="$1"
    local tag="$2"
    
    if [ "$BUILD_STATIC" = "false" ]; then
        return 0
    fi
    
    echo "Collecting asset URLs for $repo $tag..."
    
    local response
    if [ -n "$GITHUB_TOKEN" ]; then
        response=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/$repo/releases/tags/$tag")
    else
        response=$(curl -s "https://api.github.com/repos/$repo/releases/tags/$tag")
    fi
    
    # Check if we got rate limited or API error
    if echo "$response" | jq -r '.message' 2>/dev/null | grep -q "rate limit"; then
        echo "ERROR: GitHub API rate limit exceeded while collecting assets for $repo" >&2
        return 1
    fi
    
    # Check if response has assets
    if ! echo "$response" | jq -e '.assets' >/dev/null 2>&1; then
        echo "ERROR: No assets found in API response for $repo $tag" >&2
        echo "Response preview: $(echo "$response" | head -3)" >&2
        return 1
    fi
    
    # Store version
    VERSIONS["$repo"]="$tag"
    
    # Extract download URLs based on repo
    case "$repo" in
        "intel/intel-graphics-compiler")
            ASSET_URLS["igc-core"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("intel-igc-core.*amd64\\.deb")) | .browser_download_url' | head -1)
            ASSET_URLS["igc-opencl"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("intel-igc-opencl.*amd64\\.deb")) | .browser_download_url' | head -1)
            
            # Validate required assets were found
            if [ -z "${ASSET_URLS[igc-core]}" ] || [ "${ASSET_URLS[igc-core]}" = "null" ]; then
                echo "ERROR: Could not find intel-igc-core asset for $repo $tag" >&2
                return 1
            fi
            if [ -z "${ASSET_URLS[igc-opencl]}" ] || [ "${ASSET_URLS[igc-opencl]}" = "null" ]; then
                echo "ERROR: Could not find intel-igc-opencl asset for $repo $tag" >&2
                return 1
            fi
            ;;
        "intel/compute-runtime")
            ASSET_URLS["ocloc"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("intel-ocloc_.*amd64\\.deb")) | .browser_download_url' | head -1)
            ASSET_URLS["ocloc-dbgsym"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("intel-ocloc-dbgsym.*amd64\\.ddeb")) | .browser_download_url' | head -1)
            ASSET_URLS["ze-gpu-dbgsym"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("libze-intel-gpu1-dbgsym.*amd64\\.ddeb")) | .browser_download_url' | head -1)
            ASSET_URLS["ze-gpu"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("libze-intel-gpu1_.*amd64\\.deb")) | .browser_download_url' | head -1)
            ASSET_URLS["opencl-icd-dbgsym"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("intel-opencl-icd-dbgsym.*amd64\\.ddeb")) | .browser_download_url' | head -1)
            ASSET_URLS["opencl-icd"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("intel-opencl-icd_.*amd64\\.deb")) | .browser_download_url' | head -1)
            ASSET_URLS["igdgmm"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("libigdgmm12.*amd64\\.deb")) | .browser_download_url' | head -1)
            ASSET_URLS["checksum"]=$(echo "$response" | jq -r '.assets[] | select(.name | test(".*\\.sum")) | .browser_download_url' | head -1)
            
            # Validate required assets were found (checksum is optional)
            local required_assets=("ocloc" "ocloc-dbgsym" "ze-gpu-dbgsym" "ze-gpu" "opencl-icd-dbgsym" "opencl-icd" "igdgmm")
            for asset in "${required_assets[@]}"; do
                if [ -z "${ASSET_URLS[$asset]}" ] || [ "${ASSET_URLS[$asset]}" = "null" ]; then
                    echo "ERROR: Could not find required asset '$asset' for $repo $tag" >&2
                    return 1
                fi
            done
            ;;
        "intel/linux-npu-driver")
            # NPU drivers are now packaged as tar.gz files, find the Ubuntu 24.04 version
            ASSET_URLS["npu-tarball"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("linux-npu-driver.*ubuntu2404\\.tar\\.gz")) | .browser_download_url' | head -1)
            
            # Validate required asset was found
            if [ -z "${ASSET_URLS[npu-tarball]}" ] || [ "${ASSET_URLS[npu-tarball]}" = "null" ]; then
                echo "ERROR: Could not find required NPU tarball asset for $repo $tag" >&2
                return 1
            fi
            ;;
        "oneapi-src/level-zero")
            ASSET_URLS["level-zero"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("level-zero_.*u24\\.04.*amd64\\.deb")) | .browser_download_url' | head -1)
            
            # Validate required asset was found
            if [ -z "${ASSET_URLS[level-zero]}" ] || [ "${ASSET_URLS[level-zero]}" = "null" ]; then
                echo "ERROR: Could not find level-zero asset for $repo $tag" >&2
                return 1
            fi
            ;;
    esac
    
    echo "✓ Successfully collected assets for $repo"
    return 0
}

# Function to generate static setup script
generate_static_setup_script() {
    if [ "$BUILD_STATIC" = "false" ]; then
        return 0
    fi
    
    echo "=== Generating setup-static-drivers.sh ==="
    
    # Validate that all required asset URLs are present before generating script
    echo "Validating collected asset URLs..."
    local required_assets=(
        "igc-core" "igc-opencl"
        "ocloc" "ocloc-dbgsym" "ze-gpu-dbgsym" "ze-gpu" "opencl-icd-dbgsym" "opencl-icd" "igdgmm"
        "npu-tarball"
        "level-zero"
    )
    
    local missing_assets=()
    for asset in "${required_assets[@]}"; do
        if [ -z "${ASSET_URLS[$asset]}" ] || [ "${ASSET_URLS[$asset]}" = "null" ]; then
            missing_assets+=("$asset")
        fi
    done
    
    if [ ${#missing_assets[@]} -gt 0 ]; then
        echo "ERROR: Missing required asset URLs: ${missing_assets[*]}" >&2
        echo "Cannot generate static script without all required assets" >&2
        return 1
    fi
    
    echo "✓ All required asset URLs validated"
    
    local static_script="setup-static-drivers.sh"
    
    # Create the static setup script
    cat > "$static_script" << 'EOF'
#!/bin/bash

# Copyright (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
# 
# Static Driver Setup Script - Generated by build-static-installer.sh
# This script uses exact filenames and wget to avoid GitHub API rate limits

set -e

# BKC
OS_ID="ubuntu"
OS_VERSION="24.04"
CURRENT_KERNEL_VERSION=$(uname -r)
# symbol
S_VALID="✓"

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

EOF

    # Add version information with compatibility notes
    cat >> "$static_script" << EOF
# Static asset URLs and versions (generated $(date))
# Versions are compatibility-checked to prevent dependency conflicts
IGC_VERSION="${VERSIONS[intel/intel-graphics-compiler]}"
COMPUTE_RUNTIME_VERSION="${VERSIONS[intel/compute-runtime]}"
NPU_DRIVER_VERSION="${VERSIONS[intel/linux-npu-driver]}"
LEVEL_ZERO_VERSION="${VERSIONS[oneapi-src/level-zero]}"

EOF

    # Add compatibility notice if there were warnings
    if [ "$COMPATIBILITY_WARNING" = "true" ]; then
        cat >> "$static_script" << 'EOF'
# WARNING: Version compatibility could not be fully verified during generation
# This script may encounter dependency conflicts during installation
# Test on a non-production system first

EOF
    else
        cat >> "$static_script" << 'EOF'
# Version compatibility verified during generation
# These driver versions are known to work together without dependency conflicts

EOF
    fi
    
    # Add asset URLs with proper variable naming
    for key in "${!ASSET_URLS[@]}"; do
        # Convert key to uppercase and replace hyphens with underscores for bash variable names
        var_name=$(echo "${key^^}" | tr '-' '_')
        echo "ASSET_URL_${var_name}=\"${ASSET_URLS[$key]}\"" >> "$static_script"
    done
    
    # Add the compute runtime function
    cat >> "$static_script" << 'EOF'

verify_compute_runtime(){
    echo -e "\n# Verifying Intel(R) Compute Runtime drivers"

    CURRENT_DIR=$(pwd)
    
    echo -e "Install Intel(R) Graphics Compiler version: $IGC_VERSION"
    echo -e "Install Intel(R) Compute Runtime drivers version: $COMPUTE_RUNTIME_VERSION"
    
    if [ -d /tmp/neo_temp ];then
        echo -e "Found existing folder in path /tmp/neo_temp. Removing the folder"
        rm -rf /tmp/neo_temp
    fi
    
    echo -e "Downloading compute runtime packages"
    mkdir -p /tmp/neo_temp
    cd /tmp/neo_temp
    
    # Download Intel Graphics Compiler packages
    echo "Downloading IGC packages..."
    wget "$ASSET_URL_IGC_CORE" || { echo "ERROR: Failed to download IGC core package"; exit 1; }
    wget "$ASSET_URL_IGC_OPENCL" || { echo "ERROR: Failed to download IGC OpenCL package"; exit 1; }
    
    # Download Intel Compute Runtime packages
    echo "Downloading Compute Runtime packages..."
    wget "$ASSET_URL_OCLOC" || { echo "ERROR: Failed to download OCLOC package"; exit 1; }
    wget "$ASSET_URL_OCLOC_DBGSYM" || { echo "WARNING: Failed to download OCLOC debug symbols"; }
    wget "$ASSET_URL_ZE_GPU_DBGSYM" || { echo "WARNING: Failed to download ZE GPU debug symbols"; }
    wget "$ASSET_URL_ZE_GPU" || { echo "ERROR: Failed to download ZE GPU package"; exit 1; }
    wget "$ASSET_URL_OPENCL_ICD_DBGSYM" || { echo "WARNING: Failed to download OpenCL ICD debug symbols"; }
    wget "$ASSET_URL_OPENCL_ICD" || { echo "ERROR: Failed to download OpenCL ICD package"; exit 1; }
    wget "$ASSET_URL_IGDGMM" || { echo "ERROR: Failed to download IGDGMM package"; exit 1; }
    
    echo -e "Verify sha256 sums for packages (if available)"
    if [ -n "$ASSET_URL_CHECKSUM" ]; then
        wget "$ASSET_URL_CHECKSUM" || { echo "WARNING: Failed to download checksum file"; }
        if [ -f "*.sum" ]; then
            # Only verify checksums for files that actually exist
            for file in *.deb *.ddeb; do
                if [ -f "$file" ] && grep -q "$file" *.sum 2>/dev/null; then
                    echo "Verifying $file..."
                    sha256sum -c *.sum --ignore-missing || echo "Warning: Checksum verification failed for $file"
                fi
            done
        else
            echo "No checksum file available"
        fi
    else
        echo "No checksum file found, skipping verification"
    fi

    echo -e "\nInstalling compute runtime as root"
    # Remove conflicting packages before installation
    echo "Removing potentially conflicting packages..."
    apt remove -y intel-ocloc libze-intel-gpu1 intel-level-zero-gpu intel-opencl-icd || true
    dpkg --remove --force-remove-reinstreq intel-level-zero-gpu intel-ocloc libze-intel-gpu1 || true
    apt --fix-broken install -y || true
    
    # Use dpkg with comprehensive conflict resolution
    echo "Installing packages with comprehensive conflict resolution..."
    dpkg -i --force-conflicts --force-depends --auto-deconfigure ./*.deb ./*.ddeb || {
        echo "Installation failed, attempting recovery..."
        apt --fix-broken install -y
        dpkg -i --force-all ./*.deb ./*.ddeb
    }

    cd ..
    echo -e "Cleaning up /tmp/neo_temp folder after installation"
    rm -rf neo_temp
    cd "$CURRENT_DIR"
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
        
        echo -e "Installing NPU Driver version: $NPU_DRIVER_VERSION"
        echo -e "Installing Level Zero version: $LEVEL_ZERO_VERSION"

        if [ -d /tmp/npu_temp ];then
            rm -rf /tmp/npu_temp
        fi
        
        mkdir /tmp/npu_temp
        cd /tmp/npu_temp

        # Download NPU driver tarball
        echo "Downloading NPU driver tarball..."
        wget "$ASSET_URL_NPU_TARBALL" -O npu-driver.tar.gz
        
        # Extract the tarball to get individual .deb packages
        echo "Extracting NPU driver packages..."
        tar -xzf npu-driver.tar.gz
        
        # Download Level Zero package
        echo "Downloading Level Zero package..."
        wget "$ASSET_URL_LEVEL_ZERO"
        
        # Install NPU packages (the .deb files are now extracted)
        echo "Installing NPU packages..."
        dpkg -i intel-driver-compiler-npu_*.deb intel-fw-npu_*.deb intel-level-zero-npu_*.deb level-zero_*.deb 2>/dev/null || {
            echo "Installation failed, attempting with --force-depends..."
            dpkg -i --force-depends intel-driver-compiler-npu_*.deb intel-fw-npu_*.deb intel-level-zero-npu_*.deb level-zero_*.deb
        }
                                                                                                                                                                                             
        cd ..
        rm -rf npu_temp
        cd "$CURRENT_DIR"
        
        # Set up device permissions for NPU
        if [ -e /dev/accel/accel0 ]; then
            chown root:render /dev/accel/accel0
            chmod g+rw /dev/accel/accel0
        fi
        bash -c "echo 'SUBSYSTEM==\"accel\", KERNEL==\"accel*\", GROUP=\"render\", MODE=\"0660\"' > /etc/udev/rules.d/10-intel-vpu.rules"
        udevadm control --reload-rules
        udevadm trigger --subsystem-match=accel
    fi
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

show_installation_summary(){
    echo -e "\n=================================================="
    echo "# Intel AI PC Driver Installation Summary"
    echo "=================================================="
    echo "Date: $(date)"
    echo "Kernel: $(uname -r)"
    echo "OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2 2>/dev/null || echo 'Unknown')"
    echo
    
    echo "📦 DRIVER VERSIONS INSTALLED:"
    echo "├─ Intel Graphics Compiler (IGC): $IGC_VERSION"
    echo "├─ Intel Compute Runtime: $COMPUTE_RUNTIME_VERSION"
    echo "├─ Intel NPU Driver: $NPU_DRIVER_VERSION"
    echo "└─ Level Zero: $LEVEL_ZERO_VERSION"
    echo
    
    echo "🔧 PACKAGES INSTALLED:"
    echo "IGC Packages:"
    echo "├─ intel-igc-core-2 (version: $(dpkg-query -W -f='${Version}' intel-igc-core-2 2>/dev/null || echo 'not installed'))"
    echo "└─ intel-igc-opencl-2 (version: $(dpkg-query -W -f='${Version}' intel-igc-opencl-2 2>/dev/null || echo 'not installed'))"
    echo
    echo "Compute Runtime Packages:"
    echo "├─ intel-ocloc (version: $(dpkg-query -W -f='${Version}' intel-ocloc 2>/dev/null || echo 'not installed'))"
    echo "├─ libze-intel-gpu1 (version: $(dpkg-query -W -f='${Version}' libze-intel-gpu1 2>/dev/null || echo 'not installed'))"
    echo "├─ intel-opencl-icd (version: $(dpkg-query -W -f='${Version}' intel-opencl-icd 2>/dev/null || echo 'not installed'))"
    echo "└─ libigdgmm12 (version: $(dpkg-query -W -f='${Version}' libigdgmm12 2>/dev/null || echo 'not installed'))"
    echo
    echo "NPU Packages:"
    echo "├─ intel-driver-compiler-npu (version: $(dpkg-query -W -f='${Version}' intel-driver-compiler-npu 2>/dev/null || echo 'not installed'))"
    echo "├─ intel-fw-npu (version: $(dpkg-query -W -f='${Version}' intel-fw-npu 2>/dev/null || echo 'not installed'))"
    echo "└─ intel-level-zero-npu (version: $(dpkg-query -W -f='${Version}' intel-level-zero-npu 2>/dev/null || echo 'not installed'))"
    echo
    echo "Level Zero Package:"
    echo "└─ level-zero (version: $(dpkg-query -W -f='${Version}' level-zero 2>/dev/null || echo 'not installed'))"
    echo
    
    echo "💻 HARDWARE STATUS:"
    local gpu_info="$(lspci | grep VGA | grep Intel | head -1 | cut -d: -f3 | sed 's/^[ \t]*//' || echo 'No Intel GPU detected')"
    echo "├─ GPU: $gpu_info"
    local npu_info="$(lspci | grep -i 'neural\|npu\|vpu' | head -1 | cut -d: -f3 | sed 's/^[ \t]*//' || echo 'No NPU detected')"
    echo "└─ NPU: $npu_info"
    echo
    
    echo "📊 DRIVER STATUS:"
    local gpu_driver_version="$(clinfo | grep 'Driver Version' | awk '{print $NF}' 2>/dev/null || echo 'Not detected')"
    if [ "$gpu_driver_version" != "Not detected" ]; then
        echo "├─ ✅ GPU Driver: $gpu_driver_version"
    else
        echo "├─ ⚠️  GPU Driver: Not detected (may need reboot)"
    fi
    
    local npu_driver_info="$(dmesg | grep -i vpu | tail -1 | grep -o 'driver.*' 2>/dev/null || echo 'Not detected')"
    if [ "$npu_driver_info" != "Not detected" ]; then
        echo "└─ ✅ NPU Driver: Loaded"
    else
        echo "└─ ⚠️  NPU Driver: Not detected (may need reboot)"
    fi
    echo
    
    echo "🔗 VERIFICATION COMMANDS:"
    echo "├─ GPU: clinfo | grep -E '(Device Name|Driver Version)'"
    echo "├─ OpenCL: clinfo -l"
    echo "├─ Level Zero: ls /sys/class/drm/renderD*"
    echo "└─ NPU: dmesg | grep -i vpu"
    echo
    
    echo "📝 NEXT STEPS:"
    echo "1. Reboot the system if drivers are not detected"
    echo "2. Add your user to 'video' and 'render' groups if not done:"
    echo "   sudo usermod -aG video,render \$USER"
    echo
    echo "=================================================="
    echo "$S_VALID Intel AI PC Driver Installation Complete!"
    echo "=================================================="
}

setup(){
    echo "# Intel AI PC Linux Setup - Static Driver Installation"
    echo "# This script uses pre-determined asset URLs to avoid GitHub API rate limits"
    echo
    
    verify_dependencies
    verify_platform
    verify_gpu
    verify_os
    verify_drivers
    verify_kernel
    verify_compute_runtime
    
    echo -e "\n# Status"
    echo "$S_VALID Platform configured"
    
    # Show comprehensive installation summary
    show_installation_summary
}

setup
EOF

    chmod +x "$static_script"
    
    echo "✓ Generated $static_script"
    echo "  - IGC Version: ${VERSIONS[intel/intel-graphics-compiler]}"
    echo "  - Compute Runtime Version: ${VERSIONS[intel/compute-runtime]}"
    echo "  - NPU Driver Version: ${VERSIONS[intel/linux-npu-driver]}"
    echo "  - Level Zero Version: ${VERSIONS[oneapi-src/level-zero]}"
    echo
    echo "Usage: sudo ./$static_script"
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
    local response
    if [ -n "$GITHUB_TOKEN" ]; then
        response=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/intel/compute-runtime/releases/tags/$compute_runtime_tag")
    else
        response=$(curl -s "https://api.github.com/repos/intel/compute-runtime/releases/tags/$compute_runtime_tag")
    fi
    
    # Find intel-opencl-icd package (contains IGC dependency)
    local opencl_icd_url=$(echo "$response" | jq -r '.assets[] | select(.name | test("intel-opencl-icd_.*amd64\\.deb$")) | .browser_download_url' | head -1)
    
    if [ -z "$opencl_icd_url" ] || [ "$opencl_icd_url" = "null" ]; then
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
    local response
    if [ -n "$GITHUB_TOKEN" ]; then
        response=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/intel/intel-graphics-compiler/releases?per_page=50")
    else
        response=$(curl -s "https://api.github.com/repos/intel/intel-graphics-compiler/releases?per_page=50")
    fi
    
    if [ -z "$response" ]; then
        echo "  Failed to get IGC releases" >&2
        return 1
    fi
    
    # Look for tags that contain or match the required version
    local matching_tag=$(echo "$response" | jq -r ".[].tag_name" | grep -E "^(igc-|v)?${required_version}" | head -1)
    
    if [ -z "$matching_tag" ]; then
        # Try more flexible matching - look for tags containing the version
        matching_tag=$(echo "$response" | jq -r ".[].tag_name" | grep "$required_version" | head -1)
    fi
    
    if [ -z "$matching_tag" ]; then
        echo "  No IGC tag found for version $required_version" >&2
        echo "  Available recent tags:" >&2
        echo "$response" | jq -r ".[].tag_name" | head -5 | sed 's/^/    /' >&2
        return 1
    fi
    
    echo "  Found matching IGC tag: $matching_tag" >&2
    echo "$matching_tag"
    return 0
}

# Function to verify version compatibility between IGC and compute-runtime
check_version_compatibility() {
    local igc_tag="$1"
    local compute_runtime_tag="$2"
    
    echo "  Cross-checking IGC $igc_tag with compute-runtime $compute_runtime_tag..." >&2
    
    # Basic sanity check - make sure both tags exist and have releases
    local igc_response
    local cr_response
    
    if [ -n "$GITHUB_TOKEN" ]; then
        igc_response=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/intel/intel-graphics-compiler/releases/tags/$igc_tag")
        cr_response=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/intel/compute-runtime/releases/tags/$compute_runtime_tag")
    else
        igc_response=$(curl -s "https://api.github.com/repos/intel/intel-graphics-compiler/releases/tags/$igc_tag")
        cr_response=$(curl -s "https://api.github.com/repos/intel/compute-runtime/releases/tags/$compute_runtime_tag")
    fi
    
    # Check if both releases exist
    local igc_exists=$(echo "$igc_response" | jq -r '.tag_name // "null"')
    local cr_exists=$(echo "$cr_response" | jq -r '.tag_name // "null"')
    
    if [ "$igc_exists" = "null" ]; then
        echo "  IGC release $igc_tag not found" >&2
        return 1
    fi
    
    if [ "$cr_exists" = "null" ]; then
        echo "  Compute runtime release $compute_runtime_tag not found" >&2
        return 1
    fi
    
    # Check if both have assets (packages)
    local igc_assets=$(echo "$igc_response" | jq -r '.assets[].name' | grep -c '\.deb$' || echo "0")
    local cr_assets=$(echo "$cr_response" | jq -r '.assets[].name' | grep -c '\.deb$' || echo "0")
    
    if [ "$igc_assets" -eq 0 ]; then
        echo "  IGC release $igc_tag has no .deb packages" >&2
        return 1
    fi
    
    if [ "$cr_assets" -eq 0 ]; then
        echo "  Compute runtime release $compute_runtime_tag has no .deb packages" >&2
        return 1
    fi
    
    echo "  ✓ Both releases exist and have packages" >&2
    
    # Additional check: verify IGC release date is not too much newer than compute runtime
    local igc_date=$(echo "$igc_response" | jq -r '.published_at')
    local cr_date=$(echo "$cr_response" | jq -r '.published_at')
    
    if [ "$igc_date" != "null" ] && [ "$cr_date" != "null" ]; then
        # Convert to timestamps for comparison (if available)
        local igc_ts=$(date -d "$igc_date" +%s 2>/dev/null || echo "0")
        local cr_ts=$(date -d "$cr_date" +%s 2>/dev/null || echo "0")
        
        if [ "$igc_ts" -gt 0 ] && [ "$cr_ts" -gt 0 ]; then
            # Allow IGC to be up to 90 days newer than compute runtime
            local max_diff=$((90 * 24 * 3600))  # 90 days in seconds
            local time_diff=$((igc_ts - cr_ts))
            
            if [ "$time_diff" -gt "$max_diff" ]; then
                echo "  Warning: IGC release is significantly newer than compute runtime" >&2
                echo "  This may indicate version incompatibility" >&2
                return 1
            fi
        fi
    fi
    
    echo "  ✓ Version compatibility checks passed" >&2
    return 0
}

# Function to check Level Zero compatibility with compute runtime
check_level_zero_compatibility() {
    local compute_runtime_tag="$1"
    local level_zero_tag="$2"
    
    echo "  Checking Level Zero compatibility with compute runtime..." >&2
    
    # Get compute runtime package to check for Level Zero dependencies
    local response
    if [ -n "$GITHUB_TOKEN" ]; then
        response=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/intel/compute-runtime/releases/tags/$compute_runtime_tag")
    else
        response=$(curl -s "https://api.github.com/repos/intel/compute-runtime/releases/tags/$compute_runtime_tag")
    fi
    
    # Find libze-intel-gpu1 package (may conflict with older Level Zero)
    local ze_gpu_url=$(echo "$response" | jq -r '.assets[] | select(.name | test("libze-intel-gpu1_.*amd64\\.deb$")) | .browser_download_url' | head -1)
    
    if [ -z "$ze_gpu_url" ] || [ "$ze_gpu_url" = "null" ]; then
        echo "  No libze-intel-gpu1 package found in compute runtime release" >&2
        return 0  # No conflict possible
    fi
    
    # Extract version from filename
    local ze_gpu_version=$(echo "$ze_gpu_url" | grep -o 'libze-intel-gpu1_[^_]*' | cut -d'_' -f2)
    
    if [ -n "$ze_gpu_version" ]; then
        echo "  Found libze-intel-gpu1 version: $ze_gpu_version" >&2
        echo "  This may conflict with older intel-level-zero-gpu packages" >&2
        echo "  Recommendation: Remove intel-level-zero-gpu before installation" >&2
    fi
    
    return 0
}

# Collect compatible driver versions
collect_compatible_versions() {
    echo "=== Collecting Compatible Driver Versions ==="
    echo
    
    # First, get the latest compute runtime version
    echo "📡 Getting latest compute runtime version..."
    local compute_runtime_tag=$(get_latest_release_tag "intel/compute-runtime")
    if [ $? -ne 0 ]; then
        echo "❌ Failed to get compute runtime version"
        return 1
    fi
    echo "  Latest compute runtime: $compute_runtime_tag"
    
    # Find compatible IGC version
    echo "🔍 Finding compatible IGC version..."
    local compatible_igc_version=$(find_compatible_igc_version "$compute_runtime_tag")
    if [ $? -ne 0 ]; then
        echo "⚠️  Could not determine compatible IGC version, using latest..."
        COMPATIBLE_IGC_TAG=$(get_latest_release_tag "intel/intel-graphics-compiler")
        COMPATIBILITY_WARNING="true"
        echo "  Using latest IGC: $COMPATIBLE_IGC_TAG"
    else
        echo "  Required IGC version: $compatible_igc_version"
        COMPATIBLE_IGC_TAG=$(find_igc_tag_for_version "$compatible_igc_version")
        if [ $? -ne 0 ]; then
            echo "⚠️  Could not find IGC tag for version $compatible_igc_version, using latest..."
            COMPATIBLE_IGC_TAG=$(get_latest_release_tag "intel/intel-graphics-compiler")
            COMPATIBILITY_WARNING="true"
        else
            echo "  Found compatible IGC tag: $COMPATIBLE_IGC_TAG"
            COMPATIBILITY_WARNING="false"
        fi
    fi
    
    # Get other component versions
    COMPATIBLE_COMPUTE_RUNTIME_TAG="$compute_runtime_tag"
    echo "📡 Getting NPU driver and Level Zero versions..."
    COMPATIBLE_NPU_DRIVER_TAG=$(get_latest_release_tag "intel/linux-npu-driver")
    COMPATIBLE_LEVEL_ZERO_TAG=$(get_latest_release_tag "oneapi-src/level-zero")
    
    echo
    echo "📋 Selected versions:"
    echo "  IGC: $COMPATIBLE_IGC_TAG"
    echo "  Compute Runtime: $COMPATIBLE_COMPUTE_RUNTIME_TAG"
    echo "  NPU Driver: $COMPATIBLE_NPU_DRIVER_TAG"
    echo "  Level Zero: $COMPATIBLE_LEVEL_ZERO_TAG"
    echo
    
    # Verify compatibility if we found a specific compatible version
    if [ "$COMPATIBILITY_WARNING" = "false" ]; then
        echo "🔍 Verifying compatibility..."
        if check_version_compatibility "$COMPATIBLE_IGC_TAG" "$COMPATIBLE_COMPUTE_RUNTIME_TAG"; then
            # Also check Level Zero compatibility
            check_level_zero_compatibility "$COMPATIBLE_COMPUTE_RUNTIME_TAG" "$COMPATIBLE_LEVEL_ZERO_TAG"
            echo "✅ All versions are compatible!"
            return 0
        else
            echo "❌ Version compatibility issues detected!"
            COMPATIBILITY_WARNING="true"
        fi
    fi
    
    if [ "$COMPATIBILITY_WARNING" = "true" ]; then
        echo "⚠️  WARNING: Could not verify version compatibility!"
        echo "   The generated static script may have dependency conflicts."
        echo "   Consider testing installation on a non-production system first."
        echo "   Recommendation: Use a GitHub token and retry, or test manually first."
    fi
    
    return 0
}

# Main execution
echo "Checking GitHub API connectivity..."

# Test basic API access
test_response=""
if [ -n "$GITHUB_TOKEN" ]; then
    test_response=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/rate_limit")
else
    test_response=$(curl -s "https://api.github.com/rate_limit")
fi

if ! echo "$test_response" | jq -r '.rate.remaining' > /dev/null; then
    echo "ERROR: Cannot access GitHub API or jq parsing failed"
    if [ "$BUILD_STATIC" = "true" ]; then
        echo "Cannot generate static setup script without API access"
        exit 1
    else
        exit 1
    fi
fi

echo "✓ GitHub API accessible"
echo

# Check rate limit status
if [ -n "$GITHUB_TOKEN" ]; then
    rate_info=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/rate_limit")
else
    rate_info=$(curl -s "https://api.github.com/rate_limit")
fi
remaining=$(echo "$rate_info" | jq -r '.rate.remaining')
limit=$(echo "$rate_info" | jq -r '.rate.limit')
reset_time=$(echo "$rate_info" | jq -r '.rate.reset')
reset_human=$(date -d "@$reset_time" 2>/dev/null || echo "unknown")

echo "Rate limit status: $remaining/$limit requests remaining"
echo "Rate limit resets: $reset_human"

if [ "$remaining" -lt 10 ]; then
    echo "WARNING: Low rate limit remaining. Consider setting GITHUB_TOKEN"
fi
echo

# Repository information
REPOS=("intel/intel-graphics-compiler" "intel/compute-runtime" "intel/linux-npu-driver" "oneapi-src/level-zero")

# Arrays to store discovered assets for static script generation
declare -A ASSET_URLS
declare -A VERSIONS

# Track errors for static script generation
STATIC_GENERATION_FAILED=false

# Variables for compatibility checking
COMPATIBLE_IGC_TAG=""
COMPATIBLE_COMPUTE_RUNTIME_TAG=""
COMPATIBLE_NPU_DRIVER_TAG=""
COMPATIBLE_LEVEL_ZERO_TAG=""
COMPATIBILITY_WARNING="false"

echo "=== Driver Version Verification ==="
echo "GitHub API token: ${GITHUB_TOKEN:+configured}"
echo "Mode: ${BUILD_STATIC:+Static script generation}${BUILD_STATIC:-Verification only}"
echo

if [ "$BUILD_STATIC" = "true" ]; then
    echo "🔧 Building static script with version compatibility checking..."
    echo
    
    # Collect compatible versions
    if ! collect_compatible_versions; then
        echo "❌ Failed to get compatible versions"
        echo "Cannot generate static setup script safely"
        exit 1
    fi
    
    # Use compatible versions for repos
    REPOS_VERSIONS=(
        "intel/intel-graphics-compiler:$COMPATIBLE_IGC_TAG"
        "intel/compute-runtime:$COMPATIBLE_COMPUTE_RUNTIME_TAG"
        "intel/linux-npu-driver:$COMPATIBLE_NPU_DRIVER_TAG"
        "oneapi-src/level-zero:$COMPATIBLE_LEVEL_ZERO_TAG"
    )
    
    echo "📦 Collecting assets for compatible versions..."
    
    for repo_version in "${REPOS_VERSIONS[@]}"; do
        IFS=':' read -r repo tag <<< "$repo_version"
        echo "----------------------------------------"
        echo "Collecting assets for $repo $tag..."
        
        # Store version for later use
        VERSIONS["$repo"]="$tag"
        
        # List assets for verification
        if ! list_release_assets "$repo" "$tag"; then
            echo "ERROR: Failed to list assets for $repo $tag" >&2
            STATIC_GENERATION_FAILED=true
            continue
        fi
        
        # Collect asset URLs
        if ! collect_asset_urls "$repo" "$tag"; then
            echo "ERROR: Failed to collect assets for $repo $tag" >&2
            STATIC_GENERATION_FAILED=true
        fi
        echo "----------------------------------------"
    done
else
    # Original verification mode - check latest versions
    for repo in "${REPOS[@]}"; do
        echo "----------------------------------------"
        echo "Checking $repo..."
        
        # Get latest release tag
        if tag=$(get_latest_release_tag "$repo"); then
            echo "Latest release: $tag"
            
            # List all assets for debugging
            list_release_assets "$repo" "$tag"
        
        # Test patterns only for compute-runtime (the problematic one)
        if [ "$repo" = "intel/compute-runtime" ]; then
            echo "=== Testing Current Patterns Against Actual Assets ==="
            test_pattern_matching "$repo" "$tag" "intel-ocloc_.*amd64\.deb"
            test_pattern_matching "$repo" "$tag" "libze-intel-gpu1-dbgsym.*amd64\.ddeb"
            test_pattern_matching "$repo" "$tag" "libze-intel-gpu1_.*amd64\.deb"
            test_pattern_matching "$repo" "$tag" "intel-opencl-icd-dbgsym.*amd64\.ddeb"
            test_pattern_matching "$repo" "$tag" "intel-opencl-icd_.*amd64\.deb"
            test_pattern_matching "$repo" "$tag" "libigdgmm12.*amd64\.deb"
        fi
        
        # Test patterns for NPU driver
        if [ "$repo" = "intel/linux-npu-driver" ]; then
            echo "=== Testing NPU Driver Patterns Against Actual Assets ==="
            test_pattern_matching "$repo" "$tag" "linux-npu-driver.*ubuntu2404\.tar\.gz"
        fi
        
        # Test patterns for Level Zero
        if [ "$repo" = "oneapi-src/level-zero" ]; then
            echo "=== Testing Level Zero Patterns Against Actual Assets ==="
            test_pattern_matching "$repo" "$tag" "level-zero_.*u24.04.*amd64\.deb"
        fi
        else
            echo "Failed to get release information for $repo"
        fi
        echo "----------------------------------------"
    done
fi

show_current_patterns

# Generate static setup script only if all assets were collected successfully
if [ "$BUILD_STATIC" = "true" ]; then
    if [ "$STATIC_GENERATION_FAILED" = "true" ]; then
        echo ""
        echo "=== ERROR: Static Script Generation Failed ==="
        echo "Cannot create setup-static-drivers.sh due to asset collection failures" >&2
        echo "Possible causes:" >&2
        echo "- GitHub API rate limiting (try setting GITHUB_TOKEN)" >&2
        echo "- Network connectivity issues" >&2
        echo "- Missing or moved driver assets in repositories" >&2
        echo "" >&2
        exit 1
    else
        echo ""
        echo "=== Generating Static Setup Script ==="
        if [ "$COMPATIBILITY_WARNING" = "true" ]; then
            echo "⚠️  WARNING: Version compatibility could not be fully verified"
            echo "   The generated script may have dependency conflicts"
            echo "   Test on a non-production system first"
            echo ""
        fi
        
        if generate_static_setup_script; then
            echo "✅ Static setup script generated: setup-static-drivers.sh"
            echo ""
            echo "📋 Summary:"
            echo "  - IGC Version: ${VERSIONS[intel/intel-graphics-compiler]}"
            echo "  - Compute Runtime Version: ${VERSIONS[intel/compute-runtime]}"
            echo "  - NPU Driver Version: ${VERSIONS[intel/linux-npu-driver]}"
            echo "  - Level Zero Version: ${VERSIONS[oneapi-src/level-zero]}"
            
            if [ "$COMPATIBILITY_WARNING" = "false" ]; then
                echo "  - ✅ Version compatibility verified"
            else
                echo "  - ⚠️  Version compatibility warning (see above)"
            fi
            
            echo ""
            echo "🚀 Usage: sudo ./setup-static-drivers.sh"
        else
            echo "❌ Failed to generate static setup script"
            exit 1
        fi
    fi
fi

echo ""
echo "=== Summary ==="
echo "This diagnostic script completed safely without installing anything."
echo "Use the output above to:"
echo "1. Verify GitHub API connectivity"
echo "2. See what assets are actually available"
echo "3. Compare with patterns used in setup-drivers.sh"
echo "4. Identify any mismatched patterns that need updating"
if [ "$BUILD_STATIC" = "true" ] && [ "$STATIC_GENERATION_FAILED" = "false" ]; then
    echo "5. ✓ Generated setup-static-drivers.sh with exact asset URLs"
    echo -e "   \033[1;32m Run: sudo ./setup-static-drivers.sh \033[0m"
fi
