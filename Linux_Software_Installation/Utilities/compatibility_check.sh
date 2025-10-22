#!/bin/bash

# Intel Driver Version Compatibility Checker
# This script checks for version compatibility between Intel Graphics Compiler (IGC)
# and Intel Compute Runtime packages to prevent dependency conflicts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check GitHub token status
if [ -n "$GITHUB_TOKEN" ]; then
    echo_info "GitHub token configured (${#GITHUB_TOKEN} characters)"
    AUTH_HEADER="Authorization: token $GITHUB_TOKEN"
else
    echo_warn "No GitHub token found - may hit rate limits"
    echo_warn "Set GITHUB_TOKEN for better reliability"
    AUTH_HEADER=""
fi

# Function to get latest release tag
get_latest_release_tag() {
    local repo="$1"
    echo_debug "Getting latest release for $repo..."
    
    local response
    if [ -n "$GITHUB_TOKEN" ]; then
        response=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null)
    else
        response=$(curl -s "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null)
    fi
    
    # Check if curl failed or returned empty response
    if [ -z "$response" ]; then
        echo_error "Failed to connect to GitHub API for $repo"
        return 1
    fi
    
    # Check if response is valid JSON and contains tag_name
    if ! echo "$response" | jq -e '.tag_name' >/dev/null 2>&1; then
        echo_error "Invalid response from GitHub API for $repo"
        return 1
    fi
    
    local tag=$(echo "$response" | jq -r '.tag_name')
    if [ "$tag" = "null" ] || [ -z "$tag" ]; then
        echo_error "Could not extract tag_name from response for $repo"
        return 1
    fi
    
    echo "$tag"
    return 0
}

# Function to find compatible IGC version for compute runtime
find_compatible_igc_version() {
    local compute_runtime_tag="$1"
    echo_info "Finding compatible IGC version for compute runtime $compute_runtime_tag..."
    
    # Get the compute runtime release assets
    local response
    if [ -n "$GITHUB_TOKEN" ]; then
        response=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/intel/compute-runtime/releases/tags/$compute_runtime_tag")
    else
        response=$(curl -s "https://api.github.com/repos/intel/compute-runtime/releases/tags/$compute_runtime_tag")
    fi
    
    # Look for intel-opencl-icd package
    local opencl_icd_url=$(echo "$response" | jq -r '.assets[] | select(.name | contains("intel-opencl-icd_")) | .browser_download_url' | head -1)
    
    if [ -n "$opencl_icd_url" ] && [ "$opencl_icd_url" != "null" ]; then
        echo_debug "Downloading intel-opencl-icd package to check dependencies..."
        
        # Download the package temporarily
        local temp_dir=$(mktemp -d)
        cd "$temp_dir"
        
        if wget -q "$opencl_icd_url" -O opencl-icd.deb 2>/dev/null; then
            # Extract control information
            local deps_info=$(dpkg-deb --info opencl-icd.deb 2>/dev/null | grep -A 20 "Depends:" || echo "No dependencies found")
            
            # Look for IGC dependency
            local igc_version=$(echo "$deps_info" | grep -o "intel-igc-opencl-2 (= [^)]*)" | sed 's/intel-igc-opencl-2 (= \([^)]*\))/\1/' | head -1)
            
            cd - > /dev/null
            rm -rf "$temp_dir"
            
            if [ -n "$igc_version" ]; then
                echo_info "Found required IGC version: $igc_version"
                echo "$igc_version"
                return 0
            fi
        fi
        
        cd - > /dev/null
        rm -rf "$temp_dir"
    fi
    
    echo_error "Could not determine compatible IGC version"
    return 1
}

# Function to find IGC release tag for a specific version
find_igc_tag_for_version() {
    local target_version="$1"
    echo_debug "Searching for IGC tag matching version $target_version..."
    
    # Get IGC releases to find matching tag
    local response
    if [ -n "$GITHUB_TOKEN" ]; then
        response=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/intel/intel-graphics-compiler/releases?per_page=30")
    else
        response=$(curl -s "https://api.github.com/repos/intel/intel-graphics-compiler/releases?per_page=30")
    fi
    
    # Look through releases for matching version
    local matching_tag=$(echo "$response" | jq -r --arg version "$target_version" '.[] | select(.assets[].name | contains($version)) | .tag_name' | head -1)
    
    if [ -n "$matching_tag" ] && [ "$matching_tag" != "null" ]; then
        echo_info "Found matching IGC tag: $matching_tag"
        echo "$matching_tag"
        return 0
    fi
    
    echo_warn "Could not find IGC tag for version $target_version"
    
    # Try alternative approach - look for tags that might contain the version
    local alternative_tag=$(echo "$response" | jq -r '.[] | .tag_name' | grep -E "v?${target_version}" | head -1)
    
    if [ -n "$alternative_tag" ]; then
        echo_info "Found alternative IGC tag: $alternative_tag"
        echo "$alternative_tag"
        return 0
    fi
    
    return 1
}

# Function to check version compatibility
check_version_compatibility() {
    local igc_tag="$1"
    local compute_runtime_tag="$2"
    
    echo_info "Checking compatibility between IGC $igc_tag and Compute Runtime $compute_runtime_tag..."
    
    # Create temp directory
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Download a sample IGC package to check version
    local igc_response
    if [ -n "$GITHUB_TOKEN" ]; then
        igc_response=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/intel/intel-graphics-compiler/releases/tags/$igc_tag")
    else
        igc_response=$(curl -s "https://api.github.com/repos/intel/intel-graphics-compiler/releases/tags/$igc_tag")
    fi
    
    local igc_package_url=$(echo "$igc_response" | jq -r '.assets[] | select(.name | contains("intel-igc-opencl-2_")) | .browser_download_url' | head -1)
    
    # Download a sample Compute Runtime package
    local cr_response
    if [ -n "$GITHUB_TOKEN" ]; then
        cr_response=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/intel/compute-runtime/releases/tags/$compute_runtime_tag")
    else
        cr_response=$(curl -s "https://api.github.com/repos/intel/compute-runtime/releases/tags/$compute_runtime_tag")
    fi
    
    local cr_package_url=$(echo "$cr_response" | jq -r '.assets[] | select(.name | contains("intel-opencl-icd_")) | .browser_download_url' | head -1)
    
    if [ -n "$igc_package_url" ] && [ "$igc_package_url" != "null" ] && [ -n "$cr_package_url" ] && [ "$cr_package_url" != "null" ]; then
        echo_debug "Downloading packages to check compatibility..."
        
        if wget -q "$igc_package_url" -O igc.deb 2>/dev/null && wget -q "$cr_package_url" -O cr.deb 2>/dev/null; then
            # Extract IGC version from package
            local igc_version=$(dpkg-deb --field igc.deb Version 2>/dev/null | cut -d'+' -f1)
            
            # Extract required IGC version from compute runtime dependencies
            local required_igc=$(dpkg-deb --field cr.deb Depends 2>/dev/null | grep -o "intel-igc-opencl-2 (= [^)]*)" | sed 's/intel-igc-opencl-2 (= \([^)]*\))/\1/' | head -1)
            
            cd - > /dev/null
            rm -rf "$temp_dir"
            
            if [ -n "$igc_version" ] && [ -n "$required_igc" ]; then
                echo_info "IGC package version: $igc_version"
                echo_info "Required IGC version: $required_igc"
                
                if [ "$igc_version" = "$required_igc" ]; then
                    echo_info "✅ Versions are compatible!"
                    return 0
                else
                    echo_error "❌ Version mismatch detected!"
                    echo_error "   IGC provides: $igc_version"
                    echo_error "   Runtime needs: $required_igc"
                    return 1
                fi
            fi
        fi
    fi
    
    cd - > /dev/null
    rm -rf "$temp_dir"
    echo_warn "Could not determine compatibility"
    return 1
}

# Function to collect compatible versions
collect_compatible_versions() {
    echo_info "=== Collecting Compatible Driver Versions ==="
    echo
    
    # First, get the latest compute runtime version
    echo_info "Getting latest compute runtime version..."
    local compute_runtime_tag=$(get_latest_release_tag "intel/compute-runtime")
    if [ $? -ne 0 ]; then
        echo_error "Failed to get compute runtime version"
        return 1
    fi
    echo_info "Latest compute runtime: $compute_runtime_tag"
    
    # Find compatible IGC version
    local compatible_igc_version=$(find_compatible_igc_version "$compute_runtime_tag")
    if [ $? -ne 0 ]; then
        echo_warn "Could not determine compatible IGC version, using latest..."
        IGC_TAG=$(get_latest_release_tag "intel/intel-graphics-compiler")
    else
        IGC_TAG=$(find_igc_tag_for_version "$compatible_igc_version")
        if [ $? -ne 0 ]; then
            echo_warn "Could not find IGC tag for version $compatible_igc_version, using latest..."
            IGC_TAG=$(get_latest_release_tag "intel/intel-graphics-compiler")
        fi
    fi
    
    # Get other component versions
    COMPUTE_RUNTIME_TAG="$compute_runtime_tag"
    NPU_DRIVER_TAG=$(get_latest_release_tag "intel/linux-npu-driver")
    LEVEL_ZERO_TAG=$(get_latest_release_tag "oneapi-src/level-zero")
    
    echo
    echo_info "=== Selected Versions ==="
    echo_info "IGC: $IGC_TAG"
    echo_info "Compute Runtime: $COMPUTE_RUNTIME_TAG"
    echo_info "NPU Driver: $NPU_DRIVER_TAG"
    echo_info "Level Zero: $LEVEL_ZERO_TAG"
    echo
    
    # Verify compatibility
    echo_info "=== Verifying Compatibility ==="
    if check_version_compatibility "$IGC_TAG" "$COMPUTE_RUNTIME_TAG"; then
        echo_info "✅ All versions are compatible!"
        return 0
    else
        echo_error "❌ Version compatibility issues detected!"
        return 1
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [options]

Options:
    --check              Check compatibility of current latest versions
    --igc-tag <tag>      Check specific IGC tag compatibility
    --runtime-tag <tag>  Check specific Compute Runtime tag compatibility
    --help               Show this help message

Examples:
    $0 --check                                    # Check latest versions
    $0 --igc-tag v2.14.1 --runtime-tag 25.22.33944.8  # Check specific versions

Environment Variables:
    GITHUB_TOKEN         GitHub personal access token (recommended)
EOF
}

# Main execution
main() {
    local check_latest=false
    local igc_tag=""
    local runtime_tag=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check)
                check_latest=true
                shift
                ;;
            --igc-tag)
                igc_tag="$2"
                shift 2
                ;;
            --runtime-tag)
                runtime_tag="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Check for required tools
    if ! command -v jq &> /dev/null; then
        echo_error "jq is required but not installed. Install with: sudo apt install jq"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        echo_error "curl is required but not installed. Install with: sudo apt install curl"
        exit 1
    fi
    
    echo_info "Intel Driver Version Compatibility Checker"
    echo_info "=========================================="
    echo
    
    if [ "$check_latest" = true ]; then
        # Check compatibility of latest versions
        if collect_compatible_versions; then
            echo
            echo_info "✅ Compatibility check passed!"
            echo_info "These versions can be used together safely."
            exit 0
        else
            echo
            echo_error "❌ Compatibility issues found!"
            echo_error "Using these versions together may cause dependency conflicts."
            exit 1
        fi
    elif [ -n "$igc_tag" ] && [ -n "$runtime_tag" ]; then
        # Check specific version compatibility
        echo_info "Checking specific versions:"
        echo_info "IGC: $igc_tag"
        echo_info "Compute Runtime: $runtime_tag"
        echo
        
        if check_version_compatibility "$igc_tag" "$runtime_tag"; then
            echo
            echo_info "✅ These versions are compatible!"
            exit 0
        else
            echo
            echo_error "❌ These versions are NOT compatible!"
            echo_error "This combination will cause dependency conflicts."
            exit 1
        fi
    else
        echo_error "No action specified. Use --check or provide specific versions."
        echo
        show_usage
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
