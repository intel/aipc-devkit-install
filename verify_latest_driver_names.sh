#!/bin/bash

# Verify Latest Driver Names - No installation, just inspection
# This script safely queries GitHub API to show available driver assets without downloading anything

set -e

echo "=== Latest Driver Names Verification ==="
echo "This script safely checks what driver assets are available from GitHub releases"
echo "No files will be downloaded or installed"
echo

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Install with: sudo apt install jq"
    exit 1
fi

# Function to safely get latest release tag
get_latest_release_tag() {
    local repo="$1"
    echo "Checking latest release for $repo..."
    
    local response=$(curl -s "https://api.github.com/repos/$repo/releases/latest")
    
    # Check if we got rate limited
    if echo "$response" | jq -r '.message' 2>/dev/null | grep -q "rate limit"; then
        echo "ERROR: GitHub API rate limit exceeded"
        echo "Solution: Set GITHUB_TOKEN environment variable with a personal access token"
        echo "Visit: https://github.com/settings/tokens"
        return 1
    fi
    
    local tag=$(echo "$response" | jq -r '.tag_name // "ERROR"')
    if [ "$tag" = "ERROR" ] || [ "$tag" = "null" ]; then
        echo "ERROR: Could not get latest release tag for $repo"
        echo "Response: $response" | head -3
        return 1
    fi
    
    echo "Latest release: $tag"
    echo "$tag"
}

# Function to safely list release assets
list_release_assets() {
    local repo="$1"
    local tag="$2"
    echo
    echo "=== Assets for $repo release $tag ==="
    
    local response=$(curl -s "https://api.github.com/repos/$repo/releases/tags/$tag")
    
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
}

# Function to test asset pattern matching
test_pattern_matching() {
    local repo="$1"
    local tag="$2"
    local pattern="$3"
    
    echo "Testing pattern '$pattern' against $repo $tag:"
    
    local response=$(curl -s "https://api.github.com/repos/$repo/releases/tags/$tag")
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

# Main execution
echo "Checking GitHub API connectivity..."

# Test basic API access
if ! curl -s "https://api.github.com/rate_limit" | jq -r '.rate.remaining' > /dev/null; then
    echo "ERROR: Cannot access GitHub API or jq parsing failed"
    exit 1
fi

echo "✓ GitHub API accessible"
echo

# Check rate limit status
rate_info=$(curl -s "https://api.github.com/rate_limit")
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
repos=("intel/intel-graphics-compiler" "intel/compute-runtime")

for repo in "${repos[@]}"; do
    echo "----------------------------------------"
    
    # Get latest release tag
    if tag=$(get_latest_release_tag "$repo"); then
        # List all assets
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
    else
        echo "Failed to get release information for $repo"
    fi
    echo "----------------------------------------"
done

show_current_patterns

echo "=== Summary ==="
echo "This diagnostic script completed safely without installing anything."
echo "Use the output above to:"
echo "1. Verify GitHub API connectivity"
echo "2. See what assets are actually available"
echo "3. Compare with patterns used in setup-drivers.sh"
echo "4. Identify any mismatched patterns that need updating"
