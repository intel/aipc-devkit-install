#!/bin/bash

# Simple test script to show what driver versions would be downloaded
# This version has more robust error handling and debugging

echo "=== Simple Driver Version Test ==="
echo
echo "Note: This script uses the GitHub API which has rate limits."

# Check GitHub token status
if [ -n "$GITHUB_TOKEN" ]; then
    echo "✓ GitHub token is configured (${#GITHUB_TOKEN} characters)"
    echo "  This will allow higher rate limits and better reliability."
else
    echo "⚠ No GitHub token found in environment"
    echo "  Recommendation: Set GITHUB_TOKEN for better reliability:"
    echo "  1. Get a token at: https://github.com/settings/tokens"
    echo "  2. export GITHUB_TOKEN=your_token_here"
    echo "  3. Re-run this script"
fi
echo

# Test HTTPS connectivity
echo "1. Testing HTTPS connectivity..."
if curl -s --connect-timeout 5 --max-time 10 https://github.com > /dev/null; then
    echo "   ✓ Can reach github.com via HTTPS"
else
    echo "   ✗ Cannot reach github.com via HTTPS"
    exit 1
fi

# Test GitHub API basic endpoint
echo "2. Testing GitHub API..."
if [ -n "$GITHUB_TOKEN" ]; then
    echo "   ✓ GitHub token is set (length: ${#GITHUB_TOKEN} characters)"
    echo "   Using authenticated requests..."
    API_RESPONSE=$(curl -s --connect-timeout 5 --max-time 10 -H "Authorization: token $GITHUB_TOKEN" https://api.github.com)
else
    echo "   ⚠ No GitHub token set - using unauthenticated requests"
    echo "   Note: This may hit rate limits quickly. Set GITHUB_TOKEN for better reliability."
    API_RESPONSE=$(curl -s --connect-timeout 5 --max-time 10 https://api.github.com)
fi

if [ $? -eq 0 ] && echo "$API_RESPONSE" | grep -q "current_user_url"; then
    echo "   ✓ GitHub API is accessible"
elif echo "$API_RESPONSE" | grep -q "rate limit exceeded"; then
    echo "   ✗ GitHub API rate limit exceeded"
    echo
    echo "   To fix this issue:"
    echo "   1. Set your GitHub token: export GITHUB_TOKEN=your_token_here"
    echo "   2. Get a token at: https://github.com/settings/tokens"
    echo "   3. Re-run this script"
    echo
    exit 1
else
    echo "   ✗ GitHub API is not accessible"
    echo "   Response: $API_RESPONSE"
    exit 1
fi

# Simple function to get version with verbose output
get_version_simple() {
    local repo="$1"
    echo "   Trying to fetch version for $repo..."
    
    local url="https://api.github.com/repos/$repo/releases/latest"
    echo "   URL: $url"
    
    local response
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "   Using authenticated request..."
        response=$(curl -s --connect-timeout 10 --max-time 30 -H "Authorization: token $GITHUB_TOKEN" "$url")
    else
        echo "   Using unauthenticated request..."
        response=$(curl -s --connect-timeout 10 --max-time 30 "$url")
    fi
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo "   curl failed with exit code: $exit_code"
        return 1
    fi
    
    if [ -z "$response" ]; then
        echo "   Empty response"
        return 1
    fi
    
    # Check if it's an error response
    if echo "$response" | grep -q '"message"'; then
        echo "   API Error:"
        echo "$response" | grep '"message"' | head -1
        return 1
    fi
    
    local version=$(echo "$response" | grep '"tag_name":' | head -1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
    
    if [ -z "$version" ]; then
        echo "   Could not parse version from response"
        echo "   First 200 chars of response: $(echo "$response" | head -c 200)"
        return 1
    fi
    
    echo "   ✓ Found version: $version"
    echo "$version"
}

echo
echo "3. Testing specific repositories..."

# Test each repository
repos=(
    "intel/intel-graphics-compiler"
    "intel/compute-runtime"
    "intel/linux-npu-driver"
    "oneapi-src/level-zero"
)

for repo in "${repos[@]}"; do
    echo
    echo "Testing $repo:"
    version=$(get_version_simple "$repo")
    if [ $? -eq 0 ]; then
        echo "   Result: $version"
    else
        echo "   Result: FAILED"
    fi
done

echo
echo "Test completed!"
