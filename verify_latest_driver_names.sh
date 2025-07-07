#!/bin/bash

# Verify Latest Driver Names - No installation, just inspection
# This script safely queries GitHub API to show available driver assets without downloading anything
# Use --build-static flag to generate setup-static-drivers.sh with exact filenames

set -e

# Parse command line arguments
BUILD_STATIC=false
if [ "$1" = "--build-static" ]; then
    BUILD_STATIC=true
    echo "=== Building Static Driver Setup Script ==="
    echo "Will generate setup-static-drivers.sh with exact filenames"
    echo
fi

echo "=== Latest Driver Names Verification ==="
echo "This script safely checks what driver assets are available from GitHub releases"
echo "No files will be downloaded or installed"
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
        response=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/$repo/releases/latest")
    else
        response=$(curl -s "https://api.github.com/repos/$repo/releases/latest")
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
    echo "  - libze-intel-gpu1-dbgsym.*amd64.ddeb"
    echo "  - libze-intel-gpu1_.*amd64.deb"
    echo "  - intel-opencl-icd-dbgsym.*amd64.ddeb"
    echo "  - intel-opencl-icd_.*amd64.deb"
    echo "  - libigdgmm12.*amd64.deb"
    echo "  - .*\.sum (checksum file)"
    echo
    echo "Intel NPU Driver patterns:"
    echo "  - intel-driver-compiler-npu.*ubuntu24.04.*amd64.deb"
    echo "  - intel-fw-npu.*ubuntu24.04.*amd64.deb"
    echo "  - intel-level-zero-npu.*ubuntu24.04.*amd64.deb"
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
    
    # Store version
    VERSIONS["$repo"]="$tag"
    
    # Extract download URLs based on repo
    case "$repo" in
        "intel/intel-graphics-compiler")
            ASSET_URLS["igc-core"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("intel-igc-core.*amd64\\.deb")) | .browser_download_url' | head -1)
            ASSET_URLS["igc-opencl"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("intel-igc-opencl.*amd64\\.deb")) | .browser_download_url' | head -1)
            ;;
        "intel/compute-runtime")
            ASSET_URLS["ocloc"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("intel-ocloc_.*amd64\\.deb")) | .browser_download_url' | head -1)
            ASSET_URLS["ze-gpu-dbgsym"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("libze-intel-gpu1-dbgsym.*amd64\\.ddeb")) | .browser_download_url' | head -1)
            ASSET_URLS["ze-gpu"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("libze-intel-gpu1_.*amd64\\.deb")) | .browser_download_url' | head -1)
            ASSET_URLS["opencl-icd-dbgsym"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("intel-opencl-icd-dbgsym.*amd64\\.ddeb")) | .browser_download_url' | head -1)
            ASSET_URLS["opencl-icd"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("intel-opencl-icd_.*amd64\\.deb")) | .browser_download_url' | head -1)
            ASSET_URLS["igdgmm"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("libigdgmm12.*amd64\\.deb")) | .browser_download_url' | head -1)
            ASSET_URLS["checksum"]=$(echo "$response" | jq -r '.assets[] | select(.name | test(".*\\.sum")) | .browser_download_url' | head -1)
            ;;
        "intel/linux-npu-driver")
            ASSET_URLS["npu-compiler"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("intel-driver-compiler-npu.*ubuntu24\\.04.*amd64\\.deb")) | .browser_download_url' | head -1)
            ASSET_URLS["npu-fw"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("intel-fw-npu.*ubuntu24\\.04.*amd64\\.deb")) | .browser_download_url' | head -1)
            ASSET_URLS["npu-level-zero"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("intel-level-zero-npu.*ubuntu24\\.04.*amd64\\.deb")) | .browser_download_url' | head -1)
            ;;
        "oneapi-src/level-zero")
            ASSET_URLS["level-zero"]=$(echo "$response" | jq -r '.assets[] | select(.name | test("level-zero_.*u24\\.04.*amd64\\.deb")) | .browser_download_url' | head -1)
            ;;
    esac
}

# Function to generate static setup script
generate_static_setup_script() {
    if [ "$BUILD_STATIC" = "false" ]; then
        return 0
    fi
    
    echo "=== Generating setup-static-drivers.sh ==="
    
    local static_script="setup-static-drivers.sh"
    
    # Create the static setup script
    cat > "$static_script" << 'EOF'
#!/bin/bash

# Copyright (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
# 
# Static Driver Setup Script - Generated by verify_latest_driver_names.sh
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

    # Add the static asset URLs and versions
    echo "# Static asset URLs and versions (generated $(date))" >> "$static_script"
    echo "IGC_VERSION=\"${VERSIONS[intel/intel-graphics-compiler]}\"" >> "$static_script"
    echo "COMPUTE_RUNTIME_VERSION=\"${VERSIONS[intel/compute-runtime]}\"" >> "$static_script"
    echo "NPU_DRIVER_VERSION=\"${VERSIONS[intel/linux-npu-driver]}\"" >> "$static_script"
    echo "LEVEL_ZERO_VERSION=\"${VERSIONS[oneapi-src/level-zero]}\"" >> "$static_script"
    echo >> "$static_script"
    
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
    wget "$ASSET_URL_IGC_CORE"
    wget "$ASSET_URL_IGC_OPENCL"
    
    # Download Intel Compute Runtime packages
    wget "$ASSET_URL_OCLOC"
    wget "$ASSET_URL_ZE_GPU_DBGSYM"
    wget "$ASSET_URL_ZE_GPU"
    wget "$ASSET_URL_OPENCL_ICD_DBGSYM"
    wget "$ASSET_URL_OPENCL_ICD"
    wget "$ASSET_URL_IGDGMM"
    
    echo -e "Verify sha256 sums for packages (if available)"
    if [ -n "$ASSET_URL_CHECKSUM" ]; then
        wget "$ASSET_URL_CHECKSUM"
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

        # Download NPU driver packages
        wget "$ASSET_URL_NPU_COMPILER"
        wget "$ASSET_URL_NPU_FW"
        wget "$ASSET_URL_NPU_LEVEL_ZERO"
        
        # Download Level Zero package
        wget "$ASSET_URL_LEVEL_ZERO"
        
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
    exit 1
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
repos=("intel/intel-graphics-compiler" "intel/compute-runtime" "intel/linux-npu-driver" "oneapi-src/level-zero")

# Arrays to store discovered assets for static script generation
declare -A ASSET_URLS
declare -A VERSIONS

for repo in "${repos[@]}"; do
    echo "----------------------------------------"
    
    # Get latest release tag
    if tag=$(get_latest_release_tag "$repo"); then
        # List all assets
        list_release_assets "$repo" "$tag"
        
        # Collect asset URLs for static script generation
        collect_asset_urls "$repo" "$tag"
        
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
            test_pattern_matching "$repo" "$tag" "intel-driver-compiler-npu.*ubuntu24.04.*amd64\.deb"
            test_pattern_matching "$repo" "$tag" "intel-fw-npu.*ubuntu24.04.*amd64\.deb"
            test_pattern_matching "$repo" "$tag" "intel-level-zero-npu.*ubuntu24.04.*amd64\.deb"
        fi
        
        # Test patterns for Level Zero
        if [ "$repo" = "oneapi-src/level-zero" ]; then
            echo "=== Testing Level Zero Patterns Against Actual Assets ==="
            test_pattern_matching "$repo" "$tag" "level-zero_.*u24.04.*amd64\.deb"
        fi
        
        # Collect asset URLs for static script generation
        collect_asset_urls "$repo" "$tag"
    else
        echo "Failed to get release information for $repo"
    fi
    echo "----------------------------------------"
done

show_current_patterns

# Generate static setup script if requested
generate_static_setup_script

echo "=== Summary ==="
echo "This diagnostic script completed safely without installing anything."
echo "Use the output above to:"
echo "1. Verify GitHub API connectivity"
echo "2. See what assets are actually available"
echo "3. Compare with patterns used in setup-drivers.sh"
echo "4. Identify any mismatched patterns that need updating"
if [ "$BUILD_STATIC" = "true" ]; then
    echo "5. ✓ Generated setup-static-drivers.sh with exact asset URLs"
    echo "   Run: sudo ./setup-static-drivers.sh"
fi
