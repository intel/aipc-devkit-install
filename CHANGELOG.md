# AIPCDevKit Changelog
AIPCDevKit Release Notes

All notable changes to this project will be documented in this file.

## ReleaseVersion: [2024.10.2] - 2024-10-28

### Prerequisite
Download and install the following package version
| Software                         | Version         | Description                            |
|-|-|-|

### Sofware/Archive Versions
| Software/Archive                 | Version         |
|-|-|
| Visual Studio Code               | 1.91.0          |
| Git                              | 2.46.0          |
| Vim                              | 9.1.0           |
| Visual C++ Redistributable       | 14.32.31332.0   |
| Cmake                            | 3.30.2          |
| OpenCV                           | 4.10.0          |
| Intel Driver & Support Assistant | 24.4.32.8       |
| Python                           | 3.10.11         |
| OpenVino                         | 2024.4.1        |
| OpenVino Notebooks               | 2024.4          |
| Intel Demos                      | 2024.4          |
| Open Model Zoo                   | 2024.3.0        |

### Feature Added
- Added working samples

### Feature Changed / Modified
- Added option to include specific members from an archive

### Feature Deprecated
No

### Feature Removed
None

### Issues Fixed
None

### Security Issues Fixed
None

### New Issues
None

### Source Repo
- https://github.com/intel/aipc-devkit-install

## ReleaseVersion: [2024.10.1] - 2024-10-08

### Prerequisite
Download and install the following package version
| Software                         | Version         | Description                            |
|-|-|-|

### Sofware/Archive Versions
| Software/Archive                 | Version         |
|-|-|
| Visual Studio Code               | 1.91.0          |
| Git                              | 2.46.0          |
| Vim                              | 9.1.0           |
| Visual C++ Redistributable       | 14.32.31332.0   |
| Cmake                            | 3.30.2          |
| OpenCV                           | 4.10.0          |
| Intel Driver & Support Assistant | 24.4.32.8       |
| Python                           | 3.10.11         |
| OpenVino                         | 2024.4.1        |
| OpenVino Notebooks               | 2024.4          |
| Open Model Zoo                   | 2024.3.0        |


### Feature Added                  
- Added signing of installer
- Added Git soruce tar ball
- Added File version and other details embedded in the installer.exe
- Added uninstall option in installer and an uninstall script
- Added option to install specific softwares
- Added option to install softwares from online
- Added option to download and extract archives
- Added UI to display license and install

### Feature Changed / Modified     
- Moved the path values from script to configuration file
- Changed silent install options for IDSA
- Changed python installation to be interactive
- Changed the path of Logs directory inside the installation directory
- Changed the starting directory for jupyter lab to openvino_notebooks
- Upgraded versions of Git, Cmake, OpenCV and  python modules based on BDBA Vulnerabilities
- Install python wheels online
- Install all softwares from online
- Changed checksum from md5 sha256
- Remove only the version of VC++ installed by the installer
- requirements.txt to be part of the installer.exe
- Upgraded pytorch version and upgraded openvino notebooks
                                   
### Feature Deprecated             
None                               
                                   
### Feature Removed
None
                                   
### Issues Fixed                   
- Fixed bandit scan and checkmarx issues
- Fixed OpenVino version Issues

### Security Issues Fixed          
None                               

### New Issues
None

### Source Repo
- https://github.com/intel/aipc-devkit-install

