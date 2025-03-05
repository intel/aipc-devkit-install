# Intel® AI PC Development Kit
## VERSION 2024.10.2 README
### October 30, 2024

## Table of Contents

1. [Introduction](#1-introduction)
2. [System Requirements](#2-system-requirements)
3. [Installation Instructions](#3-installation-instructions)
4. [Uninstallation Instructions](#4-uninstallation-instructions)
5. [Usage Information](#5-usage-information)
6. [Known Issues](#6-known-issues)
7. [License Agreement](#7-license-agreement)


## 1. Introduction

This README file provides comprehensive information about the Intel® AI PC Development Kit.

The Intel® AI PC Development Kit will install the following software on your system:

- **Python**                           : 3.10.11
- **Visual Studio Code**               : 1.91.0
- **Git**                              : 2.46.0
- **Vim**                              : 9.1.0
- **Visual C++ Redistributable**       : 14.32.31332.0
- **Cmake**                            : 3.30.2
- **OpenCV**                           : 4.10.0
- **Intel Driver & Support Assistant** : 24.4.32.8
- **OpenVino**                         : 2024.4.1
- **OpenVino Notebooks**               : 2024.4
- **Intel Demos**                      : 2024.4
- **Open Model Zoo**                   : 2024.3.0
- **Dependent Python Modules**

## 2.  System Requirements

- **Operating System**: Windows 11
- **Internet Connection**: Required
- **Environment Variables**:
  - `PIP_TRUSTED_HOST=pypi.org files.pythonhosted.org`
  - Ensure the Git path is included in the system environment variable, e.g., `set PATH=%PATH%;C:\Program Files\Git\bin`

## 3.  Installation Instructions

**Note 1:** These steps are not required, if the system is pre-installed.

**Note 2:** If you are building the installer from source with the help of REAMDE.md(#README.md), then skip first 3 steps and continue with step 4

1. Copy `IntelAIPCDevkit_2024.10.2.zip` to `C:\Intel\Setup`.
2. Unzip the contents of the zip file into the `Setup` folder.
3. Navigate to `C:\Intel\Setup\IntelAIPCDevkit_2024.10.2`.
4. Run `installer.exe` with administrative privileges.
5. The license agreement will appear. Click "I accept the license agreement" to start the installation.
6. Click "Install".
7. The installation will begin, and the software listed in section 1 will be installed sequentially.
8. Accept the licenses as needed.
9. The installations will proceed with default options.
10. After the installation completes, the AI PC virtual environment will be available, and Jupyter Notebook will open in the browser.

## 4.  Uninstallation Instructions

1. The uninstaller can be found at `C:\Intel\aipcdevkit`.
2. Run `uninstall.exe` with administrative privileges to remove all the software installed during the installation process. Note that the Intel Driver & Support Assistant (IDSA) will not be uninstalled.
3. Uninstallation logs will not be removed and can be found at `C:\Intel\UninstallLogs`.

## 5. Usage Information

1. Set up your browser to enable WebNN flags. This is not enabled by default for security reasons.
   - **Google Chrome**: Type `chrome://flags` in the browser and search for WebNN. Select "Enabled" in the dropdown that appears.
   - **Microsoft Edge**: Type `edge://flags` in the browser and search for WebNN. Select "Enabled" in the dropdown that appears.
2. You can restart Jupyter Labs anytime after the installation by running `start_lab.cmd` from `C:\Intel\aipcdevkit`.

## 6. Known Issues

1. **Unable to download software**:
   - Ensure Internet connection is available and proxies are set as required.
2. **Jupyter Kernel not working**:
   - A Jupyter Lab Kernel HTTP Connection error may occur, preventing the installation of Python modules.
   - Add the environment variable: `PIP_TRUSTED_HOST=pypi.org files.pythonhosted.org`.
3. **`git+https` module is not working**:
   - The `git+https` module is not functioning on the dev kit for Jupyter Notebooks, preventing the execution of notebooks that use Hugging Face models and the Intel Optimum package.
   - Add the environment variable: `PIP_TRUSTED_HOST=pypi.org files.pythonhosted.org`.
4. **Internet/Network stability**:
   - The installer requires a stable internet connection as software is downloaded during the installation. The Python modules download timeout is set to 2 minutes. Delays may cause the download/installation of modules to fail.

## 7.  License Agreement

Copyright © 2024 Intel Corporation

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in the
Software without restriction, including without limitation the rights to use, copy,
modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
and to permit persons to whom the Software is furnished to do so, subject to the
following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
