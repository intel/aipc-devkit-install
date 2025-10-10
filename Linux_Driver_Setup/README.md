# Intel AI PC Linux Driver Setup

This directory contains scripts to set up Intel GPU and NPU drivers on Ubuntu 24.04 for AI PC platforms.

## Overview

The setup builds an installation script that represents the latest versions of the drivers that work together.

- **`build-static-installer.sh`**: ⭐ Static installer builder (no GitHub token required)
- **`setup-static-drivers.sh`**: Generated static driver installation script (no API dependencies)
- **`Utilities/verify_connectivity.sh`**: Diagnostic tools for troubleshooting GitHub API connectivity issues

### Step 1: Static Script Creation ⭐

**No GitHub token required** 

```bash
# Step 1: Build static installer with compatibility checking
./build-static-installer.sh --build-static

# Step 2: Run the generated static installer
sudo ./setup-static-drivers.sh
```

## Troubleshooting


#### GitHub API Rate Limiting
**Problem**: Installation fails with rate limit errors -- this sometimes happens if you are at a company behind a proxy and it appears that many users are sharing the same iP address.
**Solution**: Set GITHUB_TOKEN environment variable
```bash
export GITHUB_TOKEN=your_token_here
sudo -E ./setup-static-drivers.sh  # -E preserves environment variables
```

#### Network Connectivity
**Problem**: Cannot reach GitHub
**Solution**: Check your internet connection and firewall settings
```bash
# Test basic connectivity
curl https://github.com

# Run full diagnostic
./verify_connectivity.sh
```

#### Permission Issues
**Problem**: Script fails due to insufficient privileges
**Solution**: Run with sudo
```bash
sudo ./setup-static-drivers.sh
```

### Diagnostic Script Output

The `verify_connectivity.sh` script performs these checks:

1. **HTTPS Connectivity**: Tests connection to github.com
2. **GitHub API Access**: Verifies API accessibility and rate limits
3. **Repository Testing**: Checks latest versions for all required repositories:
   - intel/intel-graphics-compiler
   - intel/compute-runtime
   - intel/linux-npu-driver
   - oneapi-src/level-zero

#### Successful Output Example

```text
=== Simple Driver Version Test ===

1. Testing HTTPS connectivity...
   ✓ Can reach github.com via HTTPS
2. Testing GitHub API...
   Using GitHub authentication token
   ✓ GitHub API is accessible

3. Testing specific repositories...

Testing intel/intel-graphics-compiler:
   ✓ Found version: v2.12.5

Testing intel/compute-runtime:
   ✓ Found version: 25.22.33944.8

Testing intel/linux-npu-driver:
   ✓ Found version: v1.17.0

Testing oneapi-src/level-zero:
   ✓ Found version: v1.22.4

Test completed!
```

#### Rate Limited Output Example

```text
=== Simple Driver Version Test ===

1. Testing HTTPS connectivity...
   ✓ Can reach github.com via HTTPS
2. Testing GitHub API...
   ✗ GitHub API rate limit exceeded

   To fix this issue:
   1. Set your GitHub token: export GITHUB_TOKEN=your_token_here
   2. Get a token at: https://github.com/settings/tokens
   3. Re-run this script
```


### Updating Static Installers

To update to newer driver versions:

```bash
# Regenerate with latest versions
./build-static-installer.sh --build-static

# The static installer will be updated with new URLs
sudo ./setup-static-drivers.sh
```

### Environment Variables

- **`GITHUB_TOKEN`**: Personal access token for GitHub API (recommended)
- **`OS_ID`**: Target OS identifier (default: "ubuntu")
- **`OS_VERSION`**: Target OS version (default: "24.04")

### Manual Package Selection

The script automatically downloads the latest versions, but you can check what versions would be installed:

```bash
./Utilities/verify_connectivity.sh
```

## Contributing

When contributing to this project:

1. Test changes with the diagnostic script first
2. Ensure compatibility with Ubuntu 24.04
3. Update documentation for any new features
4. Follow the existing error handling patterns

