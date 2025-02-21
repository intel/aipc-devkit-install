# Setup Python and Package

This GitHub Action sets up Python and installs necessary packages.

## Inputs

- `python-version` (optional): Python version to use. Default is `3.10.11`.

## Permissions

This action requires read permissions for all available permissions.
```yaml
permissions: read-all
```

## Usage

```yaml

name: Setup Python and Package
description: This action sets up Python and installs necessary packages.
inputs:
  python-version:
    description: 'Python version to use'
    required: false
    default: '3.10.11'
    
runs:
  using: "composite"
  steps:
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.10.11'
      # This step sets up the Python environment with the specified version.

    - name: Verify Python in PATH and Install dependencies
      run: |
        python --version
        python -m pip install --upgrade pip
        python -m pip install pyinstaller
        python -m pip install pyinstaller-versionfile
      shell: pwsh
      # This step verifies Python is in the PATH and installs necessary dependencies using pip.

    - name: Copy Python to C:\Python310
      run: |
        $pythonPath = (Get-Command python).Path
        $pythonDir = Split-Path -Parent $pythonPath
        if (-Not (Test-Path -Path "C:\Python310")) {
          New-Item -ItemType Directory -Path "C:\Python310"
        }
        Copy-Item -Path "$pythonDir\*" -Destination "C:\Python310" -Recurse -Force
      shell: pwsh
      # This step copies the Python installation to C:\Python310.

    - name: Verify Python Installation
      run: |
        if (Test-Path -Path "C:\Python310\python.exe") {
          Write-Host "Python installed successfully."
          C:\Python310\python.exe --version
        } else {
          Write-Error "Python installation failed."
          exit 1
        }
      shell: pwsh
      # This step verifies the Python installation by checking if python.exe exists in C:\Python310.

    - name: Set up environment variables for Python
      run: |
        $newPath = "C:\Python310\Scripts;$env:PATH"
        $env:PATHS = "C:\Python310;C:\Python310\Scripts;" + $env:PATH
        [System.Environment]::SetEnvironmentVariable("PATH", $newPath, [System.EnvironmentVariableTarget]::Process)
        [System.Environment]::SetEnvironmentVariable("PATH", $PATHS, [System.EnvironmentVariableTarget]::Process)
        Write-Output "Updated PATH: $newPath"
        Write-Output "Updated PATHS: $PATHS"
        $env:PYTHONPATH = "C:\Python310"
      shell: pwsh
      # This step sets up the environment variables for Python.

    - name: Verify PyInstaller Installation
      run: |
        python --version
        pyinstaller --version
      shell: pwsh
      # This step verifies the installation of PyInstaller by checking its version.