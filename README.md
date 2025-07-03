# Intel AI PC Linux Setup

This repository contains scripts to set up Intel GPU and NPU drivers on Ubuntu 24.04 for AI PC platforms.

## Overview

The setup consists of several scripts to provide flexible driver installation options:
- **`setup-drivers.sh`**: Main driver installation script (requires root privileges and GitHub API access)
- **`setup-static-drivers.sh`**: Static driver installation script (generated file, no API dependencies)
- **`verify_connectivity_driver_versions.sh`**: Diagnostic tool for troubleshooting GitHub API connectivity issues
- **`verify_latest_driver_names.sh`**: Tool to inspect available driver assets and optionally generate static installer

## Installation Methods

You have **two options** for installing Intel GPU and NPU drivers:

### Option 1: Direct Installation (Recommended if you have GITHUB_TOKEN)

If you have a GitHub token set up, you can use the original direct method:

```bash
# Set your GitHub token (get one from https://github.com/settings/tokens)
export GITHUB_TOKEN=your_personal_access_token_here

# Run the installation
sudo -E ./setup-drivers.sh
```

### Option 2: Two-Step Static Installation (Recommended to avoid rate limits)

If you don't have a GitHub token or want to avoid API rate limits, use the two-step process:

```bash
# Step 1: Verify connectivity and generate static installer
./verify_latest_driver_names.sh --build-static

# Step 2: Run the generated static installer
sudo ./setup-static-drivers.sh
```

**Benefits of the static method:**
- ✅ No GitHub API rate limits
- ✅ No need for GitHub token
- ✅ Faster installation (direct downloads)
- ✅ More reliable (no API dependencies)
- ✅ Can be run offline after generation

## Quick Start

Choose one of the two installation methods below:

### Method 1: Direct Installation (If you have GITHUB_TOKEN)

```bash
# Set your GitHub token (get one from https://github.com/settings/tokens)
export GITHUB_TOKEN=your_personal_access_token_here

# Run the installation
sudo -E ./setup-drivers.sh
```

### Method 2: Two-Step Static Installation (Recommended)

```bash
# Step 1: Verify connectivity and generate static installer
./verify_latest_driver_names.sh --build-static

# Step 2: Run the generated static installer
sudo ./setup-static-drivers.sh
```

## Troubleshooting Installation Issues

### If Method 1 Fails Due to Download Issues

The script will display a troubleshooting message:

```
Error: Failed to get latest release for intel/intel-graphics-compiler
Troubleshooting: Run './verify_connectivity_driver_versions.sh' to diagnose GitHub API connectivity issues
```

### Run the Diagnostic Tool

```bash
./verify_connectivity_driver_versions.sh
```

### Fix Any Issues

If you encounter GitHub API rate limiting, either:

1. **Set a GitHub token** (for Method 1):

   ```bash
   export GITHUB_TOKEN=your_personal_access_token_here
   ```

   To get a token:
   
   1. Go to <https://github.com/settings/tokens>
   2. Generate a new token (classic) with minimal permissions
   3. Copy the token and export it as shown above

2. **Use the static method** (Method 2) to avoid API issues entirely

## What Gets Installed

The setup script installs the following components:

### Intel GPU Drivers
- Intel Graphics Compiler (IGC)
- Intel Compute Runtime
- OpenCL drivers
- Level Zero drivers

### Intel NPU Drivers
- Intel NPU driver compiler
- Intel NPU firmware
- Intel Level Zero NPU drivers

### Supporting Packages
- Required dependencies (curl, wget, clinfo, etc.)
- Intel GPU repository configuration
- Proper user group permissions (video, render)

## System Requirements

- **OS**: Ubuntu 24.04 LTS
- **Kernel**: 6.8 or newer (recommended for optimal compatibility)
- **Hardware**: Intel AI PC with compatible GPU/NPU
- **Privileges**: Root/sudo access for installation

## Troubleshooting

### Common Issues

#### GitHub API Rate Limiting
**Problem**: Installation fails with rate limit errors
**Solution**: Set GITHUB_TOKEN environment variable
```bash
export GITHUB_TOKEN=your_token_here
sudo -E ./setup-drivers.sh  # -E preserves environment variables
```

#### Network Connectivity
**Problem**: Cannot reach GitHub
**Solution**: Check your internet connection and firewall settings
```bash
# Test basic connectivity
curl https://github.com

# Run full diagnostic
./simple_test_driver_versions.sh
```

#### Permission Issues
**Problem**: Script fails due to insufficient privileges
**Solution**: Run with sudo
```bash
sudo ./setup-drivers.sh
```

### Diagnostic Script Output

The `simple_test_driver_versions.sh` script performs these checks:

1. **HTTPS Connectivity**: Tests connection to github.com
2. **GitHub API Access**: Verifies API accessibility and rate limits
3. **Repository Testing**: Checks latest versions for all required repositories:
   - intel/intel-graphics-compiler
   - intel/compute-runtime
   - intel/linux-npu-driver
   - oneapi-src/level-zero

#### Successful Output Example
```
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
```
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

## Installation Workflow

```mermaid
flowchart TD
    A[Choose Installation Method] --> B{Have GitHub Token?}
    B -->|Yes| C[Method 1: Direct Installation]
    B -->|No| D[Method 2: Static Installation]
    
    C --> E[export GITHUB_TOKEN=token]
    E --> F[sudo -E ./setup-drivers.sh]
    F --> G{Installation Successful?}
    G -->|Yes| H[✓ Drivers Installed]
    G -->|No| I[Run diagnostics]
    
    D --> J[./verify_latest_driver_names.sh --build-static]
    J --> K[sudo ./setup-static-drivers.sh]
    K --> L{Installation Successful?}
    L -->|Yes| H
    L -->|No| M[Check logs/permissions]
    
    I --> N[Fix GitHub API issues]
    N --> F
    M --> O[Fix system issues]
    O --> K
```

## Comparison of Installation Methods

| Feature | Method 1 (Direct) | Method 2 (Static) |
|---------|-------------------|-------------------|
| **GitHub Token Required** | ✅ Yes | ❌ No |
| **Internet During Install** | ✅ Required | ✅ Required |
| **GitHub API Calls** | ✅ Many | ❌ None |
| **Rate Limit Risk** | ⚠️ High | ❌ None |
| **Installation Speed** | ⚠️ Slower | ✅ Faster |
| **Reliability** | ⚠️ API dependent | ✅ Direct downloads |
| **Setup Complexity** | ✅ Simple | ⚠️ Two-step |

**Recommendation**: Use Method 2 (Static) for production deployments and Method 1 (Direct) for development/testing when you already have a GitHub token configured.

## File Structure

```
training.developer.aipc/
├── README.md                           # This file
├── setup-drivers.sh                    # Main installation script (GitHub API method)
├── setup-static-drivers.sh             # Static installation script (generated)
├── verify_connectivity_driver_versions.sh # Diagnostic tool
├── verify_latest_driver_names.sh       # Asset inspection and static script generator
├── setup-software.sh                   # Software setup (separate)
└── LICENSE                             # License information
```

## Advanced Usage

### Generating Static Installers

The `verify_latest_driver_names.sh` script can be used to generate static installers:

```bash
# Generate static installer with current latest versions
./verify_latest_driver_names.sh --build-static

# Just verify connectivity and assets (no generation)
./verify_latest_driver_names.sh
```

### Updating Static Installers

To update to newer driver versions:

```bash
# Regenerate with latest versions
./verify_latest_driver_names.sh --build-static

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
./simple_test_driver_versions.sh
```

## Contributing

When contributing to this project:

1. Test changes with the diagnostic script first
2. Ensure compatibility with Ubuntu 24.04
3. Update documentation for any new features
4. Follow the existing error handling patterns

## License

Copyright (C) 2025 Intel Corporation
SPDX-License-Identifier: Apache-2.0
