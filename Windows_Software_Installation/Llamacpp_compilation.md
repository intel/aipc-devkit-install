# Llama.cpp Compilation Guide for Windows

This guide provides four different methods to compile and install llama.cpp with GPU acceleration on Windows systems.

## 📋 Prerequisites

### Required Software
- **Python 3.12+** with pip
- **Visual Studio 2019/2022** (Community, Professional, or Enterprise)
- **CMake 3.16+**
- **Ninja Build System** (for SYCL builds)

### GPU-Specific Requirements

#### For SYCL (Intel GPU)
- **Intel OneAPI Toolkit** (includes Intel C++ Compiler and SYCL runtime)
- **Intel GPU drivers** (latest version)

#### For Vulkan (Intel GPU)
- **Vulkan SDK** (latest version)
  [Vulkan SDK Download](https://vulkan.lunarg.com/sdk/home)
- **GPU drivers** with Vulkan support

## 🚀 Compilation Methods

### 1. Llama.cpp Native SYCL Compilation


```powershell
# Step 1: Set up Intel OneAPI environment
cmd.exe "/K" '"C:\Program Files (x86)\Intel\oneAPI\setvars.bat" && powershell'

# Step 2: Configure build with CMake
cmake -B build -G "Ninja" -DGGML_SYCL=ON -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=icx -DCMAKE_BUILD_TYPE=Release -DGGML_SYCL_F16=ON -DLLAMA_CURL=OFF

# Step 3: Build the project
cmake --build build --config Release -j
```

**Output:** Native executables with Intel GPU acceleration via SYCL

---

### 2. Llama.cpp Native Vulkan Compilation

 Cross-platform GPU support, maximum compatibility

```powershell
# Step 1: Configure build with CMake
cmake -B build -DGGML_VULKAN=ON -DLLAMA_CURL=OFF

# Step 2: Build the project
cmake --build build --config Release -j
```

**Output:** Native executables with Vulkan GPU acceleration

---

### 3. Llama.cpp Python Vulkan Compilation

Python integration with Vulkan GPU acceleration

```powershell
# Single command installation
$env:CMAKE_ARGS="-DGGML_VULKAN=on"; $env:FORCE_CMAKE="1"; pip install llama-cpp-python==0.3.8 -U --force --no-cache-dir --verbose
```

**Output:** Python package with Vulkan GPU acceleration

---

### 4. Llama.cpp Python SYCL Compilation
 Python integration with Intel GPU acceleration

```powershell
# Set up Intel OneAPI environment and install
cmd.exe "/K" '"C:\Program Files (x86)\Intel\oneAPI\setvars.bat" && powershell'; $env:CMAKE_GENERATOR="Ninja"; $env:CMAKE_C_COMPILER="cl"; $env:CMAKE_CXX_COMPILER="icx"; $env:CXX="icx"; $env:CC="cl"; $env:CMAKE_ARGS="-DGGML_SYCL=ON -DGGML_SYCL_F16=ON -DCMAKE_CXX_COMPILER=icx -DCMAKE_C_COMPILER=cl"; pip install llama-cpp-python==0.3.8 -U --force --no-cache-dir --verbose
```

**Output:** Python package with Intel GPU acceleration via SYCL



## 🛠️ Build Configuration Options

### Common CMake Options

| Option | Description | Values |
|--------|-------------|--------|
| `DGGML_SYCL=ON` | Enable Intel SYCL support | ON/OFF |
| `DGGML_VULKAN=ON` | Enable Vulkan support | ON/OFF |
| `DGGML_SYCL_F16=ON` | Enable FP16 for SYCL | ON/OFF |
| `DLLAMA_CURL=OFF` | Disable CURL dependency | ON/OFF |
| `DCMAKE_BUILD_TYPE=Release` | Optimization level | Debug/Release |

### Environment Variables for Python Builds

| Variable | Purpose | Example |
|----------|---------|---------|
| `CMAKE_ARGS` | CMake configuration | `"-DGGML_VULKAN=ON"` |
| `CMAKE_GENERATOR` | Build system | `"Ninja"` |
| `CMAKE_C_COMPILER` | C compiler | `"cl"` |
| `CMAKE_CXX_COMPILER` | C++ compiler | `"icx"` |
| `FORCE_CMAKE` | Force CMake rebuild | `"1"` |

## 🔧 Troubleshooting

### Common Issues

#### SYCL Build Issues
- **Error:** `icx: command not found`
  - **Solution:** Run Intel OneAPI setvars.bat first
- **Error:** `CMAKE_CXX_COMPILER-NOTFOUND`
  - **Solution:** Ensure Visual Studio and Intel OneAPI are installed

#### Vulkan Build Issues
- **Error:** `vulkan/vulkan.h: No such file`
  - **Solution:** Install Vulkan SDK
- **Error:** `VK_VERSION_1_2 not defined`
  - **Solution:** Update Vulkan SDK to latest version

#### Python Package Issues
- **Error:** `Microsoft Visual C++ 14.0 is required`
  - **Solution:** Install Visual Studio Build Tools
- **Error:** `CMAKE_ARGS not recognized`
  - **Solution:** Use PowerShell, not Command Prompt

### Verification Commands

```powershell
# Check SYCL devices
sycl-ls

# Check Vulkan support
vulkaninfo --summary

# Test Python installation
python -c "import llama_cpp; print('Version:', llama_cpp.__version__)"

# Performance test
python -c "from llama_cpp import Llama; llm = Llama('model.gguf', n_gpu_layers=33); print('GPU acceleration active')"
```

## 📁 Directory Structure

After successful compilation:

```
├── build/                  # Native builds output
│   ├── bin/               # Executables (main, quantize, etc.)
│   └── lib/               # Libraries
└── models/                # Your GGUF model files
```

## 🎯 Choosing the Right Method

### For Development
- **C++ Projects:** Native builds for Intel GPUs
- **Python ML:** Python packages for Intel GPUs



## 📚 Additional Resources

- [Llama.cpp GitHub Repository](https://github.com/ggerganov/llama.cpp)
- [Intel OneAPI Documentation](https://www.intel.com/content/www/us/en/developer/tools/oneapi/toolkits.html)
- [Vulkan SDK Download](https://vulkan.lunarg.com/sdk/home)
- [Python llama-cpp-python Package](https://github.com/abetlen/llama-cpp-python)

## 📝 Notes

- SYCL builds require Intel OneAPI and work best with Intel GPUs
- Vulkan builds offer broader GPU compatibility
- Python packages add ~10-15% overhead compared to native builds
- Always use the latest GPU drivers for optimal performance
- F16 precision (SYCL_F16=ON) can improve performance on supported hardware
