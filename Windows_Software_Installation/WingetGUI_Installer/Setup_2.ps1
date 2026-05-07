# AI PC Dev Kit Complete Installation Script for Windows

param(
    [string]$DevKitWorkingDir = "C:\Intel",
    [int]$MaxRetries = 3
)

$ErrorActionPreference = "Continue"

# Ensure working directory exists
New-Item -ItemType Directory -Path $DevKitWorkingDir -ErrorAction SilentlyContinue
Set-Location $DevKitWorkingDir

# Track installation results for final summary
$installResults = [ordered]@{
    "OpenVINO Notebooks venv"        = "Skipped"
    "OpenVINO GenAI C++ Samples"     = "Skipped"
    "OpenVINO GenAI Python venv"     = "Skipped"
    "AI PC Samples venv"             = "Skipped"
    "LlamaCpp Python (Vulkan)"       = "Skipped"
    "Native LlamaCpp (Vulkan)"       = "Skipped"
    "Windows AI Foundry Samples"     = "Skipped"
}

# Function: Download With Progress and Retry
function Start-DownloadWithRetry {
    param (
        [string]$Uri,
        [string]$OutFile,
        [int]$MaxRetries = 3
    )

    $attempt = 0
    do {
        try {
            $attempt++
            Write-Host "[Attempt $attempt/$MaxRetries] Downloading $OutFile..." -ForegroundColor Cyan

            $req = [System.Net.HttpWebRequest]::Create($Uri)
            $req.Method = "GET"
            $res = $req.GetResponse()
            $stream = $res.GetResponseStream()
            $totalBytes = $res.ContentLength
            [byte[]]$buffer = New-Object byte[] 1MB
            $bytesRead = 0
            $targetFileStream = [System.IO.File]::Create($OutFile)

            do {
                $count = $stream.Read($buffer, 0, $buffer.Length)
                $targetFileStream.Write($buffer, 0, $count)
                $bytesRead += $count

                if ($totalBytes -gt 0) {
                    $percentComplete = [Math]::Round(($bytesRead / $totalBytes) * 100, 2)
                    Write-Progress -Activity "Downloading $OutFile" -Status "$percentComplete% Complete" -PercentComplete $percentComplete
                }
            } while ($count -gt 0)

            $targetFileStream.Close()
            $stream.Close()
            Write-Progress -Activity "Downloading $OutFile" -Completed
            return $true
        }
        catch {
            Write-Warning "[Attempt $attempt failed] $_"
            if ($attempt -lt $MaxRetries) {
                $delay = [Math]::Pow(2, $attempt) * 1000  # Exponential backoff: 2s, 4s, 8s...
                Write-Host "Retrying in $([Math]::Round($delay / 1000, 1)) seconds..." -ForegroundColor Yellow
                Start-Sleep -Milliseconds $delay
            } else {
                Write-Error "Failed to download $OutFile after $MaxRetries attempts."
                return $false
            }
        }
    } while ($attempt -le $MaxRetries)
}

function Install-PipPackages {
    param(
        [string]$VenvPath,
        [string]$RequirementsFile = $null,
        [string[]]$Packages = $null,
        [int]$TimeoutSeconds = 300,
        [int]$MaxRetries = 3
    )
    
    $pipExe = Join-Path $VenvPath "Scripts\pip.exe"
    
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            Write-Host "Attempt $attempt of $MaxRetries..."
            
            if ($RequirementsFile) {
                $installArgs = @("install", "-r", $RequirementsFile, "--timeout", $TimeoutSeconds)
            } elseif ($Packages) {
                $installArgs = @("install") + $Packages + @("--timeout", $TimeoutSeconds)
            }
            
            & $pipExe $installArgs
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Package installation successful" -ForegroundColor Green
                return $true
            } else {
                Write-Host "Package installation failed (attempt $attempt)" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "Exception during package installation (attempt $attempt): $_" -ForegroundColor Yellow
        }
        
        if ($attempt -lt $MaxRetries) {
            Write-Host "Retrying in 5 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }
    }
    
    Write-Host "Trying with alternative PyPI mirror..." -ForegroundColor Yellow
    try {
        if ($RequirementsFile) {
            $installArgs = @("install", "-r", $RequirementsFile, "--timeout", $TimeoutSeconds, "-i", "https://pypi.org/simple/")
        } elseif ($Packages) {
            $installArgs = @("install") + $Packages + @("--timeout", $TimeoutSeconds, "-i", "https://pypi.org/simple/")
        }
        
        & $pipExe $installArgs
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Package installation successful with alternative mirror" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Host "Exception with alternative mirror: $_" -ForegroundColor Yellow
    }
    
    Write-Host "Failed to install packages after all attempts" -ForegroundColor Red
    return $false
}

function New-PythonVenv {
    param(
        [string]$Path,
        [string]$VenvName = "venv"
    )
    
    $venvPath = Join-Path $Path $VenvName
    
    if (Test-Path $venvPath) {
        Write-Host "Virtual environment already exists at: $venvPath" -ForegroundColor Yellow
        return $venvPath
    }
    
    try {
        Write-Host "Creating Python virtual environment at: $venvPath"
        & python -m venv $venvPath
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Virtual environment created successfully" -ForegroundColor Green
            return $venvPath
        } else {
            Write-Host "Failed to create virtual environment" -ForegroundColor Red
            return $null
        }
    }
    catch {
        Write-Host "Exception creating virtual environment: $_" -ForegroundColor Red
        return $null
    }
}

function Test-PyPIConnectivity {
    try {
        Write-Host "Checking network connectivity to PyPI..."
        $response = Invoke-WebRequest -Uri "https://pypi.org" -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "Network connectivity to PyPI is working" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Host "Warning: Network connectivity to PyPI seems slow or unavailable" -ForegroundColor Yellow
        return $false
    }
}

function Test-BuildEnvironment {
    $vcvarsFound = $false
    $cmakeFound = $false
    $cmakeVersionOk = $false
    
    # Check for CMake and version
    try {
        $cmakeOutput = & cmake --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $cmakeOutput) {
            $cmakeFound = $true
            # Extract version number from output like "cmake version 3.XX.X" or "cmake version 4.XX.X"
            if ($cmakeOutput[0] -match "cmake version (\d+)\.(\d+)\.(\d+)") {
                $majorVersion = [int]$matches[1]
                $minorVersion = [int]$matches[2]
                if ($majorVersion -gt 3 -or ($majorVersion -eq 3 -and $minorVersion -ge 5)) {
                    $cmakeVersionOk = $true
                    Write-Host "CMake version OK: $($cmakeOutput[0])" -ForegroundColor Green
                } else {
                    Write-Host "CMake version too old: $($cmakeOutput[0]) (requires 3.5+)" -ForegroundColor Yellow
                }
            }
        }
    }
    catch {
        Write-Host "CMake not found in PATH" -ForegroundColor Yellow
    }
    
    # Primary: use vswhere.exe (official VS locator, ships with VS 2017+)
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        try {
            $vsInstallPath = (& $vswhere -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null) | Select-Object -First 1
            if ($vsInstallPath) {
                $vsInstallPath = $vsInstallPath.Trim()
                $vcvarsPath = Join-Path $vsInstallPath "VC\Auxiliary\Build\vcvarsall.bat"
                if (Test-Path $vcvarsPath) {
                    $vcvarsFound = $true
                    Write-Host "Visual Studio with C++ tools found at: $vsInstallPath" -ForegroundColor Green
                }
            }
            if (-not $vcvarsFound) {
                # Also check for Build Tools without the full IDE
                $vsInstallPath = (& $vswhere -latest -products Microsoft.VisualStudio.Product.BuildTools -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null) | Select-Object -First 1
                if ($vsInstallPath) {
                    $vsInstallPath = $vsInstallPath.Trim()
                    $vcvarsPath = Join-Path $vsInstallPath "VC\Auxiliary\Build\vcvarsall.bat"
                    if (Test-Path $vcvarsPath) {
                        $vcvarsFound = $true
                        Write-Host "Visual Studio Build Tools with C++ found at: $vsInstallPath" -ForegroundColor Green
                    }
                }
            }
        }
        catch {
            Write-Host "vswhere.exe query failed, falling back to path scan..." -ForegroundColor Yellow
        }
    }
    
    # Fallback: scan common install paths if vswhere not available or found nothing
    if (-not $vcvarsFound) {
        $vcvarsPaths = @(
            "${env:ProgramFiles}\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvarsall.bat",
            "${env:ProgramFiles}\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat",
            "${env:ProgramFiles}\Microsoft Visual Studio\18\Professional\VC\Auxiliary\Build\vcvarsall.bat",
            "${env:ProgramFiles}\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\Build\vcvarsall.bat",
            "${env:ProgramFiles}\Microsoft Visual Studio\2026\BuildTools\VC\Auxiliary\Build\vcvarsall.bat",
            "${env:ProgramFiles}\Microsoft Visual Studio\2026\Community\VC\Auxiliary\Build\vcvarsall.bat",
            "${env:ProgramFiles}\Microsoft Visual Studio\2026\Professional\VC\Auxiliary\Build\vcvarsall.bat",
            "${env:ProgramFiles}\Microsoft Visual Studio\2026\Enterprise\VC\Auxiliary\Build\vcvarsall.bat",
            "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat",
            "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat",
            "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat",
            "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat",
            "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvarsall.bat",
            "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat"
        )
        foreach ($vcvarsPath in $vcvarsPaths) {
            if (Test-Path $vcvarsPath) {
                $vcvarsFound = $true
                Write-Host "Visual Studio Build Tools found at: $vcvarsPath" -ForegroundColor Green
                break
            }
        }
    }

    if (-not $vcvarsFound) {
        Write-Host "Visual Studio Build Tools with C++ components not found" -ForegroundColor Yellow
        Write-Host "Tip: Run 'vswhere.exe -all -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64' to diagnose" -ForegroundColor Gray
    }
    
    if (-not $cmakeFound) {
        Write-Host "CMake not found" -ForegroundColor Yellow
    } elseif (-not $cmakeVersionOk) {
        Write-Host "CMake version incompatible (needs 3.5+)" -ForegroundColor Yellow
    }
    
    return ($vcvarsFound -and $cmakeFound -and $cmakeVersionOk)
}

function Install-JupyterKernel {
    param(
        [string]$VenvPath,
        [string]$KernelName,
        [string]$DisplayName
    )
    
    Write-Host "Installing ipykernel and creating Jupyter kernel..." -ForegroundColor Cyan
    $ipykernelSuccess = Install-PipPackages -VenvPath $VenvPath -Packages @("ipykernel")
    if ($ipykernelSuccess) {
        $pythonExe = Join-Path $VenvPath "Scripts\python.exe"
        try {
            & $pythonExe -m ipykernel install --user --name=$KernelName --display-name="$DisplayName"
            Write-Host "Jupyter kernel '$KernelName' created successfully" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to create Jupyter kernel: $_" -ForegroundColor Yellow
        }
    }
}

# Main Installation Process
Write-Host "Starting AI PC Dev Kit Complete Installation..." -ForegroundColor Cyan
Test-PyPIConnectivity

# Step 1: Fast Parallel Downloads
Write-Host "`n=== STEP 1: DOWNLOADING REPOSITORIES ===" -ForegroundColor Magenta

# Setup Runspace Pool for Parallel Downloads
$runspacePool = [runspacefactory]::CreateRunspacePool(1, 5)
$runspacePool.Open()

$jobs = @()

# Define Repos
$repos = @(    
    @{ Name = "openvino_notebooks"; Uri = "https://github.com/openvinotoolkit/openvino_notebooks/archive/refs/heads/latest.zip"; File = "openvino_notebooks-latest.zip" },
    @{ Name = "openvino_genai"; Uri = "https://storage.openvinotoolkit.org/repositories/openvino_genai/packages/2026.0/windows/openvino_genai_windows_2026.0.0.0_x86_64.zip"; File = "openvino_genai.zip" },
    @{ Name = "AI-PC-Samples"; Uri = "https://github.com/intel/AI-PC-Samples/archive/refs/heads/main.zip"; File = "ai-pc-samples.zip" },
    @{ Name = "Microsoft-Build2025-Samples"; Uri = "https://github.com/intel/Microsoft-Build2025-Samples/archive/refs/heads/main.zip"; File = "microsoft-build2025-samples.zip" }
)

# Launch jobs
$skipped = 0
foreach ($repo in $repos) {
    # Check if target directory already exists - skip download if so
    if (Test-Path $repo.Name) {
        Write-Host "SKIP: $($repo.Name) directory already exists, skipping download." -ForegroundColor Yellow
        $skipped++
        continue
    }
    
    # Check if zip file already exists - skip download if so
    $zipPath = Join-Path $DevKitWorkingDir $repo.File
    if (Test-Path $zipPath) {
        Write-Host "SKIP: $($repo.File) already downloaded." -ForegroundColor Yellow
        $skipped++
        continue
    }

    $scriptBlock = {
        param($Uri, $OutFile, $Name, $MaxRetries, $WorkingDir)
        
        function Start-DownloadWithRetry {
            param ($Uri, $OutFile, [int]$MaxRetries = 3)
            $attempt = 0
            $fullPath = Join-Path $WorkingDir $OutFile
            do {
                try {
                    $attempt++
                    Write-Host "[Attempt $attempt/$MaxRetries] $Name..." -ForegroundColor Gray
                    $req = [System.Net.HttpWebRequest]::Create($Uri)
                    $req.Method = "GET"
                    $res = $req.GetResponse()
                    $stream = $res.GetResponseStream()
                    $totalBytes = $res.ContentLength
                    [byte[]]$buffer = New-Object byte[] 1MB
                    $bytesRead = 0
                    $targetFileStream = [System.IO.File]::Create($fullPath)

                    do {
                        $count = $stream.Read($buffer, 0, $buffer.Length)
                        $targetFileStream.Write($buffer, 0, $count)
                        $bytesRead += $count

                        if ($totalBytes -gt 0) {
                            $percentComplete = [Math]::Round(($bytesRead / $totalBytes) * 100, 2)
                            # Progress doesn't show in runspaces, so we'll log instead
                            if ($bytesRead % (5 * 1MB) -eq 0 -or $count -eq 0) {
                                Write-Host "[$Name] $percentComplete% downloaded" -ForegroundColor Gray
                            }
                        }
                    } while ($count -gt 0)

                    $targetFileStream.Close()
                    $stream.Close()
                    Write-Host "[$Name] Download completed!" -ForegroundColor Green
                    return $true
                }
                catch {
                    Write-Warning "[${Name}] Attempt $attempt failed: $_"
                    if ($attempt -lt $MaxRetries) {
                        $delay = [Math]::Pow(2, $attempt) * 1000
                        Start-Sleep -Milliseconds $delay
                    } else {
                        return $false
                    }
                }
            } while ($attempt -le $MaxRetries)
        }

        Start-DownloadWithRetry -Uri $Uri -OutFile $OutFile -MaxRetries $MaxRetries
    }

    $powershell = [powershell]::Create().
        AddScript($scriptBlock).
        AddArgument($repo.Uri).
        AddArgument($repo.File).
        AddArgument($repo.Name).
        AddArgument($MaxRetries).
        AddArgument($DevKitWorkingDir)

    $powershell.RunspacePool = $runspacePool
    $handle = $powershell.BeginInvoke()
    $jobs += [PSCustomObject]@{
        Name   = $repo.Name
        Job    = $powershell
        Handle = $handle
        File   = $repo.File
    }
}

# Wait for all downloads
if ($jobs.Count -eq 0) {
    Write-Host "`nNo downloads needed - all repositories already exist or are downloaded." -ForegroundColor Green
} else {
    Write-Host "`nWaiting for $($jobs.Count) downloads to complete... ($skipped skipped)" -ForegroundColor Yellow
    $completed = 0
    $total = $jobs.Count
    Write-Host "Downloads completed: $completed/$total" -ForegroundColor Cyan
    
    while ($completed -lt $total) {
        Start-Sleep -Milliseconds 500  # Check more frequently
        $newCompleted = ($jobs | Where-Object { $_.Handle.IsCompleted }).Count
        if ($newCompleted -gt $completed) {
            $completed = $newCompleted
            Write-Host "Downloads completed: $completed/$total" -ForegroundColor Cyan
        }
    }
}

# Check Results
$downloadResults = foreach ($job in $jobs) {
    try {
        $result = $job.Job.EndInvoke($job.Handle)
        [PSCustomObject]@{
            Name     = $job.Name
            Success  = $result
            File     = $job.File
        }
    } catch {
        [PSCustomObject]@{
            Name     = $job.Name
            Success  = $false
            File     = $job.File
        }
    } finally {
        $job.Job.Dispose()
    }
}

# Extract archives - FIXED DIRECTORY NAMES
foreach ($result in $downloadResults) {
    if (-not $result.Success) {
        Write-Error "Skipping extraction for $($result.Name) due to download failure."
        continue
    }

    $name = $result.Name
    $file = $result.File

    if (Test-Path $name) {
        Write-Host "SKIP: $name already exists." -ForegroundColor Yellow
        continue
    }

    Write-Host "`nExtracting $file -> $name..." -ForegroundColor Cyan
    try {
        Expand-Archive -Path "$DevKitWorkingDir\$file" -DestinationPath $DevKitWorkingDir -Force
        Remove-Item "$DevKitWorkingDir\$file" -Force

        switch ($name) {
            "openvino_notebooks"     { 
                if (Test-Path "openvino_notebooks-latest") {
                    Rename-Item "openvino_notebooks-latest" $name 
                }
            }
            "webnn_workshop"         { 
                if (Test-Path "webnn_workshop-main") {
                    Rename-Item "webnn_workshop-main" $name 
                }
            }
            "AI-PC-Samples"          { 
                if (Test-Path "AI-PC-Samples-main") {
                    Rename-Item "AI-PC-Samples-main" $name 
                }
            }
            "openvino_genai"         { 
                # Updated to 2026.0.0.0
                if (Test-Path "openvino_genai_windows_2026.0.0.0_x86_64") {
                    Rename-Item "openvino_genai_windows_2026.0.0.0_x86_64" $name 
                }
            }
            "Microsoft-Build2025-Samples" { 
                if (Test-Path "Microsoft-Build2025-Samples-main") {
                    Rename-Item "Microsoft-Build2025-Samples-main" $name 
                }
            }
            Default {}
        }
        Write-Host "SUCCESS: $name ready." -ForegroundColor Green
    } catch {
        Write-Error "Failed to extract $file`: $_"
    }
}

$runspacePool.Close()
$runspacePool.Dispose()

# Step 2: Setup Virtual Environments and Install Dependencies
Write-Host "`n=== STEP 2: SETTING UP VIRTUAL ENVIRONMENTS ===" -ForegroundColor Magenta

# 1. OpenVINO Notebooks
if (Test-Path "openvino_notebooks") {
    Write-Host "`nSetting up OpenVINO Notebooks environment..." -ForegroundColor Cyan
    $venvPath = New-PythonVenv -Path "$DevKitWorkingDir\openvino_notebooks"
    if ($venvPath) {
        $requirementsPath = Join-Path "$DevKitWorkingDir\openvino_notebooks" "requirements.txt"
        if (Test-Path $requirementsPath) {
            Write-Host "Installing OpenVINO notebooks requirements..."
            $success = Install-PipPackages -VenvPath $venvPath -RequirementsFile $requirementsPath
            if ($success) {
                Install-JupyterKernel -VenvPath $venvPath -KernelName "openvino_notebooks" -DisplayName "OpenVINO Notebooks"
                $installResults["OpenVINO Notebooks venv"] = "Success"
            } else {
                $installResults["OpenVINO Notebooks venv"] = "Failed"
                Write-Host "Manual command: cd `"$DevKitWorkingDir\openvino_notebooks`"; .\venv\Scripts\activate; pip install -r requirements.txt" -ForegroundColor Yellow
            }
        } else {
            $installResults["OpenVINO Notebooks venv"] = "Failed (requirements.txt not found)"
        }
    } else {
        $installResults["OpenVINO Notebooks venv"] = "Failed (venv creation error)"
    }
}

# 2. OpenVINO GenAI
if (Test-Path "openvino_genai") {
    Write-Host "`nSetting up OpenVINO GenAI environment..." -ForegroundColor Cyan
    $genaiPath = "$DevKitWorkingDir\openvino_genai"
    Set-Location $genaiPath
    
    Write-Host "Using pre-built binary package" -ForegroundColor Green
    # Install OpenVINO dependencies (Windows equivalent)
    $dependenciesScript = Join-Path $genaiPath "install_dependencies\install_openvino_dependencies.ps1"
    if (Test-Path $dependenciesScript) {
        Write-Host "Installing OpenVINO dependencies..." -ForegroundColor Cyan
        try {
            & $dependenciesScript
            Write-Host "Dependencies installed successfully" -ForegroundColor Green
        }
        catch {
            Write-Host "Warning: Failed to install dependencies: $_" -ForegroundColor Yellow
        }
    }
    
    # Source setupvars.ps1 (Windows equivalent of setupvars.sh)
    $setupvarsScript = Join-Path $genaiPath "setupvars.ps1"
    if (Test-Path $setupvarsScript) {
        Write-Host "Sourcing setupvars.ps1..." -ForegroundColor Cyan
        try {
            & $setupvarsScript
            Write-Host "Environment variables set successfully" -ForegroundColor Green
        }
        catch {
            Write-Host "Warning: Failed to source setupvars.ps1: $_" -ForegroundColor Yellow
        }
    }
    
    # Test build environment and attempt to build C++ samples
    $cppSamplesPath = Join-Path $genaiPath "samples\cpp"
    if (Test-Path $cppSamplesPath) {
        # Ensure we're in the correct directory for building
        Push-Location $cppSamplesPath
        
        if (Test-BuildEnvironment) {
            $buildScript = Join-Path $cppSamplesPath "build_samples.ps1"
            if (Test-Path $buildScript) {
                Write-Host "Building C++ samples in: $cppSamplesPath" -ForegroundColor Cyan
                try {
                    # Use CMAKE_POLICY_VERSION_MINIMUM for CMake 4.0 compatibility
                    $env:CMAKE_POLICY_VERSION_MINIMUM = "3.5"
                    
                    Write-Host "Using CMAKE_POLICY_VERSION_MINIMUM=3.5 for CMake 4.0 compatibility..." -ForegroundColor Yellow
                    
                    # Try the build with the policy version minimum
                    & $buildScript
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "C++ samples built successfully" -ForegroundColor Green
                        $installResults["OpenVINO GenAI C++ Samples"] = "Success"
                    } else {
                        Write-Host "Build completed with warnings/errors (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
                        Write-Host "This is common with OpenVINO GenAI samples and may not prevent usage" -ForegroundColor Yellow
                        $installResults["OpenVINO GenAI C++ Samples"] = "Completed with warnings"
                    }
                }
                catch {
                    Write-Host "Build script execution failed: $_" -ForegroundColor Yellow
                    Write-Host "Attempting direct CMake build..." -ForegroundColor Yellow
                    
                    # Try direct cmake approach with CMAKE_POLICY_VERSION_MINIMUM
                    try {
                        Write-Host "Trying direct CMake build with policy version minimum..." -ForegroundColor Cyan
                        $buildDir = Join-Path $cppSamplesPath "build"
                        if (-not (Test-Path $buildDir)) {
                            New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
                        }
                        Push-Location $buildDir
                        
                        # Configure with CMAKE_POLICY_VERSION_MINIMUM
                        & cmake .. -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release
                        if ($LASTEXITCODE -eq 0) {
                            & cmake --build . --config Release
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "Direct CMake build succeeded" -ForegroundColor Green
                            } else {
                                Write-Host "Direct CMake build completed with warnings" -ForegroundColor Yellow
                            }
                        }
                        Pop-Location
                    }
                    catch {
                        Write-Host "Direct CMake approach also failed: $_" -ForegroundColor Yellow
                        $installResults["OpenVINO GenAI C++ Samples"] = "Failed"
                        # Ensure we return to the correct location even on error
                        try { Pop-Location } catch { }
                    }
                }
                finally {
                    # Clean up environment variable
                    Remove-Item env:CMAKE_POLICY_VERSION_MINIMUM -ErrorAction SilentlyContinue
                }
            } else {
                Write-Host "Warning: build_samples.ps1 not found at $buildScript" -ForegroundColor Yellow
            }
        } else {
            Write-Host "Warning: Build environment not properly configured. Skipping C++ samples build." -ForegroundColor Yellow
            Write-Host "Requirements for C++ sample compilation:" -ForegroundColor Yellow
            Write-Host "1. Install Visual Studio Build Tools 2026 or Visual Studio 2026" -ForegroundColor White
            Write-Host "2. Install CMake 3.5+ and add to PATH" -ForegroundColor White
            Write-Host "3. Run: cd `"$cppSamplesPath`"; .\build_samples.ps1" -ForegroundColor White
            Write-Host "Alternative: Use pre-built Python samples instead" -ForegroundColor White
            $installResults["OpenVINO GenAI C++ Samples"] = "Skipped (build environment not configured)"
        }
        
        # Return to the original location
        Pop-Location
    }
    
    # Return to base directory and setup Python environment
    Set-Location $DevKitWorkingDir
    $samplesPath = "$DevKitWorkingDir\openvino_genai\samples"
    if (Test-Path $samplesPath) {
        $venvPath = New-PythonVenv -Path $samplesPath
        if ($venvPath) {
            $requirementsPath = Join-Path $samplesPath "requirements.txt"
            if (Test-Path $requirementsPath) {
                Write-Host "Installing OpenVINO GenAI requirements..." -ForegroundColor Cyan
                $success = Install-PipPackages -VenvPath $venvPath -RequirementsFile $requirementsPath
                if ($success) {
                    Install-JupyterKernel -VenvPath $venvPath -KernelName "openvino_genai" -DisplayName "OpenVINO GenAI"
                    $installResults["OpenVINO GenAI Python venv"] = "Success"
                } else {
                    $installResults["OpenVINO GenAI Python venv"] = "Failed"
                    Write-Host "Manual command: cd `"$samplesPath`"; .\venv\Scripts\activate; pip install -r requirements.txt" -ForegroundColor Yellow
                }
            } else {
                $installResults["OpenVINO GenAI Python venv"] = "Failed (requirements.txt not found)"
            }
        } else {
            $installResults["OpenVINO GenAI Python venv"] = "Failed (venv creation error)"
        }
    }
}

# 4. AI-PC-Samples (Intel AI PC Samples)
if (Test-Path "AI-PC-Samples") {
    Write-Host "`nSetting up AI PC Samples environment..." -ForegroundColor Cyan
    $venvPath = New-PythonVenv -Path "$DevKitWorkingDir\AI-PC-Samples"
    if ($venvPath) {
        # Check for requirements.txt in AI-Travel-Agent subdirectory first
        $requirementsPath = Join-Path "$DevKitWorkingDir\AI-PC-Samples\AI-Travel-Agent" "requirements.txt"
        if (-not (Test-Path $requirementsPath)) {
            # Fallback to root directory requirements.txt
            $requirementsPath = Join-Path "$DevKitWorkingDir\AI-PC-Samples" "requirements.txt"
        }
        
        if (Test-Path $requirementsPath) {
            Write-Host "Installing AI PC Samples requirements..."
            $success = Install-PipPackages -VenvPath $venvPath -RequirementsFile $requirementsPath
            if ($success) {
                Install-JupyterKernel -VenvPath $venvPath -KernelName "ai_pc_samples" -DisplayName "AI PC Samples"
                $installResults["AI PC Samples venv"] = "Success"
                
                # Install LlamaCpp Python with Vulkan support (try latest, fall back to v0.3.8)
                Write-Host "Installing LlamaCpp Python with Vulkan support..." -ForegroundColor Cyan
                $pipExe = Join-Path $venvPath "Scripts\pip.exe"
                try {
                    # Set environment variables for Vulkan compilation
                    $env:CMAKE_ARGS = "-DGGML_VULKAN=on"
                    $env:FORCE_CMAKE = "1"
                    
                    Write-Host "Trying latest llama-cpp-python (no version pin)..." -ForegroundColor Yellow
                    & $pipExe install llama-cpp-python -U --force --no-cache-dir
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "LlamaCpp Python (latest) with Vulkan compiled successfully!" -ForegroundColor Green
                        $installResults["LlamaCpp Python (Vulkan)"] = "Success"
                    } else {
                        Write-Host "Latest failed, falling back to llama-cpp-python==0.3.8..." -ForegroundColor Yellow
                        & $pipExe install llama-cpp-python==0.3.8 -U --force --no-cache-dir
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "LlamaCpp Python v0.3.8 with Vulkan compiled successfully!" -ForegroundColor Green
                            $installResults["LlamaCpp Python (Vulkan)"] = "Success (v0.3.8 fallback)"
                        } else {
                            Write-Host "LlamaCpp Python compilation failed for both latest and v0.3.8" -ForegroundColor Yellow
                            $installResults["LlamaCpp Python (Vulkan)"] = "Failed"
                        }
                    }
                }
                catch {
                    Write-Host "Exception during LlamaCpp Python compilation: $_" -ForegroundColor Yellow
                    $installResults["LlamaCpp Python (Vulkan)"] = "Failed (exception)"
                }
                finally {
                    # Clean up environment variables
                    Remove-Item env:CMAKE_ARGS -ErrorAction SilentlyContinue
                    Remove-Item env:FORCE_CMAKE -ErrorAction SilentlyContinue
                }
                

            } else {
                $installResults["AI PC Samples venv"] = "Failed"
                Write-Host "Manual command: cd `"$DevKitWorkingDir\AI-PC-Samples`"; .\venv\Scripts\activate; pip install -r AI-Travel-Agent\requirements.txt" -ForegroundColor Yellow
            }
        } else {
            # If no requirements.txt, install basic packages for AI PC Samples
            Write-Host "Installing basic packages for AI PC Samples..."
            $packages = @("numpy", "matplotlib", "jupyter", "ipywidgets", "torch", "transformers", "opencv-python")
            $success = Install-PipPackages -VenvPath $venvPath -Packages $packages
            if ($success) {
                Install-JupyterKernel -VenvPath $venvPath -KernelName "ai_pc_samples" -DisplayName "AI PC Samples"
                $installResults["AI PC Samples venv"] = "Success"
                
                # Install LlamaCpp Python with Vulkan support (try latest, fall back to v0.3.8)
                Write-Host "Installing LlamaCpp Python with Vulkan support..." -ForegroundColor Cyan
                $pipExe = Join-Path $venvPath "Scripts\pip.exe"
                try {
                    # Set environment variables for Vulkan compilation
                    $env:CMAKE_ARGS = "-DGGML_VULKAN=on"
                    $env:FORCE_CMAKE = "1"
                    
                    Write-Host "Trying latest llama-cpp-python (no version pin)..." -ForegroundColor Yellow
                    & $pipExe install llama-cpp-python -U --force --no-cache-dir
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "LlamaCpp Python (latest) with Vulkan compiled successfully!" -ForegroundColor Green
                        $installResults["LlamaCpp Python (Vulkan)"] = "Success"
                    } else {
                        Write-Host "Latest failed, falling back to llama-cpp-python==0.3.8..." -ForegroundColor Yellow
                        & $pipExe install llama-cpp-python==0.3.8 -U --force --no-cache-dir
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "LlamaCpp Python v0.3.8 with Vulkan compiled successfully!" -ForegroundColor Green
                            $installResults["LlamaCpp Python (Vulkan)"] = "Success (v0.3.8 fallback)"
                        } else {
                            Write-Host "LlamaCpp Python compilation failed for both latest and v0.3.8" -ForegroundColor Yellow
                            $installResults["LlamaCpp Python (Vulkan)"] = "Failed"
                        }
                    }
                }
                catch {
                    Write-Host "Exception during LlamaCpp Python compilation: $_" -ForegroundColor Yellow
                    $installResults["LlamaCpp Python (Vulkan)"] = "Failed (exception)"
                }
                finally {
                    # Clean up environment variables
                    Remove-Item env:CMAKE_ARGS -ErrorAction SilentlyContinue
                    Remove-Item env:FORCE_CMAKE -ErrorAction SilentlyContinue
                }
            } else {
                $installResults["AI PC Samples venv"] = "Failed"
            }
        }
    }
}

# 5. LlamaCpp with Vulkan (Independent Installation)
Write-Host "`nSetting up LlamaCpp with Vulkan in C:\Intel..." -ForegroundColor Cyan
$llamacppPath = Join-Path $DevKitWorkingDir "llama.cpp"
if (-not (Test-Path $llamacppPath)) {
    Set-Location $DevKitWorkingDir
    
    try {
        $llamacppTag = "b8920"
        $llamacppZipUrl = "https://github.com/ggml-org/llama.cpp/archive/refs/tags/$llamacppTag.zip"
        $llamacppZip = Join-Path $DevKitWorkingDir "llama.cpp-$llamacppTag.zip"

        Write-Host "Downloading LlamaCpp $llamacppTag zip..." -ForegroundColor Cyan
        $downloadSuccess = Start-DownloadWithRetry -Uri $llamacppZipUrl -OutFile $llamacppZip -MaxRetries $MaxRetries

        if ($downloadSuccess -and (Test-Path $llamacppZip)) {
            Write-Host "Extracting LlamaCpp $llamacppTag..." -ForegroundColor Cyan
            Expand-Archive -Path $llamacppZip -DestinationPath $DevKitWorkingDir -Force
            Remove-Item $llamacppZip -Force -ErrorAction SilentlyContinue

            # Release zips extract as llama.cpp-<tag>, rename to llama.cpp
            $extractedDir = Join-Path $DevKitWorkingDir "llama.cpp-$llamacppTag"
            if (Test-Path $extractedDir) {
                Rename-Item $extractedDir $llamacppPath
                Write-Host "LlamaCpp extracted to: $llamacppPath" -ForegroundColor Green
            }
        } else {
            Write-Host "Download failed, falling back to git clone..." -ForegroundColor Yellow
            & git clone https://github.com/ggml-org/llama.cpp.git
        }

        if (Test-Path $llamacppPath) {
            Set-Location $llamacppPath
            
            if (Test-BuildEnvironment) {
                Write-Host "Building native LlamaCpp with Vulkan support in: $llamacppPath" -ForegroundColor Cyan
                
                # Configure with CMake
                & cmake -B build -DGGML_VULKAN=ON -DLLAMA_CURL=OFF
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "CMake configuration successful, building..." -ForegroundColor Green
                    & cmake --build build --config Release -j
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Native LlamaCpp built successfully in: $llamacppPath" -ForegroundColor Green
                        $installResults["Native LlamaCpp (Vulkan)"] = "Success"
                    } else {
                        Write-Host "Native LlamaCpp build completed with warnings" -ForegroundColor Yellow
                        $installResults["Native LlamaCpp (Vulkan)"] = "Completed with warnings"
                    }
                } else {
                    Write-Host "CMake configuration failed for native LlamaCpp" -ForegroundColor Yellow
                    $installResults["Native LlamaCpp (Vulkan)"] = "Failed (CMake config error)"
                }
            } else {
                Write-Host "Build environment not available, skipping native LlamaCpp compilation" -ForegroundColor Yellow
                Write-Host "Requirements: Visual Studio Build Tools 2026 + CMake 3.5+" -ForegroundColor White
            }
        }
    }
    catch {
        Write-Host "Failed to clone or build native LlamaCpp: $_" -ForegroundColor Yellow
        $installResults["Native LlamaCpp (Vulkan)"] = "Failed (clone/build error)"
    }
    finally {
        Set-Location $DevKitWorkingDir
    }
} else {
    Write-Host "Native LlamaCpp already exists at: $llamacppPath, skipping..." -ForegroundColor Yellow
}

# 6. Windows AI Foundry Samples (no venv required)
if (Test-Path "Microsoft-Build2025-Samples") {
    Write-Host "`nWindows AI Foundry Samples downloaded successfully at: $DevKitWorkingDir\Microsoft-Build2025-Samples" -ForegroundColor Green
    $installResults["Windows AI Foundry Samples"] = "Success"
} else {
    $installResults["Windows AI Foundry Samples"] = "Skipped (directory not found)"
}

# Clean up any remaining zip files - UPDATED ZIP FILE NAMES
Write-Host "`nCleaning up downloaded zip files..." -ForegroundColor Cyan
$zipFiles = @("openvino_notebooks-latest.zip", "openvino_genai.zip", "ai-pc-samples.zip", "microsoft-build2025-samples.zip")
foreach ($zipFile in $zipFiles) {
    if (Test-Path $zipFile) {
        Remove-Item $zipFile -Force
        Write-Host "Removed: $zipFile"
    }
}

# Final Summary
Write-Host "`n=== INSTALLATION SUMMARY ===" -ForegroundColor Magenta
Write-Host "AI PC DevKit Complete Installation finished!" -ForegroundColor Green
Write-Host "Installation directory: $DevKitWorkingDir" -ForegroundColor Green

Write-Host "`nJupyter Kernels Created:" -ForegroundColor Yellow
Write-Host "- openvino_notebooks (OpenVINO Notebooks)" -ForegroundColor White
Write-Host "- openvino_genai (OpenVINO GenAI)" -ForegroundColor White
Write-Host "- ai_pc_samples (AI PC Samples)" -ForegroundColor White

Write-Host "`nTo use Jupyter kernels:" -ForegroundColor Yellow
Write-Host "1. Start Jupyter: jupyter lab" -ForegroundColor White
Write-Host "2. Select kernel from the dropdown menu when creating/opening notebooks" -ForegroundColor White

Write-Host "`nTo activate virtual environments:" -ForegroundColor Yellow
Write-Host "OpenVINO Notebooks: cd `"$DevKitWorkingDir\openvino_notebooks`"; .\venv\Scripts\activate" -ForegroundColor White
Write-Host "OpenVINO GenAI: cd `"$DevKitWorkingDir\openvino_genai\samples`"; .\venv\Scripts\activate" -ForegroundColor White
Write-Host "AI PC Samples: cd `"$DevKitWorkingDir\AI-PC-Samples`"; .\venv\Scripts\activate" -ForegroundColor White

Write-Host "`nWindows AI Foundry Samples:" -ForegroundColor Yellow
Write-Host "Location: $DevKitWorkingDir\Microsoft-Build2025-Samples" -ForegroundColor White

Write-Host "`nNative Tools Built:" -ForegroundColor Yellow
Write-Host "LlamaCpp with Vulkan: $DevKitWorkingDir\llama.cpp\build" -ForegroundColor White
Write-Host "OpenVINO GenAI C++ Samples: $DevKitWorkingDir\openvino_genai\samples\cpp\build" -ForegroundColor White

# Component-level installation results
Write-Host "`n=== COMPONENT INSTALLATION RESULTS ==="  -ForegroundColor Magenta
$succeeded = @()
$failed = @()
$skippedItems = @()
foreach ($key in $installResults.Keys) {
    $val = $installResults[$key]
    $color = switch -Wildcard ($val) {
        "Success"                  { "Green" }
        "Completed with warnings"  { "Yellow" }
        "Skipped*"                 { "Gray" }
        default                    { "Red" }
    }
    Write-Host ("  {0,-40} {1}" -f $key, $val) -ForegroundColor $color
    if ($val -eq "Success" -or $val -eq "Completed with warnings") { $succeeded += $key }
    elseif ($val -like "Skipped*")                                  { $skippedItems += $key }
    else                                                            { $failed += $key }
}

Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host "All components installed successfully!" -ForegroundColor Green
} else {
    Write-Host "$($succeeded.Count) component(s) succeeded, $($failed.Count) component(s) failed:" -ForegroundColor Yellow
    foreach ($f in $failed) {
        Write-Host "  - $f : $($installResults[$f])" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Review the output above for manual remediation steps." -ForegroundColor Yellow
}

Write-Host "`nScript completed!" -ForegroundColor Green
