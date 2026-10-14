# Intel AI PC Linux Setup Guide

Complete guide for setting up Intel AI PC development on Linux, including driver installation and AI software environment setup.

---

## Quick Start

For a first-time Linux driver setup on Ubuntu 24.04 or 26.04, run:

```bash
# From the repository root
cd Linux_Software_Installation

# Behind a corporate proxy, export it first (example)
# export http_proxy=http://proxy.example.com:912 https_proxy=$http_proxy

# Generate the driver installer for this Ubuntu release
./build-static-installer.sh --build-static

# Install the drivers (-E keeps proxy settings for apt/curl)
sudo -E ./setup-static-drivers.sh
```

After the driver installation completes, reboot the machine before running `setup-software.sh`.

---

## 🔧 Part 1: Driver Setup (Required First)

> **⚠️ CRITICAL: Install Drivers Before AI Software**
>
> You **must** install Intel GPU and NPU drivers before installing any AI development software. The AI frameworks and tools require proper driver support to function correctly.

### Overview

The driver setup supports **Ubuntu 24.04 (noble)** and **Ubuntu 26.04 (resolute)** and uses the same flow on both:

- **GPU drivers** come from the Intel Graphics PPA (`ppa:kobuk-team/intel-graphics`), following Intel's guide: [Installing packages from the Intel PPA](https://dgpu-docs.intel.com/installation-guides/installing-packages-from-the-intel-ppa.html).
- **NPU driver** comes from the latest [intel/linux-npu-driver](https://github.com/intel/linux-npu-driver/releases) release tarball for the matching Ubuntu release (`ubuntu2404` or `ubuntu2604`). The NPU packages use the `libze1` Level Zero loader from the PPA.

**Available Scripts:**
- **`build-static-installer.sh`**: Builder. Detects the Ubuntu release, checks that the PPA is reachable, resolves the latest NPU driver release and its SHA256, and generates `setup-static-drivers.sh`.
- **`setup-static-drivers.sh`**: Generated installer (run as root). Pins the NPU release the builder found.
- **`Utilities/verify_connectivity.sh`**: Read-only check that the PPA, Launchpad, and GitHub are reachable (through your proxy, if set).

### What `setup-static-drivers.sh` does

1. Checks it runs as root on the Ubuntu release it was generated for, and uses proxy settings provided at run time. It does not embed a build-machine proxy address.
2. On 24.04, warns if the HWE kernel is missing. Intel requires it for Lunar Lake, Battlemage and Panther Lake; install with `sudo apt-get install -y --install-recommends linux-generic-hwe-24.04` and reboot. The script never changes kernels.
3. Removes conflicts from the previous GitHub-based flow: the legacy `repositories.intel.com` apt source, and the `level-zero`, `level-zero-devel` and `intel-level-zero-gpu` packages (they conflict with the PPA `libze1`).
4. Adds `ppa:kobuk-team/intel-graphics` and installs:
   - Compute: `libze-intel-gpu1 libze1 intel-metrics-discovery intel-opencl-icd clinfo intel-gsc`
   - Media: `intel-media-va-driver-non-free libmfx-gen1.2 libvpl2 libvpl-tools libva-glx2 va-driver-all vainfo`
   - Development: `libze-dev intel-ocloc`

   GPU packages that were previously installed from GitHub `.deb` files are moved to the PPA versions (`--allow-downgrades`).
5. Downloads the NPU tarball, requires and verifies its SHA256 before changing NPU packages, installs its `.deb` files with `apt-get` (including `intel-fw-npu`, `intel-level-zero-npu` and `intel-driver-compiler-npu`) so dependencies are resolved in one step, and adds the `/dev/accel` udev rule. If the release has no SHA256, the builder stops rather than generating an unchecked installer.
6. Adds the user to the `video` and `render` groups.

**Reboot afterwards.**

### Builder Features (`build-static-installer.sh`)

- **Version detection**: Ubuntu 24.04 and 26.04 are supported; other releases stop with an error.
- **Dependencies**: Installs missing `curl`/`jq` with `sudo -E apt-get` (you may be prompted for your sudo password).
- **Proxy-aware**: Uses `http_proxy`/`https_proxy` (reuses `http_proxy` for HTTPS if only that is set). It does not print or embed proxy addresses in the generated script.
- **Rate-limit tolerant**: Uses the GitHub API (optionally with `GITHUB_TOKEN`), and falls back to the github.com release page when the API is rate limited (common behind shared corporate egress IPs).
- **Safe generation**: The generated script is syntax-checked before it replaces the previous one.
- Run without arguments to see the status, or with `--help` for usage.

### Driver Installation Steps

```bash
cd Linux_Software_Installation

# Optional: confirm the driver sources are reachable
./Utilities/verify_connectivity.sh

# Step 1: Generate the installer
./build-static-installer.sh --build-static

# Step 2: Run it (-E keeps proxy variables)
sudo -E ./setup-static-drivers.sh

# Step 3: Reboot
sudo reboot
```

After reboot, verify:

```bash
clinfo | grep -i "device name"   # Intel GPU listed
ls /dev/dri/renderD* /dev/accel/accel0
groups                           # includes video and render
```

### Uninstalling the PPA

```bash
sudo add-apt-repository --remove -y ppa:kobuk-team/intel-graphics
sudo apt-get update
```

## Troubleshooting

#### Behind a Corporate Proxy
**Problem**: `apt`, `add-apt-repository` or `curl` time out.
**Solution**: Export the proxy before running the builder and keep it through `sudo` with `-E`:
```bash
export http_proxy=http://proxy.example.com:912
export https_proxy=$http_proxy
./build-static-installer.sh --build-static
sudo -E ./setup-static-drivers.sh
```
Plain `sudo` may drop proxy variables. Export the proxy appropriate to the machine running the installer, then use `sudo -E`; if your sudo policy still removes them, configure proxy access for apt/curl locally before retrying. No proxy address is recorded in the generated script.

#### GitHub API Rate Limiting
**Problem**: The builder reports the GitHub API is rate limited (many users sharing one corporate IP).
**Solution**: Usually nothing; the builder falls back to the release page automatically. If that also fails, set a token:
```bash
export GITHUB_TOKEN=your_token_here
./build-static-installer.sh --build-static
```

#### Network Connectivity
```bash
./Utilities/verify_connectivity.sh
```

#### Permission Issues
**Problem**: `Run with sudo: sudo -E ./setup-static-drivers.sh`
**Solution**: The installer must run as root:
```bash
sudo -E ./setup-static-drivers.sh
```

#### Generated For a Different Ubuntu Release
The generated script refuses to run on a release other than the one it was built for. Regenerate it on the target machine.

#### Successful Output Example — `build-static-installer.sh --build-static`

```text
GPU drivers: Intel Graphics PPA (ppa:kobuk-team/intel-graphics)
NPU driver:  latest intel/linux-npu-driver GitHub release
Proxy configured for builder downloads (values not shown)
✓ Ubuntu 24.04 (noble) supported
  NPU tarball flavor: ubuntu2404
✓ curl is installed
✓ jq is installed
=== Checking Intel Graphics PPA ===
✓ PPA publishes noble: https://ppa.launchpadcontent.net/kobuk-team/intel-graphics/ubuntu/dists/noble/Release
=== Resolving latest intel/linux-npu-driver release ===
✓ NPU driver release: v1.38.0
  Asset:  linux-npu-driver-v1.38.0.20260910-34487311128-ubuntu2404.tar.gz
  URL:    https://github.com/intel/linux-npu-driver/releases/download/v1.38.0/linux-npu-driver-v1.38.0.20260910-34487311128-ubuntu2404.tar.gz
  SHA256: 1efcd4b6...
  - GPU source:     ppa:kobuk-team/intel-graphics
  - NPU driver:     v1.38.0 (linux-npu-driver-v1.38.0.20260910-34487311128-ubuntu2404.tar.gz)
🚀 Run: sudo -E ./setup-static-drivers.sh  (-E keeps proxy settings)
```

#### Successful Output Example — `verify_connectivity.sh`

```text
=== Driver Source Connectivity Test ===
Proxy configured (values not shown)
GITHUB_TOKEN: not set (optional; the builder falls back to the release page when rate limited)

1. Intel Graphics PPA (noble)...
   ✓ https://ppa.launchpadcontent.net/kobuk-team/intel-graphics/ubuntu/dists/noble/Release
   ✓ api.launchpad.net reachable (used by add-apt-repository for the signing key)
2. GitHub (intel/linux-npu-driver)...
   ⚠ GitHub API rate limited; trying the release page
   ✓ Release page: latest release v1.38.0

All driver sources reachable.
```

### Updating Drivers

GPU packages update with normal `sudo apt upgrade` from the PPA. To pick up a newer NPU driver release, regenerate and rerun:

```bash
./build-static-installer.sh --build-static
sudo -E ./setup-static-drivers.sh
```

### Environment Variables

- **`http_proxy` / `https_proxy` / `no_proxy`**: Proxy settings (use `sudo -E` to keep them as root)
- **`GITHUB_TOKEN`**: Optional GitHub token for higher API limits

---
## 🚀 Part 2: Software Setup (After Driver Installation)

> **⚠️ IMPORTANT: Driver Setup Required First**
> **⚠️ IMPORTANT: After installing drivers reboot the system before continuing to part 2.**
>
> Before running this software setup, ensure you have completed Part 1 (Driver Setup) above. The AI software components require proper Intel GPU and NPU drivers to function correctly.

### Overview

The Linux software setup uses `setup-software.sh` as the primary installer entry point.

It sets up a complete AI development environment optimized for Intel AI PCs by installing and configuring essential AI/ML frameworks, development tools, notebooks, and sample applications.

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
- **Additional Workshop Repositories**: Extra learning materials and sample projects

#### Target Installation Directory

All AI development materials are installed under `~/intel/` for organized project management.

### Software Installation Steps

#### Prerequisites

- **Operating System**: Ubuntu 24.04 LTS or newer
- **Hardware**: Intel AI PC with compatible GPU and NPU
- **Drivers**: Intel GPU/NPU drivers installed (Part 1 above)
- **Memory**: At least 16GB RAM (32GB+ recommended for large models)
- **Storage**: At least 10GB free space for all components
- **Build Tools**: The script automatically installs: cmake, build-essential, pkg-config, ninja-build, git, curl, wget, python3-pip, python3-venv, and Vulkan SDK

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
2. **OpenVINO GenAI 2026.1.0.0**: Sets up generative AI toolkit with Intel optimizations (version 2026.1.0.0)
3. **Ollama**: Installs local LLM runtime with Intel GPU acceleration

#### Phase 4: Development Tools

1. **Google Chrome**: Installs browser for web-based development
2. **VS Code**: Installs popular IDE for AI development
3. **Additional Repositories**: Clones supplementary workshop materials

### What Gets Installed Where

```text
~/intel/
├── openvino_notebooks/              # Main OpenVINO tutorial notebooks
├── openvino_genai_ubuntu24_2026.1.0.0_x86_64/  # OpenVINO GenAI 2026.1.0.0 toolkit
├── WorkShops_BootCamp/              # Additional workshop materials
├── llama.cpp/                       # llama.cpp with Vulkan support
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

# Run full diagnostic (from Linux_Software_Installation directory)
./Utilities/verify_connectivity.sh
```

#### Permission Issues
**Problem**: Script fails due to insufficient privileges

**Solution**: Run with sudo (drivers only; -E keeps proxy settings)
```bash
sudo -E ./setup-static-drivers.sh
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

> **AI agents:** to run the builder, drivers, and software phases from an agent harness such as Hermes or GitHub Copilot, see [`.agents/skills`](../.agents/skills/README.md). The skill adds a read-only preflight, per-phase consent, logged output under `~/.local/state/aipc-devkit/`, and an outcome report.

---

## 📚 Advanced Configuration

### Updating Components

#### Driver Updates

To update to newer driver versions:

```bash
cd Linux_Software_Installation

# GPU packages update via apt from the Intel PPA; regenerate to pick up a newer NPU release
./build-static-installer.sh --build-static
sudo -E ./setup-static-drivers.sh
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
