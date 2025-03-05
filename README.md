# Intel<span style="font-size: 20px;"><sup>® </sup></span> AI PC Development Kit
#### Version 2024.10.2
#### October 30 2024

## README Contents

1.  [Introduction](#1-introduction)
2.  [Requirements](#2-requirements)
3.  [Build Instructions](#3-build-instructions)
4.  [Installation](#4-installation)
5.  [Running Notebooks](#5-running-notebooks)
6.  [License Agreemen](#6-license-agreement)

## 1. Introduction

The Intel® AI PC Development Kit is designed to equip AI developers with a comprehensive suite of tools, libraries, and frameworks necessary for building, training, and deploying AI systems. 

This kit facilitates the entire AI development lifecycle, from data preprocessing and model training to deployment and monitoring. 

This readme file contains information on how to build the installer for the Intel® AI PC Development Kit from the source code. 

## 2. Requirements

1. **Operating System**: Windows 11.
2. **Internet Connection**: Required. Please include proxy settings as needed.
3. **Python**: Version 3.10.11 installed under `C:\python310` with path variable updated.
4. **System environment variable**:
    - `PIP_TRUSTED_HOST= pypi.org files.pythonhosted.org`

## 3. Build Instructions

Follow the below steps:
1. Open a command line terminal and clone the repo.
    - `git clone https://github.com/intel/aipc-devkit-install.git`
2. Change the working directory to the repo folder `aipc-devkit-install`.
3. Create the Virtual environment with python 3.10
    - If multiple versions of python is installed in the system, use below command
        - `py -3.10 -m venv venv`
    - If only python 3.10 version is installed in the system, use below command
        - `python -3.10 -m venv venv`
4. Activate the Virtual environment
    - `.\venv\Scripts\activate`
5. Install "pyinstaller" and "pyinstaller_versionfile" modules (Make sure proxy is included as needed)
    - `pip install pyinstaller`
    - `pip install pyinstaller_versionfile`
6. Set a version for the Build
    - `set BuildVersion=1.1.0.0`
7. Build the installer
    - `cd build`
    - `Run Build.bat`
8. `installer.exe` and `uninstall.exe` is created under `dist` folder.

## 4. Installation

1. Copy the `installer.exe` and `uninstall.exe` under repo folder `aipc-devkit-install`.
2. Continue with the installation process by following the steps provided in the [Installation_Guide.md](Installation_Guide.md) starting from section 4 - **Installation Instructions**. This will guide you through the remaining installation steps to complete installation under `C:\Intel\aipcdevkit`. 
3. Once the installation is complete, the AI PC virtual environment will be set up, and Jupyter Notebook will automatically open in your browser.

## 5. Running Notebooks

In Jupiter notebooks browser, navigate to one of the following notebooks and run it to verify correct execution (requires internet connection).
- hello-world\hello-world.ipynb
- llm-chatbot\llm-chatbot.ipynb
- yolov8-optimization\yolov8-instance-segmentation.ipynb

## 6. License Agreement

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
