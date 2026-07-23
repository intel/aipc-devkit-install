#!/usr/bin/env powershell
<#
.SYNOPSIS
    Simple One-Command OVMS Script - Download and Start Models (v2026.2.1)
    
.DESCRIPTION
    Downloads OVMS v2026.2.1, downloads models, and starts the server in one command.
    Supports GPU/CPU/NPU devices with automatic model selection and required task parameters.
    
.PARAMETER Model
    Model type: "text" (default), "image", or full OpenVINO model name
    
.PARAMETER Target
    Target device: "GPU" (default), "CPU", or "NPU"
    
.PARAMETER Port
    REST API port (default: 8000)
    
.EXAMPLE
    .\start_ovms_simple_v2026.0.ps1
    # Starts Phi-3 text model on GPU
    
.EXAMPLE
    .\start_ovms_simple_v2026.0.ps1 -Target NPU
    # Starts NPU-optimized Phi-3 on NPU
    
.EXAMPLE
    .\start_ovms_simple_v2026.0.ps1 -Model image
    # Starts FLUX image generation on GPU
    
.EXAMPLE
    .\ovms_setup.ps1 -Model "OpenVINO/Mistral-7B-Instruct-v0.2-int4-cw-ov" -Target CPU
    # Starts custom model on CPU

.EXAMPLE
    .\ovms_setup.ps1 -Model qwen3-35b -Target GPU
    # Starts Qwen3.6-35B-A3B on GPU (~20GB VRAM) — basic text generation, no tool/reasoning parsers
#>

param(
    [string]$Model = "text",
    [ValidateSet("GPU", "CPU", "NPU")]
    [string]$Target = "GPU",
    [int]$Port = 8000,
    [switch]$Help
)

# Color output functions
function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-Warning { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# Model shorthands
$ModelAliases = @{
    "qwen3-35b" = "OpenVINO/Qwen3.6-35B-A3B-int4-ov"
}

# Default models for each device
$DefaultModels = @{
    "GPU" = @{
        "text" = "OpenVINO/Phi-3.5-mini-instruct-int4-ov"
        "image" = "OpenVINO/FLUX.1-schnell-int4-ov"
    }
    "CPU" = @{
        "text" = "OpenVINO/Phi-3.5-mini-instruct-int4-ov"
        "image" = "OpenVINO/stable-diffusion-v1-5-int8-ov"
    }
    "NPU" = @{
        "text" = "OpenVINO/Phi-3.5-mini-instruct-int4-cw-ov"
        "image" = "OpenVINO/FLUX.1-schnell-int8-ov"
    }
}

function Get-SourceModel {
    param([string]$ModelInput, [string]$TargetDevice)
    
    # Device-relative shorthands
    if ($ModelInput -eq "text" -or $ModelInput -eq "image") {
        return $DefaultModels[$TargetDevice][$ModelInput]
    }

    # Named alias
    if ($ModelAliases.ContainsKey($ModelInput)) {
        return $ModelAliases[$ModelInput]
    }
    
    # Full model name passed directly
    return $ModelInput
}

function Get-ModelTask {
    param([string]$SourceModel)
    
    # Determine task type based on model name patterns
    $imageModelPatterns = @(
        "*FLUX*",
        "*flux*",
        "*diffusion*",
        "*Dreamshaper*",
        "*SDXL*",
        "*stable-diffusion*",
        "*controlnet*",
        "*text-to-image*",
        "*image-generation*"
    )
    
    foreach ($pattern in $imageModelPatterns) {
        if ($SourceModel -like $pattern) {
            return "image_generation"
        }
    }
    
    # Default to text generation for all other models
    return "text_generation"
}

function Initialize-OVMS {
    Write-Info "Setting up OVMS..."
    
    $ovmsDir = "ovms"
    $ovmsExe = Join-Path $ovmsDir "ovms.exe"
    
    if (Test-Path $ovmsExe) {
        Write-Success "OVMS already available"
        
        # Always run setupvars to ensure environment is properly initialized
        $setupVars = Join-Path $ovmsDir "setupvars.ps1"
        if (Test-Path $setupVars) {
            Write-Info "Initializing OpenVINO Model Server environment..."
            try {
                $setupOutput = & $setupVars 2>&1
                if ($setupOutput -like "*Environment Initialized*") {
                    Write-Success "OpenVINO Model Server Environment Initialized"
                } else {
                    Write-Info "Environment setup completed"
                }
            }
            catch {
                Write-Warning "Environment setup had issues, but continuing..."
            }
        }
        
        return $ovmsExe
    }
    
    Write-Info "Downloading OVMS v2026.2.1..."
    $ovmsUrl = "https://github.com/openvinotoolkit/model_server/releases/download/v2026.2.1/ovms_windows_2026.2.1_python_on.zip"
    $ovmsZip = "ovms.zip"
    
    try {
        Invoke-WebRequest -Uri $ovmsUrl -OutFile $ovmsZip -UseBasicParsing
        Expand-Archive -Path $ovmsZip -DestinationPath "." -Force
        Remove-Item $ovmsZip -Force -ErrorAction SilentlyContinue
        
        if (Test-Path $ovmsExe) {
            Write-Success "OVMS downloaded and extracted"
            
            # Run setupvars to initialize environment
            $setupVars = Join-Path $ovmsDir "setupvars.ps1"
            if (Test-Path $setupVars) {
                Write-Info "Initializing OpenVINO Model Server environment..."
                try {
                    $setupOutput = & $setupVars 2>&1
                    if ($setupOutput -like "*Environment Initialized*") {
                        Write-Success "OpenVINO Model Server Environment Initialized"
                    } else {
                        Write-Info "Environment setup completed"
                    }
                }
                catch {
                    Write-Warning "Environment setup had issues, but continuing..."
                }
            }
            
            return $ovmsExe
        } else {
            throw "OVMS extraction failed"
        }
    }
    catch {
        Write-Error "Failed to setup OVMS: $_"
        exit 1
    }
}

function Start-OVMSServer {
    param([string]$SourceModel, [string]$TargetDevice, [int]$RestPort)
    
    Write-Info "Starting OVMS Server..."
    Write-Info "Model: $SourceModel"
    Write-Info "Target: $TargetDevice"
    Write-Info "Port: $RestPort"
    Write-Success "API will be available at: http://localhost:$RestPort/v3"
    Write-Info ""
    
    # Ensure models directory exists
    if (-not (Test-Path "models")) {
        New-Item -ItemType Directory -Path "models" -Force | Out-Null
    }
    
    # Determine the task type for the model
    $taskType = Get-ModelTask -SourceModel $SourceModel
    
    Write-Info "Detected task type: $taskType"
    Write-Info "Starting server (model will download automatically if not cached)..."
    Write-Warning "Press Ctrl+C to stop the server"
    Write-Info ""
    
    # MoE workaround for Qwen3.6-35B and similar models
    $isMoE = ($SourceModel -like "*Qwen3.6-35B*")
    if ($isMoE) {
        Write-Warning "Applying MoE workaround: MOE_USE_MICRO_GEMM_PREFILL=0"
        $env:MOE_USE_MICRO_GEMM_PREFILL = "0"
    }

    try {
        if ($taskType -eq "image_generation") {
            Write-Info "Using image generation mode with --task image_generation..."
            & ".\ovms\ovms.exe" --rest_port $RestPort --model_repository_path "models" --task image_generation --source_model $SourceModel --target_device $TargetDevice --log_level INFO
        } else {
            Write-Info "Using text generation mode with --task text_generation..."
            if ($isMoE) {
                # Qwen3.6-35B: linear attention model needs cache_interval_multiplier
                & ".\ovms\ovms.exe" --source_model $SourceModel --model_repository_path "models" --rest_port $RestPort --target_device $TargetDevice --task text_generation --cache_size 4 --cache_interval_multiplier 64 --allowed_media_domains raw.githubusercontent.com --log_level INFO
            } else {
                & ".\ovms\ovms.exe" --source_model $SourceModel --model_repository_path "models" --rest_port $RestPort --target_device $TargetDevice --task text_generation --cache_size 4 --log_level INFO
            }
        }
    }
    catch {
        Write-Error "Failed to start OVMS server: $_"
        exit 1
    }
    finally {
        if ($isMoE) {
            Remove-Item env:MOE_USE_MICRO_GEMM_PREFILL -ErrorAction SilentlyContinue
        }
    }
}

# Main execution
Write-Info "Simple OVMS Launcher (v2026.2.1)"
Write-Info "================================"

# Show help if requested
if ($Help) {
    Write-Host ""
    Write-Host "Simple OVMS Launcher - One Command Setup (v2026.2.1)" -ForegroundColor Yellow
    Write-Host "====================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "USAGE:" -ForegroundColor Green
    Write-Host "  .\start_ovms_simple_v2026.0.ps1 [-Model <text|image|model_name>] [-Target <GPU|CPU|NPU>] [-Port <port>]" -ForegroundColor White
    Write-Host ""
    Write-Host "PARAMETERS:" -ForegroundColor Green
    Write-Host "  -Model   : 'text' (default), 'image', or full OpenVINO model name" -ForegroundColor White
    Write-Host "  -Target  : 'GPU' (default), 'CPU', or 'NPU'" -ForegroundColor White
    Write-Host "  -Port    : REST API port (default: 8000)" -ForegroundColor White
    Write-Host "  -Help    : Show this help message" -ForegroundColor White
    Write-Host ""
    Write-Host "MODEL SHORTHANDS:" -ForegroundColor Green
    Write-Host "  text       - Device-default text model" -ForegroundColor White
    Write-Host "  image      - Device-default image model" -ForegroundColor White
    Write-Host "  qwen3-35b  - OpenVINO/Qwen3.6-35B-A3B-int4-ov (~20GB VRAM, MoE)" -ForegroundColor White
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Green
    Write-Host "  .\ovms_setup.ps1" -ForegroundColor Cyan
    Write-Host "    # Start Phi-3.5 text model on GPU" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  .\ovms_setup.ps1 -Target CPU" -ForegroundColor Cyan
    Write-Host "    # Start Phi-3.5 text model on CPU" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  .\ovms_setup.ps1 -Target NPU" -ForegroundColor Cyan
    Write-Host "    # Start NPU-optimized Phi-3.5 on NPU" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  .\ovms_setup.ps1 -Model image" -ForegroundColor Cyan
    Write-Host "    # Start FLUX image generation on GPU" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  .\ovms_setup.ps1 -Model qwen3-35b -Target GPU" -ForegroundColor Cyan
    Write-Host "    # Start Qwen3.6-35B-A3B on GPU (~20GB VRAM) — basic text generation" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  .\ovms_setup.ps1 -Model 'OpenVINO/Mistral-7B-Instruct-v0.2-int4-cw-ov' -Target NPU" -ForegroundColor Cyan
    Write-Host "    # Start custom Mistral model on NPU" -ForegroundColor Gray
    Write-Host ""
    Write-Host "DEFAULT MODELS:" -ForegroundColor Green
    Write-Host "  Text (GPU/CPU): OpenVINO/Phi-3.5-mini-instruct-int4-ov" -ForegroundColor White
    Write-Host "  Text (NPU):     OpenVINO/Phi-3.5-mini-instruct-int4-cw-ov" -ForegroundColor White
    Write-Host "  qwen3-35b:      OpenVINO/Qwen3.6-35B-A3B-int4-ov (MoE workaround + cache_interval_multiplier 64)" -ForegroundColor White
    Write-Host "  Image (GPU):    OpenVINO/FLUX.1-schnell-int4-ov" -ForegroundColor White
    Write-Host "  Image (CPU):    OpenVINO/stable-diffusion-v1-5-int8-ov" -ForegroundColor White
    Write-Host "  Image (NPU):    OpenVINO/FLUX.1-schnell-int8-ov" -ForegroundColor White
    Write-Host ""
    Write-Host "TASK AUTO-DETECTION:" -ForegroundColor Green
    Write-Host "  Image models (--task image_generation): *FLUX*, *diffusion*, *SDXL*, etc." -ForegroundColor White
    Write-Host "  Text models (--task text_generation): All other models (Phi-3, Mistral, etc.)" -ForegroundColor White
    Write-Host ""
    Write-Host "BUILT-IN HELP:" -ForegroundColor Green
    Write-Host "  Get-Help .\start_ovms_simple_v2026.0.ps1" -ForegroundColor Cyan
    Write-Host "  Get-Help .\start_ovms_simple_v2026.0.ps1 -Examples" -ForegroundColor Cyan
    Write-Host "  Get-Help .\start_ovms_simple_v2026.0.ps1 -Detailed" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "API ACCESS:" -ForegroundColor Green
    Write-Host "  Once started, API available at: http://localhost:<port>/v3" -ForegroundColor White
    Write-Host ""
    return
}

# Setup OVMS if needed
$ovmsExe = Initialize-OVMS

# Resolve model name
$sourceModel = Get-SourceModel -ModelInput $Model -TargetDevice $Target

if (-not $sourceModel) {
    Write-Error "Invalid model/target combination"
    Write-Info "Available models:"
    Write-Info "  text      - Text generation (Phi-3.5)"
    Write-Info "  image     - Image generation (FLUX/Stable Diffusion)"
    Write-Info "  qwen3-35b - Qwen3.6-35B-A3B text generation (~20GB VRAM)"
    Write-Info "  Or provide full OpenVINO model name"
    exit 1
}

# Start the server
Start-OVMSServer -SourceModel $sourceModel -TargetDevice $Target -RestPort $Port
