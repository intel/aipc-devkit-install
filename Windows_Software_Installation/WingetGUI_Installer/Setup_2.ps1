# AI PC Dev Kit Complete Installation Script for Windows

param(
    [string]$DevKitWorkingDir = "C:\Intel",
    [int]$MaxRetries = 3
)

$ErrorActionPreference = "Stop"

# Ensure working directory exists
New-Item -ItemType Directory -Path $DevKitWorkingDir -ErrorAction SilentlyContinue
Set-Location $DevKitWorkingDir

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
        $response = Invoke-WebRequest -Uri "https://pypi.org" -Method Head -TimeoutSec 10 -ErrorAction Stop
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
    
    # Check for Visual Studio Build Tools (look for common vcvarsall.bat locations)
    $vcvarsPaths = @(
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
    
    if (-not $vcvarsFound) {
        Write-Host "Visual Studio Build Tools not found" -ForegroundColor Yellow
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
    @{ Name = "openvino_build_deploy"; Uri = "https://github.com/openvinotoolkit/openvino_build_deploy/archive/refs/heads/master.zip"; File = "master-build_deploy.zip" },
    @{ Name = "ollama-ipex-llm"; Uri = "https://github.com/ipex-llm/ipex-llm/releases/download/v2.3.0-nightly/ollama-ipex-llm-2.3.0b20250725-win.zip"; File = "ollama-ipex-llm.zip" },
    @{ Name = "openvino_genai"; Uri = "https://storage.openvinotoolkit.org/repositories/openvino_genai/packages/2025.3/windows/openvino_genai_windows_2025.3.0.0_x86_64.zip"; File = "openvino_genai.zip" },
    @{ Name = "AI-PC-Samples"; Uri = "https://github.com/intel/AI-PC-Samples/archive/refs/heads/main.zip"; File = "ai-pc-samples.zip" },
    @{ Name = "open_model_zoo"; Uri = "https://github.com/openvinotoolkit/open_model_zoo/archive/refs/tags/2024.4.0.zip"; File = "2024.4.0.zip" }
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
            "openvino_build_deploy"  { 
                if (Test-Path "openvino_build_deploy-master") {
                    Rename-Item "openvino_build_deploy-master" $name 
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
                # FIXED: Updated from 2025.2.0.0 to 2025.3.0.0
                if (Test-Path "openvino_genai_windows_2025.3.0.0_x86_64") {
                    Rename-Item "openvino_genai_windows_2025.3.0.0_x86_64" $name 
                }
            }
            "ollama-ipex-llm"        { 
                # This ZIP extracts files directly to the current directory, not into a subdirectory
                # We need to create the target directory and move the files there
                Write-Host "Creating $name directory and moving extracted files..." -ForegroundColor Magenta
                
                # Get a list of all files that were likely extracted from this ZIP
                $ollamaFiles = Get-ChildItem -Path $DevKitWorkingDir -File | Where-Object { 
                    $_.Name -like "*ollama*" -or 
                    $_.Name -like "*llama*" -or 
                    $_.Name -like "*.dll" -or 
                    $_.Name -like "*.exe" -or 
                    $_.Name -like "*.bat" -or 
                    $_.Name -like "*.txt"
                }
                
                if ($ollamaFiles.Count -gt 0) {
                    # Create the target directory
                    New-Item -ItemType Directory -Path $name -Force | Out-Null
                    
                    # Move all the extracted files to the new directory
                    foreach ($file in $ollamaFiles) {
                        Move-Item -Path $file.FullName -Destination $name -Force
                    }
                    
                    Write-Host "Moved $($ollamaFiles.Count) files to $name directory" -ForegroundColor Magenta
                } else {
                    Write-Host "No ollama/llama files found to move" -ForegroundColor Yellow
                }
            }
            "open_model_zoo"         { 
                if (Test-Path "open_model_zoo-2024.4.0") {
                    Rename-Item "open_model_zoo-2024.4.0" $name 
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
            } else {
                Write-Host "Manual command: cd `"$DevKitWorkingDir\openvino_notebooks`"; .\venv\Scripts\activate; pip install -r requirements.txt" -ForegroundColor Yellow
            }
        }
    }
}

# 2. OpenVINO Build Deploy (MSBuild2025 Workshop)
if (Test-Path "openvino_build_deploy") {
    Write-Host "`nSetting up MSBuild2025 Workshop environment..." -ForegroundColor Cyan
    $workshopPath = "$DevKitWorkingDir\openvino_build_deploy\workshops\MSBuild2025"
    if (Test-Path $workshopPath) {
        $venvPath = New-PythonVenv -Path $workshopPath
        if ($venvPath) {
            Write-Host "Installing OpenVINO and Ultralytics packages..."
            # UPDATED: Changed from 2025.1.0 to 2025.3.0 to match the current version
            $packages = @("openvino==2025.3.0", "ultralytics==8.3.120")
            $success = Install-PipPackages -VenvPath $venvPath -Packages $packages
            if ($success) {
                Install-JupyterKernel -VenvPath $venvPath -KernelName "msbuild2025_workshop" -DisplayName "MSBuild2025 Workshop"
            } else {
                Write-Host "Manual command: cd `"$workshopPath`"; .\venv\Scripts\activate; pip install openvino==2025.3.0 ultralytics==8.3.120" -ForegroundColor Yellow
            }
        }
    }
}

# 3. OpenVINO GenAI
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
                    } else {
                        Write-Host "Build completed with warnings/errors (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
                        Write-Host "This is common with OpenVINO GenAI samples and may not prevent usage" -ForegroundColor Yellow
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
            Write-Host "1. Install Visual Studio Build Tools 2022 or Visual Studio Community 2022" -ForegroundColor White
            Write-Host "2. Install CMake 3.5+ and add to PATH" -ForegroundColor White
            Write-Host "3. Run: cd `"$cppSamplesPath`"; .\build_samples.ps1" -ForegroundColor White
            Write-Host "Alternative: Use pre-built Python samples instead" -ForegroundColor White
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
                } else {
                    Write-Host "Manual command: cd `"$samplesPath`"; .\venv\Scripts\activate; pip install -r requirements.txt" -ForegroundColor Yellow
                }
            }
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
                
                # Install LlamaCpp Python with Vulkan support
                Write-Host "Installing LlamaCpp Python with Vulkan support..." -ForegroundColor Cyan
                $pipExe = Join-Path $venvPath "Scripts\pip.exe"
                try {
                    # Set environment variables for Vulkan compilation
                    $env:CMAKE_ARGS = "-DGGML_VULKAN=on"
                    $env:FORCE_CMAKE = "1"
                    
                    Write-Host "Compiling llama-cpp-python with Vulkan support (this may take several minutes)..." -ForegroundColor Yellow
                    & $pipExe install llama-cpp-python==0.3.8 -U --force --no-cache-dir --verbose
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "LlamaCpp Python with Vulkan compiled successfully!" -ForegroundColor Green
                    } else {
                        Write-Host "LlamaCpp Python compilation failed, continuing with standard installation..." -ForegroundColor Yellow
                    }
                }
                catch {
                    Write-Host "Exception during LlamaCpp Python compilation: $_" -ForegroundColor Yellow
                }
                finally {
                    # Clean up environment variables
                    Remove-Item env:CMAKE_ARGS -ErrorAction SilentlyContinue
                    Remove-Item env:FORCE_CMAKE -ErrorAction SilentlyContinue
                }
                

            } else {
                Write-Host "Manual command: cd `"$DevKitWorkingDir\AI-PC-Samples`"; .\venv\Scripts\activate; pip install -r AI-Travel-Agent\requirements.txt" -ForegroundColor Yellow
            }
        } else {
            # If no requirements.txt, install basic packages for AI PC Samples
            Write-Host "Installing basic packages for AI PC Samples..."
            $packages = @("numpy", "matplotlib", "jupyter", "ipywidgets", "torch", "transformers", "opencv-python")
            $success = Install-PipPackages -VenvPath $venvPath -Packages $packages
            if ($success) {
                Install-JupyterKernel -VenvPath $venvPath -KernelName "ai_pc_samples" -DisplayName "AI PC Samples"
                
                # Install LlamaCpp Python with Vulkan support (same as above)
                Write-Host "Installing LlamaCpp Python with Vulkan support..." -ForegroundColor Cyan
                $pipExe = Join-Path $venvPath "Scripts\pip.exe"
                try {
                    # Set environment variables for Vulkan compilation
                    $env:CMAKE_ARGS = "-DGGML_VULKAN=on"
                    $env:FORCE_CMAKE = "1"
                    
                    Write-Host "Compiling llama-cpp-python with Vulkan support (this may take several minutes)..." -ForegroundColor Yellow
                    & $pipExe install llama-cpp-python==0.3.8 -U --force --no-cache-dir --verbose
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "LlamaCpp Python with Vulkan compiled successfully!" -ForegroundColor Green
                    } else {
                        Write-Host "LlamaCpp Python compilation failed, continuing..." -ForegroundColor Yellow
                    }
                }
                catch {
                    Write-Host "Exception during LlamaCpp Python compilation: $_" -ForegroundColor Yellow
                }
                finally {
                    # Clean up environment variables
                    Remove-Item env:CMAKE_ARGS -ErrorAction SilentlyContinue
                    Remove-Item env:FORCE_CMAKE -ErrorAction SilentlyContinue
                }
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
        Write-Host "Cloning LlamaCpp repository to C:\Intel\llama.cpp..." -ForegroundColor Cyan
        & git clone https://github.com/ggml-org/llama.cpp.git
        
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
                    } else {
                        Write-Host "Native LlamaCpp build completed with warnings" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "CMake configuration failed for native LlamaCpp" -ForegroundColor Yellow
                }
            } else {
                Write-Host "Build environment not available, skipping native LlamaCpp compilation" -ForegroundColor Yellow
                Write-Host "Requirements: Visual Studio Build Tools 2022 + CMake 3.5+" -ForegroundColor White
            }
        }
    }
    catch {
        Write-Host "Failed to clone or build native LlamaCpp: $_" -ForegroundColor Yellow
    }
    finally {
        Set-Location $DevKitWorkingDir
    }
} else {
    Write-Host "Native LlamaCpp already exists at: $llamacppPath, skipping..." -ForegroundColor Yellow
}

# 6. Open Model Zoo
if (Test-Path "open_model_zoo") {
    Write-Host "`nSetting up Open Model Zoo environment..." -ForegroundColor Cyan
    $venvPath = New-PythonVenv -Path "$DevKitWorkingDir\open_model_zoo"
    if ($venvPath) {
        $requirementsPath = Join-Path "$DevKitWorkingDir\open_model_zoo" "requirements.txt"
        if (Test-Path $requirementsPath) {
            Write-Host "Installing Open Model Zoo requirements..."
            $success = Install-PipPackages -VenvPath $venvPath -RequirementsFile $requirementsPath
            if ($success) {
                Install-JupyterKernel -VenvPath $venvPath -KernelName "open_model_zoo" -DisplayName "Open Model Zoo"
            } else {
                Write-Host "Manual command: cd `"$DevKitWorkingDir\open_model_zoo`"; .\venv\Scripts\activate; pip install -r requirements.txt" -ForegroundColor Yellow
            }
        } else {
            # If no requirements.txt, install basic OpenVINO packages
            Write-Host "Installing basic packages for Open Model Zoo..."
            $packages = @("openvino", "opencv-python", "numpy", "matplotlib", "jupyter", "ipywidgets")
            $success = Install-PipPackages -VenvPath $venvPath -Packages $packages
            if ($success) {
                Install-JupyterKernel -VenvPath $venvPath -KernelName "open_model_zoo" -DisplayName "Open Model Zoo"
            }
        }
    }
}

# Clean up any remaining zip files - UPDATED ZIP FILE NAMES
Write-Host "`nCleaning up downloaded zip files..." -ForegroundColor Cyan
$zipFiles = @("openvino_notebooks-latest.zip", "master-build_deploy.zip", "ollama-ipex-llm.zip", "openvino_genai.zip", "ai-pc-samples.zip", "2024.4.0.zip")
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
Write-Host "- msbuild2025_workshop (MSBuild2025 Workshop)" -ForegroundColor White
Write-Host "- openvino_genai (OpenVINO GenAI)" -ForegroundColor White
Write-Host "- ai_pc_samples (AI PC Samples)" -ForegroundColor White
Write-Host "- open_model_zoo (Open Model Zoo)" -ForegroundColor White

Write-Host "`nTo use Jupyter kernels:" -ForegroundColor Yellow
Write-Host "1. Start Jupyter: jupyter lab" -ForegroundColor White
Write-Host "2. Select kernel from the dropdown menu when creating/opening notebooks" -ForegroundColor White

Write-Host "`nTo activate virtual environments:" -ForegroundColor Yellow
Write-Host "OpenVINO Notebooks: cd `"$DevKitWorkingDir\openvino_notebooks`"; .\venv\Scripts\activate" -ForegroundColor White
Write-Host "MSBuild2025 Workshop: cd `"$DevKitWorkingDir\openvino_build_deploy\workshops\MSBuild2025`"; .\venv\Scripts\activate" -ForegroundColor White
Write-Host "OpenVINO GenAI: cd `"$DevKitWorkingDir\openvino_genai\samples`"; .\venv\Scripts\activate" -ForegroundColor White
Write-Host "AI PC Samples: cd `"$DevKitWorkingDir\AI-PC-Samples`"; .\venv\Scripts\activate" -ForegroundColor White
Write-Host "Open Model Zoo: cd `"$DevKitWorkingDir\open_model_zoo`"; .\venv\Scripts\activate" -ForegroundColor White

Write-Host "`nNative Tools Built:" -ForegroundColor Yellow
Write-Host "LlamaCpp with Vulkan: $DevKitWorkingDir\llama.cpp\build" -ForegroundColor White
Write-Host "OpenVINO GenAI C++ Samples: $DevKitWorkingDir\openvino_genai\samples\cpp\build" -ForegroundColor White

Write-Host "`nScript completed successfully!" -ForegroundColor Green
