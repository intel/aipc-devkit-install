#!/bin/bash

# Copyright (C) 2025 Intel Corporation
# SPDX-License-Identifier: MIT License

set -e

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
        LATEST_VERSION=$(apt-cache policy "$PACKAGE" | grep Candidate | awk '{print $2}')
        
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

install_vulkan_sdk(){
    echo -e "\n# Installing Vulkan SDK"
    # Add Vulkan repository key
    wget -qO- https://packages.lunarg.com/lunarg-signing-key-pub.asc | sudo tee /etc/apt/trusted.gpg.d/lunarg.asc
    
    # Add Vulkan repository for Ubuntu 24.04 (Noble)
    sudo wget -qO /etc/apt/sources.list.d/lunarg-vulkan-noble.list http://packages.lunarg.com/vulkan/lunarg-vulkan-noble.list
    
    # Update package list and install Vulkan SDK
    sudo apt update
    sudo apt install -y vulkan-sdk
    
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
    if [ ! -d "./openvino_notebooks" ]; then
        cd ~/intel
        git clone https://github.com/openvinotoolkit/openvino_notebooks.git
        cd openvino_notebooks
        python3 -m venv venv
        source venv/bin/activate
        pip install -r requirements.txt
        # Create ipykernel for this environment
        pip install ipykernel
        python -m ipykernel install --user --name=openvino_notebooks --display-name="OpenVINO Notebooks"
        deactivate
    else
        echo "./openvino_notebooks already exists"
    fi
    echo -e "\n# Build OpenVINO™ notebook complete"
}

install_openvino_notebook2(){

    echo -e "\n# Git clone OpenVINO™ notebooks 2"
    if [ ! -d "./openvino_build_deploy" ]; then
        cd ~/intel
        git clone https://github.com/openvinotoolkit/openvino_build_deploy.git
        cd openvino_build_deploy/workshops/MSBuild2025 
        python3 -m venv venv
        source venv/bin/activate
        pip install openvino==2025.3.0 ultralytics==8.3.120
        # Create ipykernel for this environment
        pip install ipykernel
        python -m ipykernel install --user --name=openvino_build_deploy --display-name="OpenVINO Build Deploy"
        deactivate
    else
        echo "./openvino_build_deploy already exists"
    fi
    echo -e "\n# Build OpenVINO™ notebook2 complete"
}

install_openvino_genai(){

    echo -e "\n# OpenVINO™ GenAI"
    if [ ! -d "./openvino_genai_ubuntu24_2025.3.0.0_x86_64" ]; then
        cd ~/intel
        curl -L https://storage.openvinotoolkit.org/repositories/openvino_genai/packages/2025.3/linux/openvino_genai_ubuntu24_2025.3.0.0_x86_64.tar.gz --output openvino_genai_2025.3.0.0.tgz
        tar -xf openvino_genai_2025.3.0.0.tgz

        cd openvino_genai_u*
        sudo -E ./install_dependencies/install_openvino_dependencies.sh
        source setupvars.sh
        cd samples/cpp
        ./build_samples.sh
    else
        echo "./openvino_genai_ubuntu24_2025.3.0.0_x86_64 already exists"
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
        cmake -B build -DGGML_VULKAN=1 -DLLAMA_CURL=OFF
        cmake --build build --config Release
        
        echo "$S_VALID llama.cpp native built with Vulkan support"
    else
        echo "llama.cpp already exists"
    fi
    
    # Install llama-cpp-python with Vulkan support
    echo -e "\n# Installing llama-cpp-python with Vulkan support"
    if [ ! -d "./llamacpp_python_env" ]; then
        cd ~/intel
        python3 -m venv llamacpp_python_env
        source llamacpp_python_env/bin/activate
        
        # Set environment variable for Vulkan support
        export CMAKE_ARGS="-DGGML_VULKAN=ON -DLLAMA_CURL=OFF"
        pip install llama-cpp-python
        
        # Create ipykernel for this environment
        pip install ipykernel
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
    
    # Start Ollama service
    ollama serve &
    sleep 5
    
    # Pull a model for testing
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
    if [ ! -d "./AI-PC-Samples" ]; then
        cd ~/intel
        git clone https://github.com/intel/AI-PC-Samples.git
        
        # Create virtual environment for AI-PC-Samples if it has requirements
        if [ -f "./AI-PC-Samples/AI-Travel-Agent/requirements.txt" ]; then
            cd AI-PC-Samples
            python3 -m venv venv
            source venv/bin/activate
            pip install -r AI-Travel-Agent/requirements.txt
            # Create ipykernel for this environment
            pip install ipykernel
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
    sudo sh -c 'echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list'
    sudo apt update
    sudo apt install code
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
    verify_dependencies
    install_uv
    install_openvino_notebook
    install_openvino_notebook2
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
    echo "- OpenVINO Build Deploy"  
    echo "- LlamaCPP Python (Vulkan)"
    echo "- AI PC Samples (if AI-Travel-Agent/requirements.txt exists)"
    echo -e "\nTo list all available kernels, run: jupyter kernelspec list"
    
    echo -e "\n# Virtual Environment Activation Commands"
    echo "To activate each virtual environment, use the following commands:"
    echo ""
    echo "1. OpenVINO Notebooks:"
    echo "   cd ~/intel/openvino_notebooks && source venv/bin/activate"
    echo ""
    echo "2. OpenVINO Build Deploy:"
    echo "   cd ~/intel/openvino_build_deploy/workshops/MSBuild2025 && source venv/bin/activate"
    echo ""
    echo "3. LlamaCPP Python (Vulkan):"
    echo "   cd ~/intel && source llamacpp_python_env/bin/activate"
    echo ""
    if [ -d "./AI-PC-Samples" ] && [ -f "./AI-PC-Samples/AI-Travel-Agent/requirements.txt" ]; then
        echo "4. AI PC Samples:"
        echo "   cd ~/intel/AI-PC-Samples && source venv/bin/activate"
        echo ""
    fi
    echo "5. OpenVINO GenAI (setup environment variables):"
    echo "   cd ~/intel/openvino_genai_u* && source setupvars.sh"
    echo ""
    echo "Note: To deactivate any virtual environment, simply run: deactivate"
}

setup
