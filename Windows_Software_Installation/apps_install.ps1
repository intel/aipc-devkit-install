# This script is designed to set up a development environment on Windows using winget.
# It installs or updates a list of applications, including Visual Studio, Python, and others.
# It also sets the execution policy to Unrestricted to allow script execution.
#
# IMPORTANT: This script must be run from an elevated PowerShell prompt.
# Run with: pwsh.exe -ExecutionPolicy Bypass -Command "& {path\to\apps_install.ps1}"

# Check if running as administrator - required for installation
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script requires administrator privileges. Please run PowerShell as administrator and try again."
    exit 1
}

# Set execution policy to unrestricted
Write-Host "Setting execution policy to Unrestricted..."
try {
    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force
    Write-Host "Execution policy set successfully." -ForegroundColor Green
} catch {
    Write-Host "Failed to set execution policy: $_" -ForegroundColor Red
}

# Rest of your script
$applications = @(
    "Microsoft.VisualStudioCode",
    "Google.Chrome.Canary",  
    "Git.Git",
    "Kitware.CMake",
    "astral-sh.uv",
    "Microsoft.VisualStudio.2022.Community",
    "Ollama.Ollama",
    "Python.Python.3.13",
    "CondaForge.Miniforge3"
)

# Loop through each application
foreach ($app in $applications) {
    # Check if the application is already installed
    if (winget list | Select-String -Pattern $app) {
        # Application is already installed, upgrade it
        Write-Host "Updating $app..." -ForegroundColor Cyan
        winget update $app
    } else {
        # Check for special cases that need custom installation flags
        Write-Host "Installing $app..." -ForegroundColor Yellow
        if ($app -eq "Microsoft.VisualStudio.2022.Community") {
            # Install Visual Studio with specific workloads and auto-accept license terms
            winget install --silent --accept-source-agreements --accept-package-agreements --force --id $app --override "--add Microsoft.VisualStudio.Workload.ManagedDesktop;includeRecommended --add Microsoft.VisualStudio.Workload.NativeDesktop;includeRecommended --quiet --norestart --includeRecommended --wait"
        } 
        else {
            # Install all other applications with silent options and force flag
            winget install --silent --accept-package-agreements --accept-source-agreements --force --id $app
        }
    }
}

Write-Host "Script completed successfully!" -ForegroundColor Green