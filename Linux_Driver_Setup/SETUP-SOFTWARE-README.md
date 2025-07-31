# Intel AI PC Software Setup Guide

> **⚠️ IMPORTANT: Driver Setup Required First**
>
> Before running this software setup script, you **must** first install the Intel AI PC drivers using either:
>
> - **Recommended**: `./build-static-installer.sh --build-static` followed by `./setup-static-drivers.sh`
> - **Alternative**: `./setup-drivers.sh` (dynamic installer)
>
> The AI software components installed by this script require proper Intel GPU and NPU drivers to function correctly. See the main [README.md](README.md) for complete driver installation instructions.

## Overview

The `setup-software.sh` script is a comprehensive automation tool that sets up a complete AI development environment optimized for Intel AI PCs. It installs and configures essential AI/ML frameworks, development tools, notebooks, and sample applications to get you started with Intel AI PC development.

## What This Script Installs

### Core Development Tools

- **UV Package Manager**: Fast Python package manager for efficient dependency management
- **Python Virtual Environments**: Proper isolation for AI projects
- **Google Chrome**: Browser for web-based AI applications and Jupyter notebooks
- **Visual Studio Code**: Popular IDE with AI development extensions

### AI/ML Frameworks and Toolkits

- **OpenVINO Toolkit**: Intel's AI inference optimization framework
- **OpenVINO GenAI**: Generative AI toolkit with Intel optimizations
- **Ollama with IPEX-LLM**: Local LLM runtime with Intel Extension for PyTorch optimizations
- **Intel Extension for PyTorch (IPEX)**: Hardware-accelerated PyTorch for Intel GPUs and CPUs

### Notebooks and Workshop Materials

- **OpenVINO Notebooks**: Comprehensive collection of AI inference examples and tutorials
- **MSBuild 2025 Workshop**: Latest Intel AI PC development workshop materials
- **Additional Workshop Repositories**: Extra learning materials and sample projects

### Target Installation Directory

All AI development materials are installed under `~/intel/` for organized project management.

## Prerequisites

### System Requirements

- **Operating System**: Ubuntu 24.04 LTS (recommended)
- **Hardware**: Intel AI PC with compatible GPU and NPU
- **Memory**: At least 8GB RAM (16GB+ recommended for large models)
- **Storage**: At least 10GB free space for all components

### Required Dependencies

The script automatically verifies and installs these if missing:

- `python3-pip`: Python package installer
- `python3-venv`: Python virtual environment support
- `curl`: For downloading packages and repositories
- `git`: For cloning repositories

### Network Requirements

- Active internet connection for downloading packages and repositories
- Access to GitHub, PyPI, and other package repositories
- Sufficient bandwidth for downloading large AI models and datasets

## Usage

### Basic Usage

```bash
# Make the script executable
chmod +x setup-software.sh

# Run the setup (DO NOT use sudo)
./setup-software.sh
```

### Important Notes

- **Never run with sudo**: The script explicitly prevents running as root for security
- **Interactive Installation**: Some components may require user input during installation
- **Time Requirements**: Full installation may take 30-60 minutes depending on internet speed
- **Resumability**: Script checks for existing installations and can be re-run safely

## Installation Process

### Phase 1: System Preparation

1. Verifies user permissions (prevents sudo execution)
2. Checks and installs system dependencies
3. Creates the `~/intel` working directory
4. Sets up error handling and logging

### Phase 2: Python Environment Setup

1. Installs UV package manager for fast Python package management
2. Verifies Python 3 and pip installation
3. Sets up virtual environment capabilities

### Phase 3: AI Framework Installation

1. **OpenVINO Notebooks**: Clones and sets up the comprehensive notebook collection
2. **MSBuild 2025 Workshop**: Installs latest Intel AI PC workshop materials
3. **OpenVINO GenAI**: Sets up generative AI toolkit with Intel optimizations
4. **Ollama + IPEX-LLM**: Installs local LLM runtime with Intel GPU acceleration

### Phase 4: Development Tools

1. **Google Chrome**: Installs browser for web-based development
2. **VS Code**: Installs popular IDE for AI development
3. **Additional Repositories**: Clones supplementary workshop materials

## What Gets Installed Where

```text
~/intel/
├── openvino_notebooks/          # Main OpenVINO tutorial notebooks
├── MSBuild2025_NeuralChat/      # MSBuild 2025 workshop materials
├── openvino.genai/              # OpenVINO GenAI toolkit
├── WorkShops_BootCamp/          # Additional workshop materials
├── llm-on-ray/                  # LLM on Ray examples
├── intel-extension-for-pytorch/ # IPEX examples
└── various Python virtual environments
```

### System-wide Installations

- **Ollama**: Installed system-wide via official installer
- **Google Chrome**: Installed via .deb package
- **VS Code**: Installed via official repository
- **UV**: Installed system-wide Python package manager

## Post-Installation

### Verification Steps

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

### Getting Started

1. **Navigate to notebooks**: `cd ~/intel/openvino_notebooks`
2. **Activate environment**: `source venv/bin/activate`
3. **Start Jupyter**: `jupyter lab`
4. **Browse examples**: Explore the notebooks directory for AI examples

### Testing Ollama + IPEX-LLM

```bash
# Test Ollama with a simple model
ollama pull llama2:7b
ollama run llama2:7b "Hello, how are you?"
```

## Troubleshooting

### Common Issues

#### Permission Errors

- **Problem**: "Permission denied" errors during installation
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
- **Solution**: Ensure Intel GPU/NPU drivers are installed first using `setup-drivers.sh`

### Log Files

Installation logs are written to the terminal. For debugging:

1. Re-run the script with verbose output: `bash -x setup-software.sh`
2. Check individual component logs in their respective directories

### Getting Help

- Check the main [README.md](README.md) for driver installation guidance
- Review OpenVINO documentation in `~/intel/openvino_notebooks/`
- Consult Intel AI PC developer resources

## Advanced Configuration

### Customizing Installation

The script can be modified to skip certain components by commenting out function calls in the main execution section.

### Environment Variables

The script respects these environment variables:

- `HOME`: User home directory (used for ~/intel path)
- `PATH`: Updated with new tool locations

### Integration with Driver Setup

This software setup script is designed to work with the Intel AI PC driver installation:

1. First run: `./setup-drivers.sh` (or use the static installer)
2. Then run: `./setup-software.sh`
3. Finally verify: `./verify_connectivity.sh`

## Maintenance

### Updating Components

- **Ollama models**: `ollama pull <model-name>`
- **OpenVINO notebooks**: `cd ~/intel/openvino_notebooks && git pull`
- **VS Code**: Updates automatically or via system package manager
- **Chrome**: Updates automatically

### Removing Components

To clean up the installation:

```bash
# Remove all AI development materials
rm -rf ~/intel/

# Uninstall system packages (optional)
sudo apt remove google-chrome-stable code ollama
```

## Security Considerations

- Script prevents execution as root to avoid system-wide permission issues
- Downloads from official sources only (GitHub, official package repositories)
- Creates isolated Python environments to prevent dependency conflicts
- No modification of system-critical directories or configurations

## Support and Resources

- **Intel AI PC Documentation**: [Intel Developer Zone](https://www.intel.com/content/www/us/en/developer/topic-technology/artificial-intelligence/overview.html)
- **OpenVINO Documentation**: [OpenVINO Toolkit](https://docs.openvino.ai/)
- **Issues**: Report problems via the project repository

---

*This script is part of the Intel AI PC development toolkit and is designed to work in conjunction with the Intel GPU/NPU driver installation scripts.*
