# Intel(R) AI PC Development Kit
## VERSION 2024.10.2 README
### October 30 2024.

## README Contents

1.  [Introduction](#1-introduction)
2.  [Requirements](#2-requirements)
3.  [Build Instructions](#2-build-instructions)
4.  [Installation](#4-installation)
5.  [Running Notebooks](#5-running-notebooks)

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
6. `installer.exe` will created under `dist` folder.

## 4. Installation

Follow the instructions in [README.md](README.md) from point 4 under **Installation Instructions**. Installation will be done under `C:\Intel\aipcdevkit`. After the installation completes, the AI PC virtual environment will be available, and Jupyter Notebook will open in the browser.

## 5. Running Notebooks

In the browser navigate to one of the following notebooks and run it to verify correct execution (requires internet connection).
- hello-world\hello-world.ipynb
- llm-chatbot\llm-chatbot.ipynb
- yolov8-optimization\yolov8-instance-segmentation.ipynb
