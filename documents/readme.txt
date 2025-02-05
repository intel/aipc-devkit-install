-----------------------------------------------------------------------
Intel(R) AI PC Development Kit
VERSION 2024.10.2 README
October 30 2024.
-----------------------------------------------------------------------


README Contents
============================================
1.  Introduction
2.  System Requirements
3.  Installation Instructions
4.  Uninstallation Instructions
5.  Usage Information
6.  Known Issues
7.  License Agreement


1. Introduction
============================================
This readme file contains information on the Intel(R) AI PC Development Kit

The Intel(R) AI PC Development Kit will install below listed softwares on your system:

- Python                           : 3.10.11
- Visual Studio Code               : 1.91.0
- Git                              : 2.46.0
- Vim                              : 9.1.0
- Visual C++ Redistributable       : 14.32.31332.0
- Cmake                            : 3.30.2
- OpenCV                           : 4.10.0
- Intel Driver & Support Assistant : 24.4.32.8
- OpenVino                         : 2024.4.1
- OpenVino Notebooks               : 2024.4
- Intel Demos                      : 2024.4
- Open Model Zoo                   : 2024.3.0
- Dependent Python Modules

2.  System Requirements
============================================
a. Windows 11 Operating System.
b. The system must be connected to the Internet.
c. Set system environment variables:
	1c. PIP_TRUSTED_HOST= pypi.org files.pythonhosted.org

3.  Installation Instructions
============================================
a. Copy IntelAIPCDevkit_2024.10.2.zip in C:\Intel\Setup.
b. Unzip the contents of the zip to the Setup folder.
c. Traverse to C:\Intel\Setup\IntelAIPCDevkit_2024.10.2 folder
d. Run “installer.exe” with admin privileges. 
e. The license agreement will appear, click on "I accept the license agreement" to start installation. 
f. Click on Install.
g. Installation will start, software's lusted in section 1 will be installed in a sequence.
h. Accept the licenses as needed.
i. The installations will continue with default installation options.
j. After the installation completes, the AI PC virtual environment will be available, Jupyter Notebook will open in the browser.

4.  Uninstallation Instructions
============================================
1. The uninstaller can be found in the path - C:\Intel\aipcdevkit
2. Run uninstall.exe with admin privileges to remove all the software's that were installed as part of the installation process. Please note that IDSA is not uninstalled as part of this.
3. Uninstallation logs also will not be removed and can be found in the path - C:\Intel\UninstallLogs 

5. Usage Information
============================================

a. Setup browser to enable WebNN flags. This is not enabled by default for security reasons.
- For Google Chrome: Type chrome://flags in the browser and search for WebNN. Select Enabled in the dropdown that appears.
- For Microsoft Edge: Type edge://flags in the browser and search for WebNN. Select Enabled in the dropdown that appears.

b.You can restart Jupyter labs anytime after the installation, by running start_lab.cmd from the path - C:\Intel\aipcdevkit.

6. Known Issues
============================================
a. Unable to download software's listed in section 2.4
Make sure proxies are SET as required.

b. Jupyter Kernel not working
Jupyter Lab Kernel HTTP Connection error is observed, due to which no python modules are able to install.

Add Environment variable - PIP_TRUSTED_HOST= pypi.org files.pythonhosted.org 

c. git+https module is not working
git+https module is not working on dev kit for jupyter notebooks thats why not able to run any notebooks which uses huggingface model and intel optimum package.

Add Environment variable - PIP_TRUSTED_HOST= pypi.org files.pythonhosted.org 

7.  License Agreement
============================================

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
