#!/usr/bin/env powershell
<#
.SYNOPSIS
    AI PC Dev Kit OVMS Agentic Launcher - Tool-Calling & Reasoning Support (v2026.2.1)

.DESCRIPTION
    Downloads OVMS v2026.2.1, configures models with tool/function calling and reasoning
    parser support, and starts the server in one command.
    Supports GPU/CPU/NPU with automatic tool_parser, reasoning_parser, and
    device-optimized model selection.

.PARAMETER Model
    Model shorthand or full OpenVINO/HuggingFace model ID.

    Shorthands:
      text             - Device-default text model
      image            - Device-default image model
      qwen3-8b         - OpenVINO/Qwen3-8B-int4-ov (GPU/CPU) or -cw-ov (NPU)
      qwen3-4b         - OpenVINO/Qwen3-4B-int4-ov
      qwen3-35b        - OpenVINO/Qwen3.6-35B-A3B-int4-ov (~20GB VRAM)
      phi4             - OpenVINO/Phi-4-mini-instruct-int4-ov
      mistral          - OpenVINO/Mistral-7B-Instruct-v0.3-int4-ov
      qwen3-coder-int4 - OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int4-ov (~19GB VRAM)
      qwen3-coder-int8 - OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int8-ov (~34GB VRAM)
      gpt-oss          - OpenVINO/gpt-oss-20b-int4-ov (~16GB VRAM)

.PARAMETER Target
    Target device: "GPU" (default), "CPU", or "NPU"

.PARAMETER Port
    REST API port (default: 8000)

.PARAMETER CacheDir
    Directory for compiled model cache files (default: .ovcache)

.PARAMETER ModelRepositoryPath
    Directory where models are stored (default: models)

.PARAMETER Pull
    Pre-download the model before starting the server

.PARAMETER ModelName
    Override the model name exposed via the API (auto-derived for known models)

.EXAMPLE
    .\ovms_agentic_setup.ps1
    # Qwen3.6-35B-A3B on GPU with qwen3coder tool parser + qwen3 reasoning parser (default)

.EXAMPLE
    .\ovms_agentic_setup.ps1 -Model phi4 -Target CPU
    # Phi-4-mini on CPU with phi4 tool parser

.EXAMPLE
    .\ovms_agentic_setup.ps1 -Model qwen3-8b -Target NPU
    # Qwen3-8B-cw on NPU with hermes3 tool parser (NPU-optimized)

.EXAMPLE
    .\ovms_agentic_setup.ps1 -Model mistral -Target GPU
    # Mistral-7B on GPU with mistral tool parser (auto-downloads chat_template.jinja)

.EXAMPLE
    .\ovms_agentic_setup.ps1 -Model qwen3-coder-int4 -Target GPU
    # Qwen3-Coder-30B-A3B (int4) on GPU - requires 19GB+ VRAM

.EXAMPLE
    .\ovms_agentic_setup.ps1 -Model gpt-oss -Target GPU
    # GPT-oss-20B on GPU with gptoss tool + reasoning parsers (~16GB VRAM)

.EXAMPLE
    .\ovms_agentic_setup.ps1 -Pull -Model qwen3-8b
    # Pre-download Qwen3-8B then start server on GPU

.EXAMPLE
    .\ovms_agentic_setup.ps1 -Model qwen3-35b -Target GPU
    # Qwen3.6-35B-A3B (int4) on GPU with qwen3coder tool parser + qwen3 reasoning parser (~20GB VRAM)
#>

param(
    [string]$Model = "text",
    [ValidateSet("GPU", "CPU", "NPU")]
    [string]$Target = "GPU",
    [int]$Port = 8000,
    [string]$CacheDir = ".ovcache",
    [string]$ModelRepositoryPath = "models",
    [string]$ModelName = $null,
    [switch]$Pull,
    [switch]$Test,
    [switch]$Help
)

# Color output functions
function Write-Info    { param([string]$Message) Write-Host "[INFO] $Message"  -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[OK] $Message"    -ForegroundColor Green }
function Write-Warning { param([string]$Message) Write-Host "[WARN] $Message"  -ForegroundColor Yellow }
function Write-Error   { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# ------------------------------------------------------------------------------
# Model aliases (shorthand -> full model ID)
# ------------------------------------------------------------------------------
$ModelAliases = @{
    "qwen3-8b"          = "OpenVINO/Qwen3-8B-int4-ov"
    "qwen3-4b"          = "OpenVINO/Qwen3-4B-int4-ov"
    "qwen3-35b"         = "OpenVINO/Qwen3.6-35B-A3B-int4-ov"
    "phi4"              = "OpenVINO/Phi-4-mini-instruct-int4-ov"
    "mistral"           = "OpenVINO/Mistral-7B-Instruct-v0.3-int4-ov"
    "qwen3-coder-int4"  = "OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int4-ov"
    "qwen3-coder-int8"  = "OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int8-ov"
    "gpt-oss"           = "OpenVINO/gpt-oss-20b-int4-ov"
}

# ------------------------------------------------------------------------------
# Default models per device (updated defaults)
# ------------------------------------------------------------------------------
$DefaultModels = @{
    "GPU" = @{
        "text"  = "OpenVINO/Qwen3.6-35B-A3B-int4-ov"
        "image" = "OpenVINO/FLUX.1-schnell-int4-ov"
    }
    "CPU" = @{
        "text"  = "OpenVINO/Phi-4-mini-instruct-int4-ov"
        "image" = "OpenVINO/stable-diffusion-v1-5-int8-ov"
    }
    "NPU" = @{
        "text"  = "OpenVINO/Qwen3-8B-int4-cw-ov"
        "image" = "OpenVINO/FLUX.1-schnell-int8-ov"
    }
}

function Get-SourceModel {
    param([string]$ModelInput, [string]$TargetDevice)

    # Device-relative shorthands
    if ($ModelInput -eq "text" -or $ModelInput -eq "image") {
        return $DefaultModels[$TargetDevice][$ModelInput]
    }

    # Named alias - redirect qwen3-8b to NPU-optimized variant on NPU
    if ($ModelAliases.ContainsKey($ModelInput)) {
        if ($TargetDevice -eq "NPU" -and $ModelInput -eq "qwen3-8b") {
            return "OpenVINO/Qwen3-8B-int4-cw-ov"
        }
        return $ModelAliases[$ModelInput]
    }

    # Full model ID passed directly
    return $ModelInput
}

function Get-ModelTask {
    param([string]$SourceModel)

    $imageModelPatterns = @(
        "*FLUX*", "*flux*", "*diffusion*", "*Dreamshaper*",
        "*SDXL*", "*stable-diffusion*", "*controlnet*",
        "*text-to-image*", "*image-generation*"
    )

    foreach ($pattern in $imageModelPatterns) {
        if ($SourceModel -like $pattern) {
            return "image_generation"
        }
    }
    return "text_generation"
}

# ------------------------------------------------------------------------------
# Returns model-specific configuration for agentic/tool-calling parameters
# ------------------------------------------------------------------------------
function Get-ModelConfig {
    param([string]$SourceModel, [string]$TargetDevice)

    $config = @{
        ToolParser           = $null    # --tool_parser
        ReasoningParser      = $null    # --reasoning_parser
        EnableToolGuidedGen  = $false   # --enable_tool_guided_generation true
        MaxPromptLen         = $null    # --max_prompt_len (NPU)
        PluginConfig         = $null    # --plugin_config (NPU)
        ModelName            = $null    # --model_name
        MoEWorkaround        = $false   # MOE_USE_MICRO_GEMM_PREFILL=0 env var
        ChatTemplateUrl      = $null    # URL for chat_template.jinja download
        EnablePrefixCaching     = $true    # --enable_prefix_caching true
        AllowedMediaDomains     = $null    # --allowed_media_domains
        CacheIntervalMultiplier = $null    # --cache_interval_multiplier (linear attention models)
    }

    if ($SourceModel -like "*Qwen3-Coder*") {
        $config.ToolParser    = "qwen3coder"
        $config.MoEWorkaround = $true
        $config.ModelName     = "Qwen3-Coder-30B-A3B-Instruct"
    }
    elseif ($SourceModel -like "*Qwen3.6-35B*") {
        $config.ToolParser              = "qwen3coder"
        $config.ReasoningParser         = "qwen3"
        $config.MoEWorkaround           = $true
        $config.EnableToolGuidedGen     = $true
        $config.AllowedMediaDomains     = "raw.githubusercontent.com"
        $config.ModelName               = "Qwen3.6-35B-A3B"
        $config.CacheIntervalMultiplier = 64   # recommended for long prompts (>20k tokens)
    }
    elseif ($SourceModel -like "OpenVINO/Qwen3-8B*") {
        $config.ToolParser = "hermes3"
        $config.ModelName  = "Qwen3-8B"
        if ($TargetDevice -eq "NPU" -or $SourceModel -like "*-cw-ov*") {
            $config.MaxPromptLen = 16384
            $config.PluginConfig = '{"NPUW_LLM_PREFILL_ATTENTION_HINT":"PYRAMID"}'
            # No reasoning parser on NPU
        } else {
            $config.ReasoningParser = "qwen3"
        }
    }
    elseif ($SourceModel -like "*Qwen3*") {
        # Other Qwen3 variants not matched above
        $config.ToolParser = "hermes3"
    }
    elseif ($SourceModel -like "*gpt-oss*") {
        $config.ToolParser      = "gptoss"
        $config.ReasoningParser = "gptoss"
        $config.ModelName       = "gpt-oss-20b"
    }
    elseif ($SourceModel -like "*Phi-4*") {
        $config.ToolParser      = "phi4"
        $config.ChatTemplateUrl = "https://raw.githubusercontent.com/vllm-project/vllm/refs/tags/v0.9.0/examples/tool_chat_template_phi4_mini.jinja"
    }
    elseif ($SourceModel -like "*Phi-3*") {
        $config.ToolParser = "phi4"
    }
    elseif ($SourceModel -like "*Mistral*") {
        $config.ToolParser      = "mistral"
        $config.ChatTemplateUrl = "https://raw.githubusercontent.com/vllm-project/vllm/refs/tags/v0.10.1.1/examples/tool_chat_template_mistral_parallel.jinja"
    }
    return $config
}

# ------------------------------------------------------------------------------
# Download chat_template.jinja for models that require one (Mistral, Phi-4)
# ------------------------------------------------------------------------------
function Install-ChatTemplate {
    param(
        [string]$SourceModel,
        [string]$RepoPath,
        [string]$TemplateUrl
    )

    $parts    = $SourceModel -split "/"
    $modelDir = Join-Path $RepoPath ($parts -join "\")
    $destFile = Join-Path $modelDir "chat_template.jinja"

    if (Test-Path $destFile) {
        Write-Success "Chat template already exists: $destFile"
        return
    }

    if (-not (Test-Path $modelDir)) {
        Write-Warning "Model directory not yet available: $modelDir"
        Write-Warning "Install chat template manually after model downloads:"
        Write-Warning "  curl -L -o `"$destFile`" `"$TemplateUrl`""
        return
    }

    Write-Info "Downloading chat template for $SourceModel..."
    try {
        Invoke-WebRequest -Uri $TemplateUrl -OutFile $destFile -UseBasicParsing
        Write-Success "Chat template installed: $destFile"
    }
    catch {
        Write-Warning "Failed to download chat template: $_"
        Write-Warning "Manual install: curl -L -o `"$destFile`" `"$TemplateUrl`""
    }
}

# ------------------------------------------------------------------------------
# Test functions - call these against a running OVMS server
# ------------------------------------------------------------------------------
function Test-OVMSConnection {
    param([int]$RestPort = 8000)

    Write-Info "Checking OVMS server connectivity on port $RestPort..."
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$RestPort/v3/models" `
            -Method GET -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Success "Server is running and reachable"
            Write-Info "Models endpoint response:"
            Write-Host $response.Content -ForegroundColor Gray
            return $true
        }
    }
    catch {
        Write-Warning "Server not reachable on port ${RestPort}: $_"
        return $false
    }
}

function Test-OVMSTextGeneration {
    param(
        [int]$RestPort = 8000,
        [string]$ModelId = "Qwen3-8B",
        [string]$Prompt = "What are the 3 main tourist attractions in Paris?",
        [int]$MaxTokens = 60
    )

    Write-Info "Testing text generation: model=$ModelId port=$RestPort"
    Write-Info "Prompt: $Prompt"

    $body = @{
        model       = $ModelId
        max_tokens  = $MaxTokens
        temperature = 0
        stream      = $false
        messages    = @(
            @{ role = "system"; content = "You are a helpful assistant." }
            @{ role = "user";   content = $Prompt }
        )
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-WebRequest `
            -Uri     "http://localhost:$RestPort/v3/chat/completions" `
            -Method  POST `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body    $body `
            -UseBasicParsing `
            -TimeoutSec 120 `
            -ErrorAction Stop

        $result = $response.Content | ConvertFrom-Json
        Write-Success "Text generation response:"
        Write-Host $result.choices[0].message.content -ForegroundColor White
        return $true
    }
    catch {
        Write-Warning "Text generation test failed: $_"
        return $false
    }
}

function Test-OVMSToolCall {
    param(
        [int]$RestPort = 8000,
        [string]$ModelId = "Qwen3-8B"
    )

    Write-Info "Testing tool/function calling: model=$ModelId port=$RestPort"

    $body = @{
        model       = $ModelId
        max_tokens  = 200
        temperature = 0
        stream      = $false
        tools       = @(
            @{
                type     = "function"
                function = @{
                    name        = "get_current_weather"
                    description = "Get the current weather in a given location"
                    parameters  = @{
                        type       = "object"
                        properties = @{
                            location = @{ type = "string"; description = "City name, e.g. Paris" }
                            unit     = @{ type = "string"; enum = @("celsius", "fahrenheit") }
                        }
                        required   = @("location")
                    }
                }
            }
        )
        messages    = @(
            @{ role = "user"; content = "What's the weather like in Paris right now?" }
        )
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-WebRequest `
            -Uri     "http://localhost:$RestPort/v3/chat/completions" `
            -Method  POST `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body    $body `
            -UseBasicParsing `
            -TimeoutSec 120 `
            -ErrorAction Stop

        $result = $response.Content | ConvertFrom-Json
        $finishReason = $result.choices[0].finish_reason
        Write-Success "Tool call test response (finish_reason: $finishReason):"
        if ($result.choices[0].message.tool_calls) {
            $toolCall = $result.choices[0].message.tool_calls[0]
            Write-Host "  Function: $($toolCall.function.name)" -ForegroundColor White
            Write-Host "  Args:     $($toolCall.function.arguments)" -ForegroundColor White
        } else {
            Write-Host $result.choices[0].message.content -ForegroundColor White
        }
        return $true
    }
    catch {
        Write-Warning "Tool call test failed: $_"
        return $false
    }
}

function Test-OVMSImageGeneration {
    param(
        [int]$RestPort = 8000,
        [string]$ModelId = "OpenVINO/FLUX.1-schnell-int4-ov",
        [string]$Prompt  = "A futuristic city skyline at sunset",
        [string]$OutFile = "ovms_test_image.png"
    )

    Write-Info "Testing image generation: model=$ModelId port=$RestPort"
    Write-Info "Prompt: $Prompt"

    $body = @{
        model   = $ModelId
        prompt  = $Prompt
        n       = 1
        size    = "512x512"
    } | ConvertTo-Json

    try {
        $response = Invoke-WebRequest `
            -Uri     "http://localhost:$RestPort/v3/images/generations" `
            -Method  POST `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body    $body `
            -UseBasicParsing `
            -TimeoutSec 300 `
            -ErrorAction Stop

        $result = $response.Content | ConvertFrom-Json
        Write-Success "Image generation succeeded"
        if ($result.data[0].b64_json) {
            $bytes = [Convert]::FromBase64String($result.data[0].b64_json)
            [System.IO.File]::WriteAllBytes((Join-Path (Get-Location) $OutFile), $bytes)
            Write-Success "Image saved to: $OutFile"
        } elseif ($result.data[0].url) {
            Write-Info "Image URL: $($result.data[0].url)"
        }
        return $true
    }
    catch {
        Write-Warning "Image generation test failed: $_"
        return $false
    }
}

function Invoke-OVMSTests {
    param(
        [int]$RestPort   = 8000,
        [string]$ModelId = $null,
        [string]$TaskType = "text_generation"
    )

    Write-Info "Running OVMS API tests on port $RestPort..."
    Write-Info "================================================"

    # 1. Connectivity
    $connected = Test-OVMSConnection -RestPort $RestPort
    if (-not $connected) {
        Write-Error "Server not reachable. Start it first with: .\ovms_agentic_setup.ps1 -Model <model>"
        return
    }

    if ($TaskType -eq "image_generation") {
        $id = if ($ModelId) { $ModelId } else { "OpenVINO/FLUX.1-schnell-int4-ov" }
        Test-OVMSImageGeneration -RestPort $RestPort -ModelId $id
    }
    else {
        $id = if ($ModelId) { $ModelId } else { "Qwen3-8B" }
        # 2. Basic text generation
        Test-OVMSTextGeneration -RestPort $RestPort -ModelId $id
        Write-Info ""
        # 3. Tool/function calling
        Test-OVMSToolCall -RestPort $RestPort -ModelId $id
    }

    Write-Info ""
    Write-Success "All tests completed"
}

# ------------------------------------------------------------------------------
# Pre-download a model using ovms --pull
# ------------------------------------------------------------------------------
function Invoke-ModelPull {
    param(
        [string]$SourceModel,
        [string]$RepoPath
    )

    Write-Info "Pre-downloading model: $SourceModel..."
    & ".\ovms\ovms.exe" --pull --model_repository_path $RepoPath --source_model $SourceModel --task text_generation

    if ($LASTEXITCODE -eq 0) {
        Write-Success "Model downloaded: $SourceModel"
    } else {
        Write-Warning "Model pull finished with exit code $LASTEXITCODE"
    }
}

# ------------------------------------------------------------------------------
# Download and initialise OVMS (unchanged from original)
# ------------------------------------------------------------------------------
function Initialize-OVMS {
    Write-Info "Setting up OVMS..."

    $ovmsDir = "ovms"
    $ovmsExe = Join-Path $ovmsDir "ovms.exe"

    if (Test-Path $ovmsExe) {
        Write-Success "OVMS already available"

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

# ------------------------------------------------------------------------------
# Start the OVMS server with full agentic parameter support
# ------------------------------------------------------------------------------
function Start-OVMSServer {
    param(
        [string]$SourceModel,
        [string]$TargetDevice,
        [int]$RestPort,
        [string]$CacheDirPath,
        [string]$RepoPath,
        [string]$ModelNameOverride
    )

    $taskType    = Get-ModelTask   -SourceModel $SourceModel
    $modelConfig = Get-ModelConfig -SourceModel $SourceModel -TargetDevice $TargetDevice

    $effectiveModelName = if ($ModelNameOverride)         { $ModelNameOverride }
                          elseif ($modelConfig.ModelName) { $modelConfig.ModelName }
                          else                            { $null }

    Write-Info "Starting OVMS Server..."
    Write-Info "  Model:     $SourceModel"
    Write-Info "  Target:    $TargetDevice"
    Write-Info "  Port:      $RestPort"
    Write-Info "  Task:      $taskType"
    if ($modelConfig.ToolParser)           { Write-Info "  Tool Parser:         $($modelConfig.ToolParser)" }
    if ($modelConfig.ReasoningParser)      { Write-Info "  Reasoning Parser:    $($modelConfig.ReasoningParser)" }
    if ($effectiveModelName)               { Write-Info "  Model Name (API):    $effectiveModelName" }
    if ($modelConfig.AllowedMediaDomains)      { Write-Info "  Allowed Domains:     $($modelConfig.AllowedMediaDomains)" }
    if ($modelConfig.CacheIntervalMultiplier)   { Write-Info "  Cache Interval Mult: $($modelConfig.CacheIntervalMultiplier)" }
    Write-Success "API will be available at: http://localhost:$RestPort/v3"
    Write-Info ""

    # Apply MoE env var workaround for Qwen3-Coder and similar MoE models
    if ($modelConfig.MoEWorkaround) {
        Write-Warning "Applying MoE workaround: MOE_USE_MICRO_GEMM_PREFILL=0"
        $env:MOE_USE_MICRO_GEMM_PREFILL = "0"
    }

    # Ensure model repository and cache directories exist
    foreach ($dir in @($RepoPath, $CacheDirPath)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    # Install chat template for models that require one (Mistral, Phi-4)
    if ($modelConfig.ChatTemplateUrl) {
        Install-ChatTemplate -SourceModel $SourceModel -RepoPath $RepoPath -TemplateUrl $modelConfig.ChatTemplateUrl
    }

    Write-Info "Starting server (model will auto-download if not cached)..."
    Write-Warning "Press Ctrl+C to stop the server"
    Write-Info ""

    try {
        if ($taskType -eq "image_generation") {
            Write-Info "Using image generation mode with --task image_generation..."
            & ".\ovms\ovms.exe" `
                --rest_port $RestPort `
                --model_repository_path $RepoPath `
                --task image_generation `
                --source_model $SourceModel `
                --target_device $TargetDevice `
                --log_level INFO
        }
        else {
            Write-Info "Using text generation mode with agentic tool support..."

            # Build argument list dynamically so only applicable flags are passed
            $ovmsArgs = [System.Collections.Generic.List[object]]::new()
            $ovmsArgs.AddRange([object[]]@(
                "--source_model",          $SourceModel,
                "--model_repository_path", $RepoPath,
                "--rest_port",             $RestPort,
                "--target_device",         $TargetDevice,
                "--task",                  "text_generation",
                "--cache_size",            4,
                "--cache_dir",             $CacheDirPath,
                "--log_level",             "INFO"
            ))

            if ($modelConfig.ToolParser) {
                $ovmsArgs.AddRange([object[]]@("--tool_parser", $modelConfig.ToolParser))
            }
            if ($modelConfig.ReasoningParser) {
                $ovmsArgs.AddRange([object[]]@("--reasoning_parser", $modelConfig.ReasoningParser))
            }
            if ($modelConfig.EnableToolGuidedGen) {
                $ovmsArgs.AddRange([object[]]@("--enable_tool_guided_generation", "true"))
            }
            if ($modelConfig.EnablePrefixCaching) {
                $ovmsArgs.AddRange([object[]]@("--enable_prefix_caching", "true"))
            }
            if ($modelConfig.MaxPromptLen) {
                $ovmsArgs.AddRange([object[]]@("--max_prompt_len", $modelConfig.MaxPromptLen))
            }
            if ($modelConfig.PluginConfig) {
                # Escape inner quotes so Windows command-line parsing preserves the JSON
                $escapedConfig = $modelConfig.PluginConfig -replace '"', '\"'
                $ovmsArgs.AddRange([object[]]@("--plugin_config", $escapedConfig))
            }
            if ($effectiveModelName) {
                $ovmsArgs.AddRange([object[]]@("--model_name", $effectiveModelName))
            }
            if ($modelConfig.AllowedMediaDomains) {
                $ovmsArgs.AddRange([object[]]@("--allowed_media_domains", $modelConfig.AllowedMediaDomains))
            }
            if ($modelConfig.CacheIntervalMultiplier) {
                $ovmsArgs.AddRange([object[]]@("--cache_interval_multiplier", $modelConfig.CacheIntervalMultiplier))
            }

            & ".\ovms\ovms.exe" @ovmsArgs
        }
    }
    catch {
        Write-Error "Failed to start OVMS server: $_"
        exit 1
    }
    finally {
        if ($modelConfig.MoEWorkaround) {
            Remove-Item env:MOE_USE_MICRO_GEMM_PREFILL -ErrorAction SilentlyContinue
        }
    }
}

# ==============================================================================
# Main execution
# ==============================================================================
Write-Info "AI PC Dev Kit OVMS Agentic Launcher (v2026.2.1)"
Write-Info "================================================"

# Show help if requested
if ($Help) {
    Write-Host ""
    Write-Host "AI PC Dev Kit OVMS Agentic Launcher (v2026.2.1)" -ForegroundColor Yellow
    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "USAGE:" -ForegroundColor Green
    Write-Host "  .\ovms_agentic_setup.ps1 [-Model <shorthand|model_id>] [-Target <GPU|CPU|NPU>] [-Port <port>]" -ForegroundColor White
    Write-Host "                           [-CacheDir <dir>] [-ModelRepositoryPath <dir>] [-Pull] [-ModelName <name>]" -ForegroundColor White
    Write-Host ""
    Write-Host "PARAMETERS:" -ForegroundColor Green
    Write-Host "  -Model               'text' (default), 'image', shorthand, or full model ID" -ForegroundColor White
    Write-Host "  -Target              'GPU' (default), 'CPU', or 'NPU'" -ForegroundColor White
    Write-Host "  -Port                REST API port (default: 8000)" -ForegroundColor White
    Write-Host "  -CacheDir            Compiled model cache directory (default: .ovcache)" -ForegroundColor White
    Write-Host "  -ModelRepositoryPath Model storage directory (default: models)" -ForegroundColor White
    Write-Host "  -Pull                Pre-download model before starting server" -ForegroundColor White
    Write-Host "  -ModelName           Override API-facing model name" -ForegroundColor White
    Write-Host "  -Test                Test a running server (no server start)" -ForegroundColor White
    Write-Host "  -Help                Show this help message" -ForegroundColor White
    Write-Host ""
    Write-Host "TEST USAGE:" -ForegroundColor Green
    Write-Host "  .\ovms_agentic_setup.ps1 -Test                         # Test default Qwen3-8B on port 8000" -ForegroundColor White
    Write-Host "  .\ovms_agentic_setup.ps1 -Test -Model phi4 -Port 9000  # Test Phi-4 on port 9000" -ForegroundColor White
    Write-Host "  .\ovms_agentic_setup.ps1 -Test -Model image             # Test image generation endpoint" -ForegroundColor White
    Write-Host ""
    Write-Host "TEST FUNCTIONS (call directly in PowerShell after starting server):" -ForegroundColor Green
    Write-Host "  Test-OVMSConnection        -RestPort 8000" -ForegroundColor White
    Write-Host "  Test-OVMSTextGeneration    -RestPort 8000 -ModelId 'Qwen3-8B'" -ForegroundColor White
    Write-Host "  Test-OVMSToolCall          -RestPort 8000 -ModelId 'Qwen3-8B'" -ForegroundColor White
    Write-Host "  Test-OVMSImageGeneration   -RestPort 8000 -ModelId 'OpenVINO/FLUX.1-schnell-int4-ov'" -ForegroundColor White
    Write-Host "  Invoke-OVMSTests           -RestPort 8000 -ModelId 'Qwen3-8B' -TaskType text_generation" -ForegroundColor White
    Write-Host ""
    Write-Host "MODEL SHORTHANDS:" -ForegroundColor Green
    Write-Host "  text             Device-default text model" -ForegroundColor White
    Write-Host "  image            Device-default image model" -ForegroundColor White
    Write-Host "  qwen3-8b         OpenVINO/Qwen3-8B-int4-ov (GPU/CPU) | -cw-ov (NPU)" -ForegroundColor White
    Write-Host "  qwen3-4b         OpenVINO/Qwen3-4B-int4-ov" -ForegroundColor White
    Write-Host "  phi4             OpenVINO/Phi-4-mini-instruct-int4-ov" -ForegroundColor White
    Write-Host "  mistral          OpenVINO/Mistral-7B-Instruct-v0.3-int4-ov" -ForegroundColor White
    Write-Host "  qwen3-coder-int4 OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int4-ov (~19GB VRAM)" -ForegroundColor White
    Write-Host "  qwen3-coder-int8 OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int8-ov (~34GB VRAM)" -ForegroundColor White
    Write-Host "  gpt-oss          OpenVINO/gpt-oss-20b-int4-ov (~16GB VRAM)" -ForegroundColor White
    Write-Host "  qwen3-35b        OpenVINO/Qwen3.6-35B-A3B-int4-ov (~20GB VRAM)" -ForegroundColor White
    Write-Host ""
    Write-Host "DEFAULT MODELS:" -ForegroundColor Green
    Write-Host "  GPU  text:  OpenVINO/Qwen3.6-35B-A3B-int4-ov    (qwen3coder tool + qwen3 reasoning, MoE)" -ForegroundColor White
    Write-Host "  CPU  text:  OpenVINO/Phi-4-mini-instruct-int4-ov (phi4 tool parser)" -ForegroundColor White
    Write-Host "  NPU  text:  OpenVINO/Qwen3-8B-int4-cw-ov         (hermes3 tool, NPU-optimized)" -ForegroundColor White
    Write-Host "  GPU  image: OpenVINO/FLUX.1-schnell-int4-ov" -ForegroundColor White
    Write-Host "  CPU  image: OpenVINO/stable-diffusion-v1-5-int8-ov" -ForegroundColor White
    Write-Host "  NPU  image: OpenVINO/FLUX.1-schnell-int8-ov" -ForegroundColor White
    Write-Host ""
    Write-Host "TOOL PARSERS (auto-detected per model):" -ForegroundColor Green
    Write-Host "  hermes3    Qwen3-8B (+ qwen3 reasoning parser on GPU/CPU)" -ForegroundColor White
    Write-Host "  hermes3    Qwen3-4B, Qwen/Qwen3-*" -ForegroundColor White
    Write-Host "  qwen3coder Qwen3-Coder (+ MoE env var workaround)" -ForegroundColor White
    Write-Host "  phi4       Phi-4-mini, Phi-3.5 models" -ForegroundColor White
    Write-Host "  mistral    Mistral models (+ auto chat_template.jinja download)" -ForegroundColor White
    Write-Host "  gptoss     GPT-oss models (+ gptoss reasoning parser)" -ForegroundColor White
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Green
    Write-Host "  .\ovms_agentic_setup.ps1" -ForegroundColor Cyan
    Write-Host "    # Qwen3-8B on GPU (default)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  .\ovms_agentic_setup.ps1 -Model phi4 -Target CPU" -ForegroundColor Cyan
    Write-Host "    # Phi-4-mini on CPU with phi4 tool parser" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  .\ovms_agentic_setup.ps1 -Model qwen3-8b -Target NPU" -ForegroundColor Cyan
    Write-Host "    # Qwen3-8B-cw on NPU (NPU-optimized, max_prompt_len 16384)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  .\ovms_agentic_setup.ps1 -Model mistral -Target GPU" -ForegroundColor Cyan
    Write-Host "    # Mistral-7B with mistral tool parser + chat template auto-download" -ForegroundColor Gray
    Write-Host ""

    Write-Host "  .\ovms_agentic_setup.ps1 -Model qwen3-coder-int4 -Target GPU" -ForegroundColor Cyan
    Write-Host "    # Qwen3-Coder-30B int4 on GPU - requires 19GB+ VRAM" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  .\ovms_agentic_setup.ps1 -Model gpt-oss -Target GPU" -ForegroundColor Cyan
    Write-Host "    # GPT-oss-20B with gptoss tool + reasoning parsers - requires 16GB+ VRAM" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  .\ovms_agentic_setup.ps1 -Model qwen3-35b -Target GPU" -ForegroundColor Cyan
    Write-Host "    # Qwen3.6-35B-A3B int4 on GPU - requires ~20GB VRAM" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  .\ovms_agentic_setup.ps1 -Pull -Model qwen3-8b" -ForegroundColor Cyan
    Write-Host "    # Pre-download Qwen3-8B then start server" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  .\ovms_agentic_setup.ps1 -Model 'OpenVINO/Qwen3-8B-int4-ov' -Target GPU -Port 9000" -ForegroundColor Cyan
    Write-Host "    # Full model ID with custom port" -ForegroundColor Gray
    Write-Host ""
    Write-Host "API ACCESS:" -ForegroundColor Green
    Write-Host "  Once started, API available at: http://localhost:<port>/v3" -ForegroundColor White
    Write-Host ""
    Write-Host "BUILT-IN HELP:" -ForegroundColor Green
    Write-Host "  Get-Help .\ovms_agentic_setup.ps1" -ForegroundColor Cyan
    Write-Host "  Get-Help .\ovms_agentic_setup.ps1 -Examples" -ForegroundColor Cyan
    Write-Host "  Get-Help .\ovms_agentic_setup.ps1 -Detailed" -ForegroundColor Cyan
    Write-Host ""
    return
}

# Run tests against an already-running server (-Test mode, no server start)
if ($Test) {
    $resolvedModel  = Get-SourceModel -ModelInput $Model -TargetDevice $Target
    $resolvedTask   = Get-ModelTask   -SourceModel $resolvedModel
    $resolvedConfig = Get-ModelConfig -SourceModel $resolvedModel -TargetDevice $Target
    $apiModelName   = if ($ModelName)                  { $ModelName }
                      elseif ($resolvedConfig.ModelName) { $resolvedConfig.ModelName }
                      else                               { $resolvedModel }
    Invoke-OVMSTests -RestPort $Port -ModelId $apiModelName -TaskType $resolvedTask
    exit 0
}

# Setup OVMS if not already present
$ovmsExe = Initialize-OVMS

# Resolve model ID from shorthand or alias
$sourceModel = Get-SourceModel -ModelInput $Model -TargetDevice $Target

if (-not $sourceModel) {
    Write-Error "Could not resolve model '$Model' for target '$Target'"
    Write-Info "Run .\ovms_agentic_setup.ps1 -Help to see available models"
    exit 1
}

# Pre-download model if -Pull was specified
if ($Pull) {
    $taskTypeForPull = Get-ModelTask -SourceModel $sourceModel
    if ($taskTypeForPull -eq "text_generation") {
        Invoke-ModelPull -SourceModel $sourceModel -RepoPath $ModelRepositoryPath
        # Try to install chat template now that model directory should exist
        $pullConfig = Get-ModelConfig -SourceModel $sourceModel -TargetDevice $Target
        if ($pullConfig.ChatTemplateUrl) {
            Install-ChatTemplate -SourceModel $sourceModel -RepoPath $ModelRepositoryPath -TemplateUrl $pullConfig.ChatTemplateUrl
        }
    } else {
        Write-Info "Skipping --pull for image generation model (not supported)"
    }
}

# Start the server
Start-OVMSServer `
    -SourceModel       $sourceModel `
    -TargetDevice      $Target `
    -RestPort          $Port `
    -CacheDirPath      $CacheDir `
    -RepoPath          $ModelRepositoryPath `
    -ModelNameOverride $ModelName
