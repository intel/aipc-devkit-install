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

    - name: Verify PyInstaller Installation
      run: |
        python --version
        pyinstaller --version
      shell: pwsh
      # This step verifies the installation of PyInstaller by checking its version.