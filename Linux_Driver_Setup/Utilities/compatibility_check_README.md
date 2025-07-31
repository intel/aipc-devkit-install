# Intel Driver Compatibility Checker (Optional Standalone Tool)

> **Note**: Compatibility checking is now **integrated into the main script**. Most users should use:
> ```bash
> ./build-static-installer.sh --build-static
> ```
> This standalone tool is **optional** and primarily useful for development, debugging, or testing specific version combinations.

This script helps identify and resolve version compatibility issues between Intel Graphics Compiler (IGC) and Intel Compute Runtime packages.

## Problem

When using the latest Intel drivers, you may encounter dependency conflicts like:
```
dpkg: dependency problems prevent configuration of intel-opencl-icd:
 intel-opencl-icd depends on intel-igc-opencl-2 (= 2.12.5); however:
  Version of intel-igc-opencl-2 on system is 2.14.1
```

This happens because the Intel Graphics Compiler and Compute Runtime are released independently, and the latest versions may not always be compatible.

## Solution

The `compatibility_check.sh` script:
1. 📡 Downloads package metadata from GitHub releases
2. 🔍 Analyzes dependency requirements in .deb packages  
3. ✅ Identifies compatible version combinations
4. 🛡️ Prevents installation of incompatible driver sets

## Usage

### Check Latest Versions
```bash
./compatibility_check.sh --check
```

### Check Specific Versions (Debugging)
```bash
./compatibility_check.sh --igc-tag v2.14.1 --runtime-tag 25.22.33944.8
```

### Example Output
```
[INFO] IGC package version: 2.14.1
[INFO] Required IGC version: 2.12.5
[ERROR] ❌ Version mismatch detected!
[ERROR]    IGC provides: 2.14.1
[ERROR]    Runtime needs: 2.12.5
```

## Environment Variables

- `GITHUB_TOKEN`: Personal access token for higher API rate limits (recommended)

## Integration Status

✅ **Compatibility checking is now integrated** into `verify_latest_driver_names.sh --build-static`

This standalone script is **optional** and mainly useful for:
- 🔧 **Development/debugging**: Testing specific version combinations
- 📊 **Manual verification**: Quick compatibility checks without generating static script
- 🛠️ **Troubleshooting**: Advanced users who want detailed compatibility analysis

## Requirements

- `jq` - JSON processor
- `curl` - HTTP client  
- `dpkg-deb` - Debian package tools
- Internet connectivity to GitHub

## Install Requirements

```bash
sudo apt install jq curl
```
