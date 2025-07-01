#!/bin/bash

# Copyright (C) 2024 Intel Corporation
# SPDX-License-Identifier: Apache-2.0 

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

verify_dependencies(){
    echo -e "\n# Verifying dependencies"
    DEPENDENCIES_PACKAGES=(
        python3-pip
        python3-venv
    )
    install_packages "${DEPENDENCIES_PACKAGES[@]}"
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
        pip install openvino==2025.1.0 ultralytics==8.3.120
    else
        echo "./openvino_build_deploy already exists"
    fi
    echo -e "\n# Build OpenVINO™ notebook2 complete"
}

install_openvino_genai(){

    echo -e "\n# OpenVINO™ GenAI"
    if [ ! -d "./openvino_genai_ubuntu24_2025.2.0.0_x86_64" ]; then
        cd ~/intel
        curl -L https://storage.openvinotoolkit.org/repositories/openvino_genai/packages/2025.2/linux/openvino_genai_ubuntu24_2025.2.0.0_x86_64.tar.gz --output openvino_genai_2025.2.0.0.tgz
        tar -xf openvino_genai_2025.2.0.0.tgz

        cd openvino_genai_u*
        sudo -E ./install_dependencies/install_openvino_dependencies.sh
        source setupvars.sh
        cd samples/cpp
        ./build_samples.sh
    else
        echo "./openvino_genai_ubuntu24_2025.2.0.0_x86_64 already exists"
    fi
    echo -e "\n# Build OpenVINO™ GenAI complete"
}

install_ollama(){

    echo -e "\n# Install Ollama"
    cd ~/intel
    curl -fsSL https://ollama.com/install.sh | sh
    sleep 5
    ollama pull llama3.2:1b
    #ollama run llama3.2:1b
    #What is OpenVINO?
    #/bye
    echo -e "\n# Ollama install complete"
}

install_chrome(){

    echo -e "\n# Install chrome"
    cd ~/intel
    wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    sudo dpkg -i google-chrome-stable_current_amd64.deb
    echo -e "\n# chrome install complete"
}

install_other_notebooks(){

    echo -e "\n# Git clone Other notebooks "
    if [ ! -d "./webnn_workshop" ]; then
        cd ~/intel
        git clone https://github.com/IntelSoftware/webnn_workshop
        git clone https://github.com/intel/AI-PC-Samples.git
    else
        echo "./webnn-workshop already exists"
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
    if [ ! -d "/home/optane/intel" ]; then
        echo -d "~/intel"
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
    install_ollama
    install_chrome
    install_other_notebooks
    install_vs_code

    echo -e "\n# Status"
    echo "$S_VALID AI PC DevKit Installed"
}

setup
