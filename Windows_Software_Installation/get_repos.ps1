# This script downloads and extracts repos for AI Dev Kit with retry logic and progress tracking.

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

# Setup Runspace Pool for Parallel Downloads
$runspacePool = [runspacefactory]::CreateRunspacePool(1, 5)
$runspacePool.Open()

$jobs = @()

# Define Repos
$repos = @(
    @{ Name = "openvino_notebooks"; Uri = "https://github.com/openvinotoolkit/openvino_notebooks/archive/refs/heads/2025.2.zip"; File = "2025.2.zip" },
    @{ Name = "openvino_build_deploy"; Uri = "https://github.com/openvinotoolkit/openvino_build_deploy/archive/refs/heads/master.zip"; File = "master-build_deploy.zip" },
    @{ Name = "ollama-ipex-llm"; Uri = "https://github.com/ipex-llm/ipex-llm/releases/download/v2.3.0-nightly/ollama-ipex-llm-2.3.0b20250725-win.zip"; File = "ollama-ipex-llm.zip" },
    @{ Name = "openvino_genai"; Uri = "https://storage.openvinotoolkit.org/repositories/openvino_genai/packages/2025.2/windows/openvino_genai_windows_2025.2.0.0_x86_64.zip"; File = "openvino_genai.zip" },
    @{ Name = "webnn_workshop"; Uri = "https://github.com/IntelSoftware/webnn_workshop/archive/refs/heads/master.zip"; File = "master-webnn.zip" },
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

# Extract archives
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
                if (Test-Path "openvino_notebooks-2025.2") {
                    Rename-Item "openvino_notebooks-2025.2" $name 
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
            "openvino_genai"         { 
                if (Test-Path "openvino_genai_windows_2025.2.0.0_x86_64") {
                    Rename-Item "openvino_genai_windows_2025.2.0.0_x86_64" $name 
                }
            }
            "ollama-ipex-llm"        { 
                # This ZIP extracts files directly to the current directory, not into a subdirectory
                # We need to create the target directory and move the files there
                Write-Host "DEBUG: Creating $name directory and moving extracted files..." -ForegroundColor Magenta
                
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
                    
                    Write-Host "DEBUG: Moved $($ollamaFiles.Count) files to $name directory" -ForegroundColor Magenta
                } else {
                    Write-Host "DEBUG: No ollama/llama files found to move" -ForegroundColor Yellow
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
Write-Host "`nScript completed successfully!" -ForegroundColor Green