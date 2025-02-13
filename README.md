# Intel(R) AI PC Development Kit
## VERSION 2024.10.2 README
### October 30 2024.

## README Contents

1.  [Introduction](#1-introduction)
2.  [Requirements](#2-requirements)
3.  [Build Instructions](#3-build-instructions)
4.  [Installation](#4-installation)
5.  [Running Notebooks](#5-running-notebooks)
6.  [License Agreemen](#6-license-agreement)

## 1. Introduction

This readme file contains information on how to build the installer for the Intel(R) AI PC Development Kit

## 2. Requirements

1. Windows 11 Operating System.
2. The system must be connected to the Internet.
3. Python version 3.10.11 is installed for all user under C:\Python310 and PATH environment is updated
4. Set system environment variables:
    PIP_TRUSTED_HOST= pypi.org files.pythonhosted.org

## 3. Build Instructions

Follow the below steps
1. Create the Virtual environment
    python -m venv venv
2. Activate the Virtual environment
    .\venv\Scripts\activate
3. Install "pyinstaller" and "pyinstaller_versionfile" modules
    pip install pyinstaller
    pip installer pyinstaller_versionfile
4. Set a version for the Build
    set BuildVersion=1.1.0.dev0
5. Build the installer
    cd Build
    Run Build.bat
6. `installer.exe` and `uninstall.exe` is created under `dist` folder.

## 4. Installation

1. Copy the `installer.exe` and `unstall.exe` under repo root folder.
2. Follow the instructions in [Installation_Guide.md](Installation_Guide.md) from point 4 under **Installation Instructions**. Installation will be done under `C:\Intel\aipcdevkit`. After the installation completes, the AI PC virtual environment will be available, and Jupyter Notebook will open in the browser.

## 5. Running Notebooks

In the browser navigate to one of the following notebooks and run it to verify correct execution (requires internet connection).
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
