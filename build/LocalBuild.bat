@echo off
REM Copyright (C) 2024 Intel Corporation
REM Author: Krishna Lakhotia <krishna.lakhotia@intel.com>
REM Author: Balasubramanyam Agalukote Lakshmipathi <balasubramanyam.agalukote.lakshmipathi@intel.com>

REM This software and the related documents are Intel copyrighted materials, and your use of them is 
REM governed by the express license under which they were provided to you ("License"). Unless the 
REM License provides otherwise, you may not use, modify, copy, publish, distribute, disclose or 
REM transmit this software or the related documents without Intel's prior written permission.

REM This software and the related documents are provided as is, with no express or implied warranties, 
REM other than those that are expressly stated in the License.

echo " Start Building Intel AI PC Development Kit"
CD ..
create-version-file installer_metadata.yml --outfile file_version_info.txt
pyinstaller --clean --onefile Script/installer.py --add-data Configuration/installation_config.json:. --version-file=file_version_info.txt

create-version-file uninstaller_metadata.yml --outfile file_version_info.txt
pyinstaller --clean --onefile Script/uninstall.py --add-data Configuration/installation_config.json:. --paths Script --version-file=file_version_info.txt

echo " Start Building Intel AI PC Development Kit zip file"
cd Build
.\7ZipToImage\7ZipToImage-1.0.0\7za.exe a ..\dist\IntelAIPCDevelopmentKit.zip ..\dist\installer.exe
.\7ZipToImage\7ZipToImage-1.0.0\7za.exe a -xr@exclude.txt ..\dist\IntelAIPCDevelopmentKit.zip ..\Prerequisites
.\7ZipToImage\7ZipToImage-1.0.0\7za.exe a -xr@exclude.txt ..\dist\IntelAIPCDevelopmentKit.zip ..\AIDevKit
