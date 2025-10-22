# Intel AI PC Linux Setup Guide

Complete guide for setting up Intel AI PC development on Linux, including driver installation and AI software environment setup.

---

## 🔧 Part 1: Driver Setup (Required First)

> **⚠️ CRITICAL: Install Drivers Before AI Software**
>
> You **must** install Intel GPU and NPU drivers before installing any AI development software. The AI frameworks and tools require proper driver support to function correctly.

### Overview

This directory contains scripts to set up Intel GPU and NPU drivers on Ubuntu 24.04 for AI PC platforms. The setup builds an installation script that represents the latest versions of the drivers that work together.

**Available Scripts:**
- **`build-static-installer.sh`**: ⭐ Static installer builder (no GitHub token required)
- **`setup-static-drivers.sh`**: Generated static driver installation script (no API dependencies)
- **`Utilities/verify_connectivity.sh`**: Diagnostic tools for troubleshooting GitHub API connectivity issues

### Driver Installation Steps

#### Step 1: Build and Run Static Installer ⭐

**No GitHub token required** 

```bash
# Navigate to driver setup directory
cd Linux_Driver_Setup

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

---

## 🚀 Part 2: Software Setup (After Driver Installation)

> **⚠️ IMPORTANT: Driver Setup Required First**
> **⚠️ IMPORTANT: After installing drivers reboot the system before continuing to part 2.**
>
> Before running this software setup, ensure you have completed Part 1 (Driver Setup) above. The AI software components require proper Intel GPU and NPU drivers to function correctly.

### Overview

The `setup-software.sh` script (located in `../Linux_Software_Installation/`) is a comprehensive automation tool that sets up a complete AI development environment optimized for Intel AI PCs. It installs and configures essential AI/ML frameworks, development tools, notebooks, and sample applications.

### What This Script Installs

#### Core Development Tools

- **UV Package Manager**: Fast Python package manager for efficient dependency management
- **Python Virtual Environments**: Proper isolation for AI projects
- **Google Chrome**: Browser for web-based AI applications and Jupyter notebooks
- **Visual Studio Code**: Popular IDE with AI development extensions

#### AI/ML Frameworks and Toolkits

- **OpenVINO Toolkit**: Intel's AI inference optimization framework
- **OpenVINO GenAI**: Generative AI toolkit with Intel optimizations
- **Ollama**: Local LLM runtime with Intel GPU acceleration

#### Notebooks and Workshop Materials

- **OpenVINO Notebooks**: Comprehensive collection of AI inference examples and tutorials
- **MSBuild 2025 Workshop**: Latest Intel AI PC development workshop materials
- **Additional Workshop Repositories**: Extra learning materials and sample projects

#### Target Installation Directory

All AI development materials are installed under `~/intel/` for organized project management.

### Software Installation Steps

#### Prerequisites

- **Operating System**: Ubuntu 24.04 LTS (recommended)
- **Hardware**: Intel AI PC with compatible GPU and NPU
- **Drivers**: Intel GPU/NPU drivers installed (Part 1 above)
- **Memory**: At least 16GB RAM (32GB+ recommended for large models)
- **Storage**: At least 10GB free space for all components

#### Installation Commands

```bash
# Navigate to software setup directory
cd ../Linux_Software_Installation

# Make the script executable
chmod +x setup-software.sh

# Run the setup (DO NOT use sudo)
./setup-software.sh
```

**Important Notes:**
- **Never run with sudo**: The script explicitly prevents running as root for security
- **Interactive Installation**: Some components may require user input during installation
- **Time Requirements**: Full installation may take 30-60 minutes depending on internet speed
- **Resumability**: Script checks for existing installations and can be re-run safely

### Installation Process

#### Phase 1: System Preparation

1. Verifies user permissions (prevents sudo execution)
2. Checks and installs system dependencies
3. Creates the `~/intel` working directory
4. Sets up error handling and logging

#### Phase 2: Python Environment Setup

1. Installs UV package manager for fast Python package management
2. Verifies Python 3 and pip installation
3. Sets up virtual environment capabilities

#### Phase 3: AI Framework Installation

1. **OpenVINO Notebooks**: Clones and sets up the comprehensive notebook collection
2. **MSBuild 2025 Workshop**: Installs latest Intel AI PC workshop materials
3. **OpenVINO GenAI**: Sets up generative AI toolkit with Intel optimizations
4. **Ollama**: Installs local LLM runtime with Intel GPU acceleration

#### Phase 4: Development Tools

1. **Google Chrome**: Installs browser for web-based development
2. **VS Code**: Installs popular IDE for AI development
3. **Additional Repositories**: Clones supplementary workshop materials

### What Gets Installed Where

```text
~/intel/
├── openvino_notebooks/          # Main OpenVINO tutorial notebooks
├── MSBuild2025_NeuralChat/      # MSBuild 2025 workshop materials
├── openvino.genai/              # OpenVINO GenAI toolkit
├── WorkShops_BootCamp/          # Additional workshop materials
├── llm-on-ray/                  # LLM on Ray examples
└── various Python virtual environments
```

**System-wide Installations:**
- **Ollama**: Installed system-wide via official installer
- **Google Chrome**: Installed via .deb package
- **VS Code**: Installed via official repository
- **UV**: Installed system-wide Python package manager

### Post-Installation

#### Verification Steps

After installation completes, verify your setup:

```bash
# Check Ollama installation
ollama --version

# Check UV installation
uv --version

# Check Chrome installation
google-chrome --version

# Check VS Code installation
code --version

# Verify Python environments
ls ~/intel/*/venv/
```

#### Getting Started

1. **Navigate to notebooks**: `cd ~/intel/openvino_notebooks`
2. **Activate environment**: `source venv/bin/activate`
3. **Start Jupyter**: `jupyter lab`
4. **Browse examples**: Explore the notebooks directory for AI examples

#### Testing Ollama

```bash
# Test Ollama with a simple model
ollama pull llama2:7b
ollama run llama2:7b "Hello, how are you?"
```

---

## 🛠️ Comprehensive Troubleshooting

### Driver Issues

#### GitHub API Rate Limiting
**Problem**: Installation fails with rate limit errors -- this sometimes happens if you are at a company behind a proxy and it appears that many users are sharing the same IP address.

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

# Run full diagnostic (from Linux_Driver_Setup directory)
./Utilities/verify_connectivity.sh
```

#### Permission Issues
**Problem**: Script fails due to insufficient privileges

**Solution**: Run with sudo (drivers only)
```bash
sudo ./setup-static-drivers.sh
```

### Software Installation Issues

#### Permission Errors

- **Problem**: "Permission denied" errors during software installation
- **Solution**: Ensure you're not running with sudo and have write access to home directory

#### Network Timeouts

- **Problem**: Downloads fail due to network issues
- **Solution**: Check internet connection and re-run the script (it will skip completed installations)

#### Python Environment Issues

- **Problem**: Virtual environment creation fails
- **Solution**: Ensure python3-venv is installed: `sudo apt install python3-venv`

#### Disk Space Issues

- **Problem**: Installation fails due to insufficient space
- **Solution**: Free up at least 10GB of space and re-run

#### GPU/NPU Recognition Issues

- **Problem**: AI acceleration not working
- **Solution**: Verify drivers are properly installed using the diagnostic script

### Log Files

Installation logs are written to the terminal. For debugging:

1. Re-run the script with verbose output: `bash -x setup-software.sh`
2. Check individual component logs in their respective directories

---

## 📚 Advanced Configuration

### Updating Components

#### Driver Updates

To update to newer driver versions:

```bash
cd Linux_Driver_Setup

# Regenerate with latest versions
./build-static-installer.sh --build-static

# The static installer will be updated with new URLs
sudo ./setup-static-drivers.sh
```

#### Software Updates

- **Ollama models**: `ollama pull <model-name>`
- **OpenVINO notebooks**: `cd ~/intel/openvino_notebooks && git pull`
- **VS Code**: Updates automatically or via system package manager
- **Chrome**: Updates automatically

### Environment Variables

#### Driver Setup Variables

- **`GITHUB_TOKEN`**: Personal access token for GitHub API (recommended)
- **`OS_ID`**: Target OS identifier (default: "ubuntu")
- **`OS_VERSION`**: Target OS version (default: "24.04")

#### Software Setup Variables

- `HOME`: User home directory (used for ~/intel path)
- `PATH`: Updated with new tool locations

### Customizing Installation

The software script can be modified to skip certain components by commenting out function calls in the main execution section.

### Removing Components

To clean up the software installation:

```bash
# Remove all AI development materials
rm -rf ~/intel/

# Uninstall system packages (optional)
sudo apt remove google-chrome-stable code ollama
```

---

## 📞 Support and Resources

- **Intel AI PC Documentation**: [Intel Developer Zone](https://www.intel.com/content/www/us/en/developer/topic-technology/artificial-intelligence/overview.html)
- **OpenVINO Documentation**: [OpenVINO Toolkit](https://docs.openvino.ai/)
- **Issues**: Report problems via the project repository

## 📄 Security Considerations

- Driver scripts run with sudo for necessary system-level installations
- Software script prevents execution as root to avoid system-wide permission issues
- Downloads from official sources only (GitHub, official package repositories)
- Creates isolated Python environments to prevent dependency conflicts
- No modification of system-critical directories or configurations

## Contributing

When contributing to this project:

1. Test changes with the diagnostic script first
2. Ensure compatibility with Ubuntu 24.04
3. Update documentation for any new features
4. Follow the existing error handling patterns

---

*This guide is part of the Intel AI PC development toolkit. Follow the steps in order: Drivers First (Part 1), then Software Setup (Part 2).*

