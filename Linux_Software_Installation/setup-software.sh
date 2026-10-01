#!/bin/bash

# Copyright (C) 2025 Intel Corporation
# SPDX-License-Identifier: MIT License

set -e
set -o pipefail

# symbol
S_VALID="✓"
CURRENT_DIRECTORY=$(pwd)

# verify current user
if [ "$EUID" -eq 0 ]; then
    echo "Must not run with sudo or root user"
    exit 1
fi

install_packages(){
    local PACKAGES=("$@")
    local INSTALL_REQUIRED=0
    for PACKAGE in "${PACKAGES[@]}"; do
        INSTALLED_VERSION=$(dpkg-query -W -f='${Version}' "$PACKAGE" 2>/dev/null || true)
        LATEST_VERSION=$(apt-cache policy "$PACKAGE" | awk '/Candidate:/ {print $2}')
        
        if [ -z "$INSTALLED_VERSION" ] || [ "$INSTALLED_VERSION" != "$LATEST_VERSION" ]; then
            echo "$PACKAGE is not installed or not the latest version."
            INSTALL_REQUIRED=1
        fi
    done
    if [ $INSTALL_REQUIRED -eq 1 ]; then
        sudo -E apt update
        sudo -E apt install -y "${PACKAGES[@]}"
    fi
}

configure_ubuntu_2604_compute_runtime_and_groups(){
    if [ ! -f /etc/os-release ]; then
        return
    fi

    . /etc/os-release
    if [[ "${VERSION_ID:-}" != 26.04* ]]; then
        return
    fi

    echo -e "\n# Ubuntu 26.04 detected: configuring compute runtime and user groups"

    install_packages intel-opencl-icd clinfo

    local CURRENT_USER
    local GROUPS_UPDATED=0
    CURRENT_USER="$(whoami)"

    for GROUP in video render; do
        if id -nG "$CURRENT_USER" | grep -w "$GROUP" >/dev/null; then
            echo "$S_VALID User '$CURRENT_USER' is already in '$GROUP' group"
        else
            echo "Adding user '$CURRENT_USER' to '$GROUP' group"
            sudo usermod -aG "$GROUP" "$CURRENT_USER"
            GROUPS_UPDATED=1
        fi
    done

    if [ "$GROUPS_UPDATED" -eq 1 ]; then
        echo "Group membership updated. Log out and back in for changes to take effect."
    fi
}

install_vulkan_sdk(){
    echo -e "\n# Installing Vulkan SDK"
    if [ ! -f /etc/os-release ]; then
        echo "Unable to detect OS release information"
        return 1
    fi

    . /etc/os-release
    if [[ "${VERSION_ID:-}" == 26.04* ]]; then
        local SDK_VERSION="1.4.350.0"
        local SDK_URL="https://sdk.lunarg.com/sdk/download/${SDK_VERSION}/linux/vulkansdk-linux-x86_64-${SDK_VERSION}.tar.xz"
        local SDK_ARCHIVE
        local SDK_DIR
        SDK_ARCHIVE=$(mktemp /tmp/vulkansdk-linux-x86_64-XXXXXX.tar.xz)
        SDK_DIR=$(mktemp -d /tmp/vulkansdk-linux-x86_64-XXXXXX)

        trap 'rm -f "$SDK_ARCHIVE"; rm -rf "$SDK_DIR"' RETURN

        wget -qO "$SDK_ARCHIVE" "$SDK_URL"
        tar -xJf "$SDK_ARCHIVE" -C "$SDK_DIR"

        if [ -x "$SDK_DIR/vulkansdk" ]; then
            "$SDK_DIR/vulkansdk" glslang vulkan-tools --maxjobs
        elif [ -x "$SDK_DIR/vulkan" ]; then
            "$SDK_DIR/vulkan" glslang vulkan-tools --maxjobs
        else
            echo "Could not find the Vulkan SDK installer binary in $SDK_DIR"
            return 1
        fi
    else
        # Add Vulkan repository key
        wget -qO- https://packages.lunarg.com/lunarg-signing-key-pub.asc | sudo tee /etc/apt/trusted.gpg.d/lunarg.asc

        # Add Vulkan repository for Ubuntu 24.04 (Noble)
        sudo wget -qO /etc/apt/sources.list.d/lunarg-vulkan-noble.list http://packages.lunarg.com/vulkan/lunarg-vulkan-noble.list

        # Update package list and install Vulkan SDK
        sudo apt update
        sudo apt install -y vulkan-sdk spirv-headers
        # LunarG may package the Vulkan headers separately from the loader.
        if [ ! -f /usr/include/vulkan/vulkan.h ]; then
            sudo apt install -y vulkan-headers
        fi
    fi

    echo "$S_VALID Vulkan SDK installed"
}

verify_dependencies(){
    echo -e "\n# Verifying dependencies"
    DEPENDENCIES_PACKAGES=(
        python3-pip
        python3-venv
        cmake
        build-essential
        pkg-config
        git
        curl
        wget
        ninja-build
        gpg
        libssl-dev
        ccache
        python3-numpy
        ocl-icd-opencl-dev
        opencl-clhpp-headers
        libopencv-dev
    )
    install_packages "${DEPENDENCIES_PACKAGES[@]}"
    install_vulkan_sdk
    echo "$S_VALID Dependencies installed"
}

install_uv(){
    echo -e "\n# Installing UV"
    if ! command -v uv &> /dev/null; then
        wget -qO- https://astral.sh/uv/install.sh | sh
        # Add UV to PATH for current session
        export PATH="$HOME/.local/bin:$PATH"
        # Verify installation
        if command -v uv &> /dev/null; then
            echo "$S_VALID UV installed successfully"
        else
            echo "Warning: UV installation may require a shell restart to update PATH"
        fi
    else
        echo "$S_VALID UV is already installed"
    fi
}

install_openvino_notebook(){

    echo -e "\n# Git clone OpenVINO™ notebooks"
    cd ~/intel
    if [ ! -d "./openvino_notebooks" ]; then
        cd ~/intel
        git clone https://github.com/openvinotoolkit/openvino_notebooks.git
        cd openvino_notebooks
        python3 -m venv venv
        source venv/bin/activate
        python -m pip install -r requirements.txt openvino
        # Create ipykernel for this environment
        python -m pip install ipykernel
        python -m ipykernel install --user --name=openvino_notebooks --display-name="OpenVINO Notebooks"
        deactivate
    else
        echo "./openvino_notebooks already exists"
    fi
    echo -e "\n# Build OpenVINO™ notebook complete"
}

install_openvino_genai(){

    echo -e "\n# OpenVINO™ GenAI"
    cd ~/intel
    if [ ! -d "./openvino_genai_ubuntu24_2026.1.0.0_x86_64" ]; then
        cd ~/intel
        curl -fL https://storage.openvinotoolkit.org/repositories/openvino_genai/packages/2026.1/linux/openvino_genai_ubuntu24_2026.1.0.0_x86_64.tar.gz --output openvino_genai_2026.1.0.0.tgz
        tar -xf openvino_genai_2026.1.0.0.tgz

        cd openvino_genai_ubuntu24_2026.1.0.0_x86_64
        sudo -E ./install_dependencies/install_openvino_dependencies.sh
        source setupvars.sh
        cd samples/cpp
        ./build_samples.sh
    else
        echo "./openvino_genai_ubuntu24_2026.1.0.0_x86_64 already exists"
    fi
    echo -e "\n# Build OpenVINO™ GenAI complete"
}

install_llamacpp(){
    echo -e "\n# Install llama.cpp with Vulkan support"
    
    cd ~/intel
    if [ ! -d "./llama.cpp" ]; then
        # Check Vulkan support
        echo "Checking Vulkan support..."
        vulkaninfo
        
        # Clone and build llama.cpp with Vulkan support
        git clone https://github.com/ggerganov/llama.cpp.git
        cd llama.cpp
        
        # Build with Vulkan support
        cmake -S . -B build -G Ninja -DGGML_VULKAN=ON -DLLAMA_CURL=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=ON
        cmake --build build --config Release
        
        echo "$S_VALID llama.cpp native built with Vulkan support"
    else
        echo "llama.cpp already exists"
    fi
    
    # Install llama-cpp-python with Vulkan support
    echo -e "\n# Installing llama-cpp-python with Vulkan support"
    if [ ! -d "$HOME/intel/llamacpp_python_env" ]; then
        cd ~/intel
        python3 -m venv llamacpp_python_env
        source llamacpp_python_env/bin/activate
        
        # Set environment variable for Vulkan support
        CMAKE_ARGS="-DGGML_VULKAN=ON -DLLAMA_CURL=OFF" \
        python -m pip install --no-cache-dir --no-binary=llama-cpp-python llama-cpp-python
        
        # Create ipykernel for this environment
        python -m pip install ipykernel
        python -m ipykernel install --user --name=llamacpp_python --display-name="LlamaCPP Python (Vulkan)"
        deactivate
        echo "$S_VALID llama-cpp-python installed with Vulkan support"
    else
        echo "llamacpp_python_env already exists"
    fi
    
    echo -e "\n# llama.cpp installation complete"
}

install_ollama(){

    echo -e "\n# Install Ollama (regular version)"
    cd ~/intel
    
    # Install regular Ollama using the official installer
    curl -fsSL https://ollama.com/install.sh | sh
    
    # Set OLLAMA_VULKAN=1 for the current session
    export OLLAMA_VULKAN=1

    # Persist in ~/.bashrc for future interactive sessions
    if ! grep -q 'OLLAMA_VULKAN' ~/.bashrc 2>/dev/null; then
        echo 'export OLLAMA_VULKAN=1' >> ~/.bashrc
    fi
    # OLLAMA_VULKAN was already exported above; do not source interactive config.

    # Persist system-wide in /etc/environment
    if ! grep -q 'OLLAMA_VULKAN' /etc/environment 2>/dev/null; then
        echo 'OLLAMA_VULKAN=1' | sudo tee -a /etc/environment
    fi

    # Set for the systemd ollama service (so the daemon picks it up too)
    sudo mkdir -p /etc/systemd/system/ollama.service.d
    echo -e '[Service]\nEnvironment="OLLAMA_VULKAN=1"' | sudo tee /etc/systemd/system/ollama.service.d/vulkan.conf
    sudo systemctl daemon-reload
    sudo systemctl restart ollama

    # Wait for the systemd service to be ready, then pull a test model
    local OLLAMA_READY=0
    local ATTEMPT
    for ATTEMPT in {1..30}; do
        if ollama list >/dev/null 2>&1; then
            OLLAMA_READY=1
            break
        fi
        sleep 1
    done
    if [ "$OLLAMA_READY" -ne 1 ]; then
        echo "Ollama did not become ready after 30 checks."
        echo "Inspect: systemctl status ollama"
        echo "Logs: journalctl -u ollama -n 50 --no-pager"
        return 1
    fi
    ollama pull llama3.2:1b
    
    echo -e "\n# Ollama install complete"
}

install_chrome(){

    echo -e "\n# Install chrome"
    cd ~/intel
    wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    sudo apt -y install ./google-chrome-stable_current_amd64.deb
    echo -e "\n# chrome install complete"
}

install_other_notebooks(){

    echo -e "\n# Git clone Other notebooks "
    cd ~/intel
    if [ ! -d "./AI-PC-Samples" ]; then
        cd ~/intel
        git clone https://github.com/intel/AI-PC-Samples.git
        
        # Create virtual environment for AI-PC-Samples if it has requirements
        if [ -f "./AI-PC-Samples/AI-Travel-Agent/requirements.txt" ]; then
            cd AI-PC-Samples
            python3 -m venv venv
            source venv/bin/activate
            python -m pip install -r AI-Travel-Agent/requirements.txt
            # Create ipykernel for this environment
            python -m pip install ipykernel
            python -m ipykernel install --user --name=ai_pc_samples --display-name="AI PC Samples"
            deactivate
            cd ..
        fi
    else
        echo "./AI-PC-Samples already exists"
    fi
    echo -e "\n# Clone other notebooks complete"
}

install_vs_code(){

    echo -e "\n# Install VS Code"
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
    sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
    sudo sh -c 'echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
    sudo apt update
    sudo apt install -y code
    echo -e "\n# VS Code complete"
}

setup() {
    if [ ! -d "/home/$(whoami)/intel" ]; then
        echo "Creating ~/intel directory"
        mkdir ~/intel
    else
        echo "~/intel already exists"
    fi
    cd ~/intel
    configure_ubuntu_2604_compute_runtime_and_groups
    verify_dependencies
    install_uv
    install_openvino_notebook
    install_openvino_genai
    install_llamacpp
    install_ollama
    install_chrome
    install_other_notebooks
    install_vs_code

    echo -e "\n# Status"
    echo "$S_VALID AI PC DevKit Installed"
    echo -e "\nInstalled Jupyter kernels:"
    echo "- OpenVINO Notebooks"
    echo "- LlamaCPP Python (Vulkan)"
    echo "- AI PC Samples (if AI-Travel-Agent/requirements.txt exists)"
    echo -e "\nTo list all available kernels, run: jupyter kernelspec list"
    
    echo -e "\n# Virtual Environment Activation Commands"
    echo "To activate each virtual environment, use the following commands:"
    echo ""
    echo "1. OpenVINO Notebooks:"
    echo "   cd ~/intel/openvino_notebooks && source venv/bin/activate"
    echo ""
    echo "2. LlamaCPP Python (Vulkan):"
    echo "   cd ~/intel && source llamacpp_python_env/bin/activate"
    echo ""
    if [ -d "./AI-PC-Samples" ] && [ -f "./AI-PC-Samples/AI-Travel-Agent/requirements.txt" ]; then
        echo "3. AI PC Samples:"
        echo "   cd ~/intel/AI-PC-Samples && source venv/bin/activate"
        echo ""
    fi
    echo "4. OpenVINO GenAI (setup environment variables):"
    echo "   cd ~/intel/openvino_genai_u* && source setupvars.sh"
    echo ""
    echo "Note: To deactivate any virtual environment, simply run: deactivate"
}

setup
