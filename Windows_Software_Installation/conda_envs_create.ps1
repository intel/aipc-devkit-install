# This script is designed to set up a development environment on Windows using winget.
# Define the list of Conda environments to create
# This script is designed to create Conda environments using Miniforge3 on Windows.
# It checks if Miniforge3 is installed, initializes Conda, and creates specified environments with required packages.

$condaEnvironments = @(
    @{
        Name = "pytorch27"
        Packages = @("jupyterlab", "ipywidgets","numpy", "pandas", "matplotlib", "scikit-learn")
    },
    @{
        Name = "openVINO"
        Packages = @("jupyterlab", "ipywidgets", "matplotlib", "scikit-learn", "opencv")
    }
)

# Path to Miniforge3 installation and executable
# When installed via winget, Miniforge is in ProgramData, not UserProfile
$miniforgeBasePath = "C:\ProgramData\miniforge3"
$condaPath = "$miniforgeBasePath\Scripts\conda.exe"

# Ensure Conda is available
if (-Not (Test-Path $condaPath)) {
    Write-Error "Conda executable not found at $condaPath. Please ensure Miniforge3 is installed."
    exit 1
}

# Initialize Conda for this PowerShell session
Write-Host "Initializing Conda environment..." -ForegroundColor Cyan

# Define possible initialization paths
$condaHookBat = "$miniforgeBasePath\condabin\conda_hook.bat"
$condabin = "$miniforgeBasePath\condabin"

# Try different initialization methods in order of preference
if (Test-Path $condaHookBat) {
    # Method 1: Use conda_hook.bat if available
    Write-Host "Using conda_hook.bat to initialize conda..." -ForegroundColor Yellow
    & cmd /c "$condaHookBat" | Out-Null
    # Update PATH to include condabin after running hook
    $env:Path = "$condabin;$env:Path"
    Write-Host "Conda initialized using conda_hook.bat." -ForegroundColor Green
}
else {
    # Method 3: Use dynamic shell hook generation
    Write-Host "Hook scripts not found, trying shell hook method..." -ForegroundColor Yellow
    $initOutput = & "$condaPath" "shell.powershell" "hook" | Out-String
    if ($LASTEXITCODE -eq 0) {
        Invoke-Expression $initOutput
        Write-Host "Conda initialized successfully using shell hook." -ForegroundColor Green
    } else {
        # Fallback to manual PATH manipulation
        Write-Host "Shell hook failed, updating PATH manually..." -ForegroundColor Yellow
        $env:Path = "$miniforgeBasePath;$miniforgeBasePath\Scripts;$miniforgeBasePath\condabin;$miniforgeBasePath\Library\bin;$env:Path"
        Write-Host "Conda initialized using PATH update." -ForegroundColor Yellow
    }
}

# Loop through each environment and create it
foreach ($env in $condaEnvironments) {
    $envName = $env.Name
    $packagesList = $env.Packages
    
    try {
        # Check if the environment already exists
        $existingEnv = conda env list | Select-String -Pattern "^\s*$envName\s"
        if ($existingEnv) {
            Write-Host "Environment '$envName' already exists. Skipping creation." -ForegroundColor Yellow
        } else {
            # Create the environment with a base Python installation first
            Write-Host "Creating environment '$envName' with packages: $($packagesList -join ', ')" -ForegroundColor Cyan
            
            # Create the base environment first
            conda create -n $envName python -y
            
            # Then install packages one by one to ensure they're passed correctly
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Installing packages into environment '$envName'..." -ForegroundColor Cyan
                conda install -n $envName -y $packagesList
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Successfully created environment '$envName' with all packages" -ForegroundColor Green
                } else {
                    Write-Host "Environment created but some packages failed to install" -ForegroundColor Yellow
                }
            } else {
                Write-Host "Failed to create environment '$envName'" -ForegroundColor Red
            }
        }
    } catch {
        Write-Error "An error occurred while creating environment '$envName': $($_.Exception.Message)"
    }
}