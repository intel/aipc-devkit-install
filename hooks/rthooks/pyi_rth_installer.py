## Copyright (C) 2024 Intel Corporation
## Author: Krishna Lakhotia <krishna.lakhotia@intel.com>
## Author: Balasubramanyam Agalukote Lakshmipathi <balasubramanyam.agalukote.lakshmipathi@intel.com>
##
## This software and the related documents are Intel copyrighted materials, and your use of them is 
## governed by the express license under which they were provided to you ("License"). Unless the 
## License provides otherwise, you may not use, modify, copy, publish, distribute, disclose or 
## transmit this software or the related documents without Intel's prior written permission.
##
## This software and the related documents are provided as is, with no express or implied warranties, 
## other than those that are expressly stated in the License.

import os
import sys
import subprocess
import shutil
import platform
import re

ACLS_CHANGED = False


class ACLChecks:
    _user_allowlist = [
        "ADMINISTRATOR",
        "ADMINISTRATORS",
        "NT AUTHORITY",
        "NT SERVICE",
        "CREATOR",
        "APPLICATION PACKAGE AUTHORITY",
        "NT ",
    ]
    _permissions_blocklist = ["W", "M", "F", "D", "DE", "DC", "WDAC", "GW", "GA", "WD", "AD"]

    def __init__(self, file_name: str) -> None:
        self.file_name = file_name
        system32 = os.path.join(
            os.environ["SystemRoot"], "SysNative" if platform.architecture()[0] == "32bit" else "System32"
        )
        self.icacls_exe = os.path.join(system32, "icacls.exe")

    def get_acls(self):
        acls = []
        cmd = [self.icacls_exe, self.file_name, "/Q"]
        try:
            output = subprocess.run(cmd, check=True, stdout=subprocess.PIPE, text=True).stdout
            for line in output.splitlines():
                line = line.replace(self.file_name, "").strip().upper()
                if line and not "SUCCESSFULLY PROCESSED" in line and not "FAILED PROCESSING" in line:
                    acls.append(line)
        except (subprocess.CalledProcessError, OSError):
            pass
        return acls

    def remove_inheritance(self):
        cmd = [self.icacls_exe, self.file_name, "/inheritancelevel:r", "/Q"]
        try:
            subprocess.call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except:
            pass

    def get_unsafe_users(self, acls=None):
        unsafe_users = []
        if not acls:
            acls = self.get_acls()
        for user in acls:
            if not any(allowed_user in user for allowed_user in self._user_allowlist):
                unsafe_users.append(user)
        return unsafe_users

    def unsafe_permission(self, acls=None):
        unsafe = False
        for user in self.get_unsafe_users(acls=acls):
            acl_list = re.sub(r"[\(\)\s+]", ",", user.partition(":")[-1])
            acl_list = [acl.strip() for acl in acl_list.split(",") if acl.strip()]
            if any(permission in acl_list for permission in self._permissions_blocklist):
                unsafe = True
                break

        return unsafe

    def fix_user_permissions(self, acls=None):
        user_has_permission = False
        current_user = os.getlogin()
        if not acls:
            acls = self.get_acls()
        if any(current_user.upper() in acl_user for acl_user in acls):
            user_has_permission = True
        if not acls:
            subprocess.call(
                [self.icacls_exe, self.file_name, "/grant", current_user + ":(R)", "/Q", "/T"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            subprocess.call(
                [self.icacls_exe, self.file_name, "/grant", "Administrator" + ":(F)", "/Q", "/T"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            subprocess.call(
                [self.icacls_exe, self.file_name, "/grant", "System" + ":(F)", "/Q", "/T"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return

        for i in acls:
            t = i.strip().split(":")
            try:
                u = t[0].strip().split("\\")[-1]
                p = t[1].strip()
            except:
                continue

            if "administrator" in u.lower() or "system" in u.lower():
                subprocess.call(
                    [self.icacls_exe, self.file_name, "/grant", u + ":(F)", "/Q", "/T"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                continue
            subprocess.call([self.icacls_exe, self.file_name, "/remove", u, "/Q", "/T"])
            subprocess.call(
                [self.icacls_exe, self.file_name, "/grant", u + ":(R)", "/Q", "/T"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

        if not user_has_permission:
            subprocess.call(
                [self.icacls_exe, self.file_name, "/grant", current_user + ":(R)", "/Q", "/T"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

    def reset_permissions(self):
        cmd = [self.icacls_exe, self.file_name, "/reset", "/t"]
        try:
            subprocess.call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except:
            pass


def move_dlls(current_dir: str, destination_dir: str, restore: bool = False):
    if not os.path.isdir(current_dir):
        return
    # restore should be set True when moving the dlls back to the original dir
    if not restore:
        try:
            shutil.rmtree(destination_dir)
        except:
            pass
        try:
            os.makedirs(destination_dir, exist_ok=True)
        except:
            pass

    for dll_file in os.listdir(current_dir):
        if dll_file.casefold().endswith(".dll"):
            try:
                shutil.move(os.path.join(current_dir, dll_file), destination_dir)
            except:
                pass

    if restore:
        # If restore=True, the temporary folder(current_dir) created should be deleted
        try:
            shutil.rmtree(current_dir)
        except:
            pass


def restore_original(temporary_dir, application_dir, acl_changed=False):
    if acl_changed:
        acl_check = ACLChecks(file_name=application_dir)
        acl_check.reset_permissions()
        global ACLS_CHANGED
        ACLS_CHANGED = False
    move_dlls(temporary_dir, application_dir, restore=True)


def _pyi_rthook():
    application_dir = os.path.dirname(sys.executable)
    relocation_dir = os.path.join(application_dir, "temporary_folder_AIDevKit")
    move_dlls(application_dir, relocation_dir)
    acl_check = ACLChecks(file_name=application_dir)
    current_acls = acl_check.get_acls()
    if acl_check.unsafe_permission(acls=current_acls):
        global ACLS_CHANGED
        ACLS_CHANGED = True
        acl_check.remove_inheritance()
        acl_check.fix_user_permissions(acls=current_acls)


if __name__ == "__main__":
    _pyi_rthook()
    del _pyi_rthook
