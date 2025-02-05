REM Copyright (C) 2024 Intel Corporation
REM Author: Krishna Lakhotia <krishna.lakhotia@intel.com>
REM Author: Balasubramanyam Agalukote Lakshmipathi <balasubramanyam.agalukote.lakshmipathi@intel.com>

REM This software and the related documents are Intel copyrighted materials, and your use of them is 
REM governed by the express license under which they were provided to you ("License"). Unless the 
REM License provides otherwise, you may not use, modify, copy, publish, distribute, disclose or 
REM transmit this software or the related documents without Intel's prior written permission.

REM This software and the related documents are provided as is, with no express or implied warranties, 
REM other than those that are expressly stated in the License.

@echo off
CD ..
REM Ensuring pip-tools is installed
C:\Python310\python.exe -m pip install pip-tools

REM Compile the requirements and Generating New Requirements.txt
pip-compile Prerequisites\PythonModules\requirementsbase.in -o Prerequisites\PythonModules\requirementsnew.txt

REM Check if requirements.txt exists and rename it if it does
if exist Prerequisites\PythonModules\requirements.txt (
    ECHO Renaming the requirement to requirements_old.txt
    move /Y Prerequisites\PythonModules\requirements.txt Prerequisites\PythonModules\requirements_old.txt
)

REM Copy the new requirements file
ECHO Renaming the newrequirement to requirements.txt
copy /Y Prerequisites\PythonModules\requirementsnew.txt Prerequisites\PythonModules\requirements.txt
