#!/bin/bash

# Ubuntu Linux Script for Compiling Ollama from Sources with Vulkan SDK
# This script checks for Vulkan installation and compiles Ollama with Vulkan support

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Vulkan installation
check_vulkan() {
    print_status "Checking for existing Vulkan installation..."
    
    if command_exists vulkaninfo; then
        print_success "vulkaninfo found, checking Vulkan capabilities..."
        if vulkaninfo --summary >/dev/null 2>&1; then
            print_success "Vulkan is properly installed and working"
            return 0
        else
            print_warning "vulkaninfo exists but Vulkan may not be working properly"
            return 1
        fi
    else
        print_warning "vulkaninfo not found, Vulkan SDK needs to be installed"
        return 1
    fi
}

# Function to install Vulkan SDK
install_vulkan_sdk() {
    print_status "Installing Vulkan SDK..."
    
    # Add LunarG repository for Vulkan SDK
    wget -qO - https://packages.lunarg.com/lunarg-signing-key-pub.asc | sudo apt-key add -
    sudo wget -qO /etc/apt/sources.list.d/lunarg-vulkan-$(lsb_release -cs).list \
        https://packages.lunarg.com/vulkan/lunarg-vulkan-$(lsb_release -cs).list
    
    sudo apt update
    
    # Install Vulkan SDK (core runtime only)
    sudo apt install -y vulkan-sdk
    
    # Verify installation
    if vulkaninfo --summary >/dev/null 2>&1; then
        print_success "Vulkan SDK installed successfully"
    else
        print_error "Vulkan SDK installation failed or not working properly"
        exit 1
    fi
}

# Function to install system dependencies
install_dependencies() {
    print_status "Installing system dependencies..."
    
    # Update package list
    sudo apt update
    
    # Install essential build tools and dependencies
    sudo apt install -y \
        xz-utils \
        build-essential \
        cmake \
        ninja-build \
        pkg-config \
        git \
        curl \
        wget \
        python3 \
        python-is-python3 \
        bison \
        clang-format
    
    # Install graphics and development libraries
    sudo apt install -y \
        libglm-dev \
        libxcb-dri3-0 \
        libxcb-present0 \
        libpciaccess0 \
        libpng-dev \
        libxcb-keysyms1-dev \
        libxcb-dri3-dev \
        libx11-dev \
        libx11-xcb-dev \
        libwayland-dev \
        libxrandr-dev \
        libxcb-randr0-dev \
        libxcb-ewmh-dev \
        liblz4-dev \
        libzstd-dev \
        libxml2-dev \
        wayland-protocols \
        python3-jsonschema
    
    # Install Qt development libraries (optional, for GUI support)
    sudo apt install -y qtbase5-dev qt6-base-dev || print_warning "Qt libraries installation failed, continuing without Qt support"
    
    print_success "System dependencies installed successfully"
}

# Function to install or update Go
install_go() {
    print_status "Checking Go installation..."
    
    if command_exists go; then
        GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
        print_status "Go $GO_VERSION is already installed"
        
        # Check if Go version is recent enough (1.19+)
        if [ "$(printf '%s\n' "1.19" "$GO_VERSION" | sort -V | head -n1)" = "1.19" ]; then
            print_success "Go version is sufficient"
            return 0
        else
            print_warning "Go version is too old, updating..."
        fi
    fi
    
    print_status "Installing/updating Go..."
    
    # Remove old Go installation if exists
    sudo rm -rf /usr/local/go
    
    # Download and install latest Go
    GO_LATEST=$(curl -s https://golang.org/VERSION?m=text)
    wget "https://golang.org/dl/${GO_LATEST}.linux-amd64.tar.gz"
    sudo tar -C /usr/local -xzf "${GO_LATEST}.linux-amd64.tar.gz"
    rm "${GO_LATEST}.linux-amd64.tar.gz"
    
    # Add Go to PATH if not already present
    if ! grep -q "/usr/local/go/bin" ~/.bashrc; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
        export PATH=$PATH:/usr/local/go/bin
    fi
    
    print_success "Go installed successfully"
}

# Function to clone or update Ollama repository
setup_ollama_repo() {
    print_status "Setting up Ollama repository..."
    
    if [ -d "ollama" ]; then
        print_status "Ollama directory exists, updating..."
        cd ollama
        git pull origin main
        cd ..
    else
        print_status "Cloning Ollama repository..."
        git clone https://github.com/ollama/ollama.git
    fi
    
    print_success "Ollama repository ready"
}

# Function to build Ollama with Vulkan support
build_ollama() {
    print_status "Building Ollama with Vulkan support..."
    
    cd ollama
    
    # Set environment variables for Vulkan support
    export VK_SDK_PATH=/usr
    export VULKAN_SDK=/usr
    export CGO_CFLAGS="-I/usr/include"
    export CGO_LDFLAGS="-L/usr/lib/x86_64-linux-gnu -lvulkan"
    
    # Clean previous builds
    if [ -d "build" ]; then
        rm -rf build
    fi
    
    # Configure with CMake
    print_status "Configuring build with CMake..."
    cmake -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLAMA_VULKAN=ON \
        -DLLAMA_CUDA=OFF \
        -DLLAMA_METAL=OFF
    
    # Build with all available cores
    CORES=$(nproc)
    print_status "Building with $CORES cores..."
    cmake --build build --config Release --parallel $CORES
    
    # Build Go components
    print_status "Building Go components..."
    go build -tags vulkan
    
    print_success "Ollama built successfully with Vulkan support"
    
    cd ..
}

# Function to test Ollama installation
test_ollama() {
    print_status "Testing Ollama installation..."
    
    cd ollama
    
    # Check if ollama binary was created
    if [ -f "./ollama" ]; then
        print_success "Ollama binary found"
        
        # Test basic functionality
        ./ollama --version
        print_success "Ollama version check passed"
    else
        print_error "Ollama binary not found!"
        exit 1
    fi
    
    cd ..
}

# Function to create startup script
create_startup_script() {
    print_status "Creating startup script..."
    
    cat > start_ollama.sh << 'EOF'
#!/bin/bash

# Startup script for Ollama with Vulkan support
cd ollama

echo "Starting Ollama server with Vulkan support..."
echo "Server will be available at http://localhost:11434"
echo "Press Ctrl+C to stop the server"
echo ""

# Set Vulkan environment variables
export VK_SDK_PATH=/usr
export VULKAN_SDK=/usr

# Start Ollama server
./ollama serve
EOF
    
    chmod +x start_ollama.sh
    
    cat > test_ollama.sh << 'EOF'
#!/bin/bash

# Test script for Ollama
cd ollama

echo "Testing Ollama with a small model..."
echo "This will download and run llama3.2:1b model"
echo ""

./ollama pull llama3.2:1b
./ollama run llama3.2:1b "Hello, how are you?"
EOF
    
    chmod +x test_ollama.sh
    
    print_success "Startup scripts created: start_ollama.sh and test_ollama.sh"
}

# Main execution
main() {
    print_status "Starting Ollama compilation with Vulkan SDK on Ubuntu Linux"
    print_status "================================================="
    
    # Check if running on Ubuntu
    if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        print_warning "This script is designed for Ubuntu. It may work on other Debian-based systems."
    fi
    
    # Check for Vulkan and install if needed
    if ! check_vulkan; then
        install_vulkan_sdk
    fi
    
    # Install system dependencies
    install_dependencies
    
    # Install Go
    install_go
    
    # Setup Ollama repository
    setup_ollama_repo
    
    # Build Ollama
    build_ollama
    
    # Test installation
    test_ollama
    
    # Create startup scripts
    create_startup_script
    
    print_success "================================================="
    print_success "Ollama compilation completed successfully!"
    print_success "================================================="
    echo ""
    print_status "Next steps:"
    echo "  1. Run './start_ollama.sh' to start the Ollama server"
    echo "  2. In another terminal, run './test_ollama.sh' to test with a model"
    echo "  3. Or manually run: cd ollama && ./ollama pull llama3.2 && ./ollama run llama3.2"
    echo ""
    print_status "Server will be available at: http://localhost:11434"
    print_status "Vulkan acceleration is enabled for better performance"
}

# Run main function
main "$@"
