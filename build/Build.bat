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
set arg1=%BuildVersion%
IF "%arg1%"=="" set arg1=1.1.0.0

create-version-file installer_metadata.yml --outfile file_version_info.txt --version %arg1%

REM Verify the version file creation
if not exist file_version_info.txt (
    echo file_version_info.txt was not created.
    exit /b 1
)

pyinstaller --clean --onefile Script/ui_installer.py --add-data Configuration/installation_config.json:. --add-data License.txt:. --add-data Prerequisites/PythonModules/requirements.txt:Prerequisites/PythonModules/requirements.txt --paths Script --paths hooks\rthooks --version-file=file_version_info.txt --name installer.exe --runtime-hook hooks\rthooks\pyi_rth_installer.py --add-binary C:/Python310/python3.dll:.

create-version-file uninstaller_metadata.yml --outfile file_version_info.txt --version %arg1%
pyinstaller --clean --onefile Script/uninstall.py --add-data Configuration/installation_config.json:. --add-data Prerequisites/PythonModules/requirements.txt:Prerequisites/PythonModules/requirements.txt --paths Script --paths hooks\rthooks --version-file=file_version_info.txt --runtime-hook hooks\rthooks\pyi_rth_installer.py --add-binary C:/Python310/python3.dll:.
