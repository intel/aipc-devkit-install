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

import argparse
import subprocess
import os
import sys
import logging
import shutil
import json
import winreg
import string
import time
from winreg import KEY_WOW64_32KEY, KEY_WOW64_64KEY, KEY_READ
from typing import Dict, List, Any, Tuple
import ctypes
import warnings
import re
from abc import ABC, abstractmethod
import shlex
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError
import ssl
from hashlib import sha256
from zipfile import ZipFile, ZipInfo, ZIP_STORED
from version import VERSION
import contextlib

with warnings.catch_warnings():
    warnings.filterwarnings("ignore", category=DeprecationWarning)
    from pkg_resources import parse_version
from dataclasses import dataclass, field

# This is to check if running from a bundle(exe created from pyinstaller) or as python script
if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
    EXE_PATH = sys._MEIPASS
    CURRENT_DIR_PATH = os.path.dirname(sys.executable)
    FILE_NAME = os.path.basename(sys.executable)
    CALLER_COMMAND = sys.executable
else:
    CURRENT_DIR_PATH = os.path.dirname(os.path.realpath(__file__))
    EXE_PATH = CURRENT_DIR_PATH
    FILE_NAME = os.path.basename(__file__)
    CALLER_COMMAND = f"{sys.executable} {__file__}"

configuration_file = os.path.join(EXE_PATH, "installation_config.json")
if not os.path.isfile(configuration_file):
    logging.error(f"The configuration file: {configuration_file} does not exist")
    sys.exit(1)

with open(configuration_file, "r") as config_file:
    configurations = json.load(config_file)

default_paths = configurations.get("default_paths", {})
logger = logging.getLogger()


def remove_unwanted_characters(line: str):
    printable = set(string.printable)
    return "".join(filter(lambda x: x in printable, line))


def split_command(command: str):
    new_command = []
    if command.startswith(('"', "'", "MsiExec.exe")):
        new_command = shlex.split(command)
    else:
        new_command = [command]

    return new_command


@dataclass
class Installation:
    installers_dir_path: str
    installer_path: str
    installer_exe: str
    install_flags: List[str] = field(default_factory=list)
    install_command: List[str] = field(default_factory=list)
    quiteinstall_flags: List[str] = field(default_factory=list)
    download_url: str = field(default="")
    online: bool = field(default=False)
    checksum: str = field(default="")
    max_file_size: int = field(default=1024 * 1024 * 1024)

    def identify_installer_exe(self, log_error: bool = True):
        """
        The installer_exe can be in a subdirectory under installer_path.
        Need to get the exact installer path
        """
        exe_path = None
        installer_path = get_absolute_path(self.installers_dir_path, self.installer_path)
        exe_path = find_file_in_directory(installer_path, self.installer_exe)
        if not exe_path:
            if log_error:
                logger.error(f"Failed to locate the executable: {self.installer_exe}")

        return exe_path

    def get_install_command(self, log_option: List[str] = None, silent: bool = False):
        install_command = self.install_command
        exe_path = self.identify_installer_exe(log_error=False)
        if not (exe_path and verify_checksum(exe_path, self.checksum)):
            download_file(
                self.installers_dir_path,
                self.installer_path,
                self.installer_exe,
                self.online,
                self.download_url,
                self.max_file_size,
            )
            exe_path = self.identify_installer_exe()
            if not exe_path:
                return None
            if not verify_checksum(exe_path, self.checksum):
                logger.error("The checksum of the file is not valid")
                return None
        install_command.append(exe_path)
        if silent:
            install_command.extend(self.quiteinstall_flags)
        else:
            install_command.extend(self.install_flags)

        if log_option:
            install_command.extend(log_option)

        return install_command


@dataclass
class ArchiveInstallation:
    installers_dir_path: str
    installation_dir: str
    source_path: str
    source_file: str
    destination_dir: str
    members: List[str] = field(default=None)
    download_url: str = field(default="")
    online: bool = field(default=False)
    checksum: str = field(default="")
    max_file_size: int = field(default=1024 * 1024 * 1024)
    skip_top_dir: bool = field(default=False)

    def identify_archive(self, log_error: bool = True):
        """
        The archive can be in a subdirectory under source_path.
        Need to get the exact archive path
        """
        archive_path = None
        installer_path = get_absolute_path(self.installers_dir_path, self.source_path)
        archive_path = find_file_in_directory(installer_path, self.source_file)
        if not archive_path:
            if log_error:
                logger.error(f"Failed to locate the archive: {self.source_file}")

        return archive_path

    def verify_archive(self):
        archive_file = self.identify_archive(log_error=False)
        if not (archive_file and verify_checksum(archive_file, self.checksum)):
            download_file(
                self.installers_dir_path,
                self.source_path,
                self.source_file,
                self.online,
                self.download_url,
                self.max_file_size,
            )
            archive_file = self.identify_archive()
            if not archive_file:
                return None
            if not verify_checksum(archive_file, self.checksum):
                logger.error("The checksum of the file is not valid")
                return None

        return archive_file

    def get_destination_path(self):
        return get_absolute_path(self.installation_dir, self.destination_dir)


@dataclass
class Logs:
    logs_dir: str
    file_name: str = field(default="install.log")
    option: str = field(default="")

    def get_log_option(self):
        if not self.option:
            return []
        if self.option.endswith("="):
            log_option = [self.option.strip() + self.get_log_file()]
        else:
            log_option = [self.option.strip(), self.get_log_file()]
        return log_option

    def get_log_file(self):
        return get_absolute_path(self.logs_dir, self.file_name.strip())


class CmdVersionIdentifier:
    def __init__(self, name: str, command: List[str] = None, options: List[str] = None, delimeter: str = " ") -> None:
        self.name = name
        self.command = command
        self.additional_options = options
        self.delimeter = delimeter

    def get_version_from_command(self):
        if not self.command:
            return None
        cmd = self.command
        if self.additional_options:
            cmd.extend(self.additional_options)
        try:
            result = subprocess.check_output(cmd, text=True, encoding="utf-8").splitlines()[0]
            return result.strip().split(self.delimeter)[-1].strip()
        except (subprocess.CalledProcessError, FileNotFoundError, IndexError):
            pass
        return None


class CMakeCmdVersionIdentifier(CmdVersionIdentifier):
    def __init__(self, name: str, command: List[str] = None, options: List[str] = None, delimeter: str = " ") -> None:
        super().__init__(name, command, options, delimeter)


class PrecheckBase(ABC):
    def __init__(self, name: str, desired_version: str, exact_match: bool = False) -> None:
        self.name = name
        self.desired_version = desired_version
        self.exact_match = exact_match

    def desired_version_installed(self, installed_versions: List[str]):
        if not installed_versions:
            return False
        installed_versions = list(map(parse_version, installed_versions))
        desired_version = parse_version(self.desired_version)
        if self.exact_match:
            return desired_version in installed_versions
        return any(version >= desired_version for version in installed_versions)

    @abstractmethod
    def enabled(self) -> bool:
        pass

    @abstractmethod
    def versions_found(self) -> Tuple[bool, List[str]]:
        pass


class RegistryQuery:
    def __init__(self, hkey: str = winreg.HKEY_LOCAL_MACHINE) -> None:
        self.hkey = hkey

    def get_values(self, registry_key_path: str, names: List[str] = None, arch_key: int = 0):
        values = {}
        try:
            with winreg.OpenKey(self.hkey, registry_key_path, 0, access=KEY_READ | arch_key) as reg_key:
                if not names:
                    names = [winreg.EnumValue(reg_key, index)[0] for index in range(winreg.QueryInfoKey(reg_key)[1])]
                for name in names:
                    try:
                        value, _ = winreg.QueryValueEx(reg_key, name)
                        values[name] = value
                    except (FileNotFoundError, OSError, KeyError, WindowsError, TypeError):
                        pass
        except WindowsError:
            pass
        except Exception as e:
            logger.error(f"get_values: An error occurred while checking the registry: {e}")
        return values

    def get_values_from_subkeys(self, registry_key_path: str, names: List[str] = None, arch_key: int = 0):
        combined_values = {}
        try:
            with winreg.OpenKey(self.hkey, registry_key_path, 0, access=KEY_READ | arch_key) as reg_key:
                sub_key_count, _, _ = winreg.QueryInfoKey(reg_key)
                for index in range(sub_key_count):
                    try:
                        key_name = winreg.EnumKey(reg_key, index)
                        sub_key_path = f"{registry_key_path}\\{key_name}"
                        values = self.get_values(sub_key_path, names, arch_key)
                        if values:
                            combined_values[sub_key_path] = values
                    except (OSError, KeyError):
                        pass
        except (FileNotFoundError, OSError, WindowsError):
            pass
        except Exception as e:
            logger.error(f"get_values_from_subkeys: An error occurred while checking the registry: {e}")

        return combined_values

    def get_32_64_arch_values(self, registry_key_path: str, include_sub_keys: bool = False, names: List[str] = None):
        combined_values = {}
        for arch_key in [KEY_WOW64_64KEY, KEY_WOW64_32KEY]:
            if include_sub_keys:
                combined_values.update(self.get_values_from_subkeys(registry_key_path, names=names, arch_key=arch_key))
            else:
                if not registry_key_path in combined_values:
                    combined_values[registry_key_path] = {}
                combined_values[registry_key_path].update(
                    self.get_values(registry_key_path, names=names, arch_key=arch_key)
                )

        return combined_values


def get_installed_programs(registry_key_path: str = "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall"):
    installed = {}
    hkeys = [winreg.HKEY_LOCAL_MACHINE, winreg.HKEY_CURRENT_USER]
    for hkey in hkeys:
        registry = RegistryQuery(hkey)
        for _, values in registry.get_32_64_arch_values(
            registry_key_path=registry_key_path, include_sub_keys=True
        ).items():
            name, value = values.get("DisplayName"), values.get("DisplayVersion")
            if name and value:
                name = remove_unwanted_characters(name).casefold().strip()
                if name not in installed:
                    installed[name] = []
                installed[name].append(values)

    return installed


def get_registry_value(registry_key_path: str, name: str):
    values_found = []
    hkeys = [winreg.HKEY_LOCAL_MACHINE]
    for hkey in hkeys:
        registry = RegistryQuery(hkey)
        for _, values in registry.get_32_64_arch_values(
            registry_key_path=registry_key_path, include_sub_keys=False, names=[name]
        ).items():
            registry_value = values.get(name)
            if registry_value:
                values_found.append(registry_value)

    return values_found


class RegistryPrecheck(PrecheckBase):
    def __init__(
        self,
        name: str,
        desired_version: str,
        registry_keys: List[str] = None,
        registry_value: str = None,
        check_name_in_installed_softwares: str = None,
        exact_match: bool = False,
    ) -> None:
        self.registry_keys = registry_keys
        if not self.registry_keys:
            self.registry_keys = []
        self.registry_value = registry_value
        self.check_name = check_name_in_installed_softwares
        super().__init__(name, desired_version, exact_match)

    def find_in_installed_softwares(self, **kwargs):
        versions = []
        if not self.check_name:
            return versions
        entries = current_installed_softwares.get(self.check_name.strip().casefold(), [])
        if kwargs:
            entries = [entry for entry in entries if all((entry.get(key) == value) for key, value in kwargs.items())]
        if entries:
            versions = [entry.get(self.registry_value) for entry in entries if entry.get(self.registry_value)]
        return versions

    def enabled(self):
        if self.registry_value and (self.registry_keys or self.check_name):
            return True
        return False

    def get_registry_entries(self, **kwargs):
        registry_entries = []
        registry_entries.extend(self.find_in_installed_softwares(**kwargs))
        for registry_key in self.registry_keys:
            registry_entries.extend(get_registry_value(registry_key_path=registry_key, name=self.registry_value))
        return registry_entries

    def versions_found(self):
        registry_entries = self.get_registry_entries()
        return self.desired_version_installed(registry_entries), registry_entries


class CommandPrecheck(PrecheckBase):
    def __init__(
        self,
        name: str,
        desired_version: str,
        command: List[str] = None,
        options: List[str] = None,
        delimeter: str = " ",
        exact_match: bool = False,
    ) -> None:
        self.command = command
        self.delimeter = delimeter
        self.options = options
        super().__init__(name, desired_version, exact_match)
        common_args = {"name": self.name, "command": self.command, "options": self.options, "delimeter": self.delimeter}
        self.version_identifiers = {"default": CmdVersionIdentifier(**common_args)}

    def get_version(self):
        version_identifier = self.version_identifiers.get(
            self.name.strip().casefold(), self.version_identifiers["default"]
        )
        return version_identifier.get_version_from_command()

    def enabled(self):
        return True if self.command else False

    def versions_found(self):
        cmd_versions_found = []
        cmd_version = self.get_version()
        if cmd_version:
            cmd_versions_found.append(cmd_version)
        return self.desired_version_installed(cmd_versions_found), cmd_versions_found


class DirectoryPrecheck(PrecheckBase):
    def __init__(
        self,
        name: str,
        desired_version: str,
        file_paths: List[str] = None,
        any_path: bool = False,
        exact_match: bool = False,
    ) -> None:
        self.file_paths = file_paths
        self.any_path = any_path
        super().__init__(name, desired_version, exact_match)

    def path_exists(self):
        if not self.file_paths:
            return False
        if self.any_path:
            return any(os.path.exists(file_path) for file_path in self.file_paths)
        return all(os.path.exists(file_path) for file_path in self.file_paths)

    def enabled(self):
        return True if self.file_paths else False

    def versions_found(self):
        dir_versions_found = []
        if self.path_exists():
            dir_versions_found.append(self.desired_version)
        return self.desired_version_installed(dir_versions_found), dir_versions_found


class RegistryDirPrecheck(RegistryPrecheck):
    def __init__(
        self,
        name: str,
        desired_version: str,
        registry_keys: List[str] = None,
        registry_value: str = None,
        check_name_in_installed_softwares: str = None,
        append_path: str = None,
        exact_match: bool = False,
    ) -> None:
        self.append_path = append_path
        super().__init__(
            name, desired_version, registry_keys, registry_value, check_name_in_installed_softwares, exact_match
        )

    def path_check(self):
        exe_paths = self.get_registry_entries()
        if self.append_path:
            exe_paths = [get_absolute_path(exe_path.rstrip("\\"), self.append_path) for exe_path in exe_paths]
        return exe_paths

    def versions_found(self):
        return DirectoryPrecheck(
            name=self.name, desired_version=self.desired_version, file_paths=self.path_check(), any_path=True
        ).versions_found()


class RegistryCmdPrecheck(RegistryDirPrecheck):
    def __init__(
        self,
        name: str,
        desired_version: str,
        registry_keys: List[str] = None,
        registry_value: str = None,
        check_name_in_installed_softwares: str = None,
        append_path: str = None,
        command_options: List[str] = None,
        exact_match: bool = False,
    ) -> None:
        self.command_options = command_options
        super().__init__(
            name,
            desired_version,
            registry_keys,
            registry_value,
            check_name_in_installed_softwares,
            append_path,
            exact_match,
        )

    def versions_found(self):
        found_desired = False
        found_versions = []
        exe_paths = self.path_check()
        for exe_path in exe_paths:
            found, versions = CommandPrecheck(
                name=self.name, desired_version=self.desired_version, command=[exe_path], options=self.command_options
            ).versions_found()
            found_desired |= found
            found_versions.extend(versions)
        return found_desired, found_versions


class Prechecks:
    _supported = {
        "registry": RegistryPrecheck,
        "command_check": CommandPrecheck,
        "directory_check": DirectoryPrecheck,
        "registry_cmd_check": RegistryCmdPrecheck,
        "registry_dir_check": RegistryDirPrecheck,
    }

    def __init__(self, name: str, desired_version: str, checks: Dict[str, Any]) -> None:
        self.desired_version = desired_version
        self.verify_prechecks = []
        for precheck, precheck_class in Prechecks._supported.items():
            self.verify_prechecks.append(
                precheck_class(name=name, desired_version=self.desired_version, **checks.get(precheck, {}))
            )

    def versions_found(self):
        found = True
        all_versions = []
        for precheck in self.verify_prechecks:
            if precheck.enabled():
                success, versions_found = precheck.versions_found()
                found &= success
                all_versions.extend(versions_found)

        return found, set(all_versions)


@dataclass
class UnInstallation:
    name: str
    installers_dir_path: str
    desired_version: str
    all_versions: bool = False
    command: Dict[str, str] = field(default_factory=dict)
    registry: Dict[str, str] = field(default_factory=dict)

    def identify_installer_exe(self, installer_path: str, installer_exe: str):
        """
        The installer_exe can be in a subdirectory under installer_path.
        Need to get the exact installer path
        """
        exe_path = None
        installer_path = get_absolute_path(self.installers_dir_path, installer_path)
        exe_path = find_file_in_directory(installer_path, installer_exe)
        if not exe_path:
            logger.error(f"Failed to locate the executable: {installer_exe}")

        return exe_path

    def uninstallation_command_from_exe(self, log_option: List[str] = None, silent: bool = False):
        uninstall_command = self.command.get("uninstall_command", [])
        installer_path = self.command.get("installer_path", "")
        installer_exe = self.command.get("installer_exe", "")
        uninstall_flags = self.command.get("uninstall_flags", [])
        silent_uninstall_flags = self.command.get("quiteuninstall_flags", [])
        exe_path = None
        if installer_exe:
            exe_path = self.identify_installer_exe(installer_path, installer_exe)
            if not exe_path:
                return None
            uninstall_command.append(exe_path)
        if silent:
            uninstall_command.extend(silent_uninstall_flags)
        else:
            uninstall_command.extend(uninstall_flags)

        if log_option:
            uninstall_command.extend(log_option)

        return [uninstall_command]

    def uninstallation_command_from_registry(self, log_option: List[str] = None, silent: bool = False):
        commands = []
        entries = []
        check_names = self.registry.get("check_name_in_installed_softwares", [])
        registry_value = self.registry.get("registry_value", "UninstallString")
        uninstall_flags = self.registry.get("uninstall_flags", [])
        silent_uninstall_flags = self.registry.get("quiteuninstall_flags", [])
        registry_keys = self.registry.get("registry_keys", [])
        if not check_names:
            entries = RegistryPrecheck(
                name=self.name,
                desired_version=self.desired_version,
                registry_keys=registry_keys,
                registry_value=registry_value,
                exact_match=True,
            ).get_registry_entries()
        else:
            for check_name in check_names:
                all_versions_found = [check_name.get("version", self.desired_version)]
                if self.all_versions:
                    all_versions_found = RegistryPrecheck(
                        name=check_name["name"],
                        desired_version=check_name.get("version", self.desired_version),
                        registry_keys=registry_keys,
                        registry_value="DisplayVersion",
                        check_name_in_installed_softwares=check_name["name"],
                        exact_match=not self.all_versions,
                    ).get_registry_entries()
                for version in set(all_versions_found):
                    uninstall_entries = RegistryPrecheck(
                        name=check_name["name"],
                        desired_version=version,
                        registry_keys=registry_keys,
                        registry_value=registry_value,
                        check_name_in_installed_softwares=check_name["name"],
                        exact_match=True,
                    ).get_registry_entries(DisplayVersion=version)
                    entries.extend(uninstall_entries)
        for entry in set(entries):
            command = split_command(entry)
            if silent:
                command.extend(silent_uninstall_flags)
            else:
                command.extend(uninstall_flags)
            if log_option:
                command.extend(log_option)
            commands.append(command)
        return commands

    def get_uninstallation_command(self, log_option: List[str] = None, silent: bool = False):
        uninstall_commands = []
        if self.command:
            uninstall_commands = self.uninstallation_command_from_exe(log_option, silent)
        elif self.registry:
            uninstall_commands = self.uninstallation_command_from_registry(log_option, silent)
        return uninstall_commands


class PostInstall:
    def __init__(
        self, workspace: str, command: List[str], run_on_file_contents: str = "", fallback_command: List[str] = None
    ) -> None:
        self.workspace = workspace
        self.command = command
        self.run_on_file_contents = run_on_file_contents
        self.fallback_command = fallback_command

    def run(self, line: str = None):
        success = True
        error = ""
        exec_cmd = self.command
        exec_fallback_cmd = self.fallback_command if self.fallback_command else []
        if line:
            exec_cmd = exec_cmd + [line]
            exec_fallback_cmd = exec_fallback_cmd + [line] if exec_fallback_cmd else []
        try:
            subprocess.run(exec_cmd, check=True, cwd=self.workspace)
        except (subprocess.CalledProcessError, FileNotFoundError) as ex:
            error = str(ex)
            if exec_fallback_cmd:
                try:
                    subprocess.run(exec_fallback_cmd, check=True, cwd=self.workspace)
                except (subprocess.CalledProcessError, FileNotFoundError) as ex:
                    error = str(ex)
                    success = False
            else:
                success = False

        return success, error

    def postprocess(self):
        logger.info("Running Post-install ...")
        success = True
        if self.run_on_file_contents:
            file_path = find_file_in_directory(self.workspace, self.run_on_file_contents)
            if not file_path:
                error = f"The file does not exist: {self.run_on_file_contents}"
                return False, error
            with open(file_path, "r", encoding="utf-8") as in_file:
                lines = json.load(in_file)
            for line in lines:
                line = line.strip()
                if line:
                    ret, error = self.run(find_file_in_directory(self.workspace, line))
                    success &= ret
        else:
            success, error = self.run()
        if not success:
            logger.error(f"Post install commands failed")
        return success, error


class SoftwareInstall:
    def __init__(
        self,
        software: Dict[str, str],
        installers_dir_path: str,
        logs_dir: str,
        silent: bool = False,
        force_reinstall: bool = False,
        online: bool = False,
    ) -> None:
        self.logs_dir = logs_dir
        self.installers_dir_path = installers_dir_path
        self.silent = silent
        self.force_reinstall = force_reinstall
        os.makedirs(self.logs_dir, exist_ok=True)
        self.name = software["name"]
        self.desired_version = software.get("target_version", "")
        self.installation = Installation(
            installers_dir_path=installers_dir_path, online=online, **software["installation"]
        )
        self.prechecks = Prechecks(self.name, self.desired_version, software.get("prechecks", {}))
        self.logs = Logs(logs_dir=self.logs_dir, **software.get("logs", {}))
        self.post_install = software.get("post_install", [])
        self.installer_path = get_absolute_path(self.installers_dir_path, self.installation.installer_path)

    # Function to compare software versions
    def upgrade_required(self, installed_versions: List[str]):
        if not installed_versions:
            return False
        return all(parse_version(version) < parse_version(self.desired_version) for version in installed_versions)

    def install_required(self):
        logger.info(f"Installing {self.name} ...")
        if self.force_reinstall:
            return True
        desired_version_found, versions_found = self.prechecks.versions_found()
        if desired_version_found:
            logger.info(f"The desired/higher version is already installed for {self.name}: {versions_found}")
            return False
        if self.upgrade_required(versions_found):
            logger.info(f"Older version of {self.name} found. Upgrading to the version: {self.desired_version}")

        return True

    # Function to install software
    def install(self):
        if not self.install_required():
            return True
        install_command = self.installation.get_install_command(
            log_option=self.logs.get_log_option(), silent=self.silent
        )
        if not install_command:
            logger.error(f"Installation failed for {self.name}")
            return False
        # logger.debug(f"Installation command: {install_command}")
        try:
            subprocess.run(install_command, text=True, encoding="utf-8", check=True, cwd=self.installer_path)
            if not self.post_process():
                return False
            logger.info(f"Installation completed successfully for {self.name}.")
            return True
        except subprocess.CalledProcessError:
            logger.error(f"Installation failed for {self.name}")
            logger.error(f"Please check the logs for more details: {self.logs.get_log_file()}")

        return False

    def post_process(self):
        success = True
        for post_cmd in self.post_install:
            post_install = PostInstall(workspace=self.installer_path, **post_cmd)
            ret, _ = post_install.postprocess()
            success &= ret
        return success


class SoftwareUninstall:
    def __init__(self, software: Dict[str, str], installers_dir_path: str, logs_dir: str, silent: bool = False):
        self.logs_dir = logs_dir
        self.installers_dir_path = installers_dir_path
        os.makedirs(self.logs_dir, exist_ok=True)
        self.name = software["name"]
        self.desired_version = software.get("target_version", "")
        self.uninstallation_spec = software.get("uninstallation", {})
        self.uninstallation = UnInstallation(
            name=self.name,
            installers_dir_path=installers_dir_path,
            desired_version=self.desired_version,
            **self.uninstallation_spec,
        )
        self.exact_match = self.uninstallation.all_versions is False
        prechecks = {
            key: {**value, **{"exact_match": self.exact_match}} for key, value in software.get("prechecks", {}).items()
        }
        self.prechecks = Prechecks(self.name, self.desired_version, prechecks)
        self.logs = Logs(logs_dir=self.logs_dir, **software.get("logs", {}))
        self.silent = silent

    def uninstall_required(self):
        if not self.uninstallation_spec:
            return False
        logger.info(f"Un-Installing {self.name} ...")
        desired_version_found, versions_found = self.prechecks.versions_found()
        if self.exact_match and desired_version_found:
            return True
        if not self.exact_match and versions_found:
            return True
        logger.info(f"The version is not installed on the system for {self.name}: {self.desired_version}")

        return False

    def uninstall(self):
        ret = True
        if not self.uninstall_required():
            return True
        uninstall_commands = self.uninstallation.get_uninstallation_command(
            log_option=self.logs.get_log_option(), silent=self.silent
        )
        if not uninstall_commands:
            logger.error(f"Un-Installation command not found for: {self.name}")
            return False
        for uninstall_command in uninstall_commands:
            try:
                subprocess.run(uninstall_command, text=True, encoding="utf-8", check=True)
            except subprocess.CalledProcessError:
                logger.error(f"Un-Installation failed for {self.name}. Command: {uninstall_command}")
                logger.error(f"Please check the logs for more details: {self.logs.get_log_file()}")
                ret &= False
            except FileNotFoundError:
                logger.error(f"Un-Installation failed for {self.name}")
                logger.error(f"Could not locate the uninstaller: {uninstall_command}")
                ret &= False

        if ret:
            logger.info(f"Un-Installation completed successfully for {self.name}.")
        return ret


class ArchiveInstall:
    def __init__(
        self,
        archive: Dict[str, str],
        installers_dir_path: str,
        installation_dir: str,
        force_reinstall: bool = False,
        online: bool = False,
    ) -> None:
        self.installers_dir_path = installers_dir_path
        self.installation_dir = installation_dir
        self.force_reinstall = force_reinstall
        self.online = online
        self.name = archive["name"]
        self.desired_version = archive.get("target_version", "")
        self.archive = ArchiveInstallation(
            installers_dir_path=self.installers_dir_path,
            installation_dir=self.installation_dir,
            online=self.online,
            **archive["installation"],
        )

    def unarchive(self):
        logger.info(f"Installing package for {self.name}")
        archive_path = self.archive.verify_archive()
        if not archive_path:
            logger.error("Archive path not found")
            return False

        if self.archive.skip_top_dir:
            return unzip_file_skip_topdir(
                archive_path, self.archive.get_destination_path(), self.archive.members, self.force_reinstall
            )

        return unzip_file(archive_path, self.archive.get_destination_path(), self.archive.members, self.force_reinstall)


class BatchFileCreation:
    def __init__(self, workspace: str, file_path: str, file_name: str = "AIDevKit.bat") -> None:
        self.workspace = workspace
        self.file_path = get_absolute_path(workspace, file_path)
        self.file_name = get_absolute_path(self.file_path, file_name)

    def create_empty(self):
        with open(self.file_name, "w", encoding="UTF-8") as infile:
            infile.write("@echo off")

    def add_line(self, line: str):
        with open(self.file_name, "a+", encoding="UTF-8") as infile:
            infile.write(f"\n\n")
            infile.write(line)

    def add_bat_file_call(self, bat_file: str):
        with open(self.file_name, "a+", encoding="UTF-8") as infile:
            infile.write(f"\n\n")
            infile.write(
                f'IF NOT EXIST "{bat_file}" echo Please setup the environment using {os.path.join(CURRENT_DIR_PATH, FILE_NAME)} && exit /b 0'
            )
            infile.write(f'\nCALL "{bat_file}"\n')

    def run_file(self):
        command = [self.file_name]
        subprocess.run(command, cwd=self.file_path, check=True)

    def remove_file(self):
        try:
            os.remove(self.file_name)
        except (OSError, FileNotFoundError):
            pass


class SoftwaresToInstall:
    def __init__(self, softwares: List = None) -> None:
        self.softwares = softwares
        if not softwares:
            self.softwares = configurations.get("software_installations", [])

    def get_by_name(self, name: str):
        for software in self.softwares:
            if software.get("name", "").casefold() == name.casefold():
                return software
        return None

    def get_list(self, software_names: List[str] = None):
        softwares_list = []
        if not software_names:
            return self.softwares
        for name in software_names:
            software = self.get_by_name(name=name)
            if software:
                softwares_list.append(software)
        return softwares_list

    def names(self):
        return [software["name"] for software in self.softwares]


# This class is not being used currently
# Would enable this in the next release to add dependency between softwares to be installed
class SoftwaresWithDependency(SoftwaresToInstall):
    def __init__(self, softwares: List = None, software_names: List[str] = None) -> None:
        self.software_names = software_names
        super().__init__(softwares)
        if not software_names:
            self.software_names = self.names()
        self.dependency_list = []

    def find_item(self, name: str):
        return name in self.dependency_list

    def add_dependencies(self, depends_on: List[str] = None):
        if not depends_on:
            depends_on = []
        for name in depends_on:
            if self.find_item(name):
                continue
            dependent_sw = self.get_by_name(name)
            if dependent_sw:
                self.add_dependencies(dependent_sw.get("depends_on", []))
                self.dependency_list.append(name)

    def get_dependency_list(self):
        for name in self.software_names:
            sw = self.get_by_name(name=name)
            if sw:
                self.add_dependencies(sw.get("depends_on", []))
                self.dependency_list.append(name)
        return self.dependency_list

    def get_ordered_list(self):
        ordered_softwares = self.get_dependency_list()
        return self.get_list(ordered_softwares)


class ZipFileExactPath(ZipFile):
    def __init__(
        self, file, mode="r", compression=ZIP_STORED, allowZip64=True, compresslevel=None, *, strict_timestamps=True
    ) -> None:
        super().__init__(file, mode, compression, allowZip64, compresslevel, strict_timestamps=strict_timestamps)

    def _extract_member(self, member, targetpath, pwd):
        """Extract the ZipInfo object 'member' to a physical
        file on the path targetpath.
        """
        if not isinstance(member, ZipInfo):
            member = self.getinfo(member)

        # build the destination pathname, replacing
        # forward slashes to platform specific separators.
        arcname = member.filename.replace("/", os.path.sep)

        if os.path.altsep:
            arcname = arcname.replace(os.path.altsep, os.path.sep)
        # interpret absolute pathname as relative, remove drive letter or
        # UNC path, redundant separators, "." and ".." components.
        arcname = os.path.splitdrive(arcname)[1]
        invalid_path_parts = ("", os.path.curdir, os.path.pardir)
        arcname = os.path.sep.join(x for x in arcname.split(os.path.sep) if x not in invalid_path_parts)
        if os.path.sep == "\\":
            # filter illegal characters on Windows
            arcname = self._sanitize_windows_name(arcname, os.path.sep)

        # Commenting this line to unzip the member to exact targetpath
        # targetpath = os.path.join(targetpath, arcname)
        targetpath = os.path.normpath(targetpath)

        # Create all upper directories if necessary.
        upperdirs = os.path.dirname(targetpath)
        if upperdirs and not os.path.exists(upperdirs):
            os.makedirs(upperdirs)

        if member.is_dir():
            if not os.path.isdir(targetpath):
                os.mkdir(targetpath)
            return targetpath

        with self.open(member, pwd=pwd) as source, open(targetpath, "wb") as target:
            shutil.copyfileobj(source, target)

        return targetpath


current_installed_softwares = get_installed_programs()


def download_file(
    installers_dir_path: str,
    installer_path: str,
    installer_exe: str,
    online: bool = False,
    download_url: str = None,
    max_file_size=1024 * 1024 * 1024,
):
    if not online or not download_url or not download_url.casefold().startswith("http"):
        return None
    installer_path = get_absolute_path(installers_dir_path, installer_path)
    os.makedirs(installer_path, exist_ok=True)
    file_path = os.path.join(installer_path, installer_exe)
    ssl_file = os.getenv("SSL_CA_CERTIFICATE_FILE", None)
    ssl_path = os.getenv("SSL_CA_CERTIFICATES_PATH", None)
    ctx = ssl.create_default_context(cafile=ssl_file, capath=ssl_path)
    if not (ssl_file or ssl_path):
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    try:
        logger.info(f"Downloading the file: {download_url}")
        req = Request(url=download_url)
        with contextlib.closing(urlopen(req, context=ctx, timeout=300)) as response:
            file_size = response.getheader("Content-Length")
            if file_size and int(file_size) > int(max_file_size):
                logger.error(f"File size exceeds the limit: {max_file_size} bytes")
                return None

            if response.status in (200, 201):
                bs = 1024 * 1024
                with open(file_path, mode="wb") as exe_file:
                    while block := response.read(bs):
                        exe_file.write(block)
            else:
                logger.error(f"Failed to connect to: {download_url}")
                return None
    except (URLError, HTTPError, TimeoutError) as ex:
        logger.error(f"Failed to download the file from {download_url}: {str(ex)}")
        return None

    return file_path


def verify_checksum(file_path: str, checksum: str = None):
    if not checksum:
        return True
    with open(file_path, mode="rb") as fd:
        return checksum == sha256(fd.read(), usedforsecurity=False).hexdigest()


def find_file_in_directory(search_dir: str, file_to_search: str):
    search_dir = os.path.dirname(get_absolute_path(search_dir, file_to_search))
    file_to_search = os.path.basename(file_to_search)
    for root, _, files in os.walk(search_dir):
        for file_name in files:
            if os.path.basename(file_name).casefold() == file_to_search.casefold():
                file_path = get_absolute_path(root, file_name)
                return file_path

    return None


def get_python_path():
    default_python_path = default_paths.get("default_python_path")
    if default_python_path and os.path.isfile(default_python_path):
        return default_python_path

    return "python"


def isUserAdmin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except:
        return False


def members_to_extract_with_dest(zip_ref: ZipFile, members: List[Dict[str, str]] = None):
    namelist = zip_ref.namelist()

    def get_dest_path(member: str, replace_str: str):
        path_with_exclude_dir = member.replace(replace_str, "", 1).replace("/", os.path.sep)
        if os.path.altsep:
            path_with_exclude_dir = path_with_exclude_dir.replace(os.path.altsep, os.path.sep)
        return path_with_exclude_dir if path_with_exclude_dir else None

    if not members:
        return [{"src": member, "dest": get_dest_path(member, namelist[0])} for member in namelist]

    extract_members = []
    for member in members:
        replace_str = namelist[0]
        member_path = member["path"]
        keep_only_base = member.get("keep_only_base", False)
        if keep_only_base:
            replace_str = os.path.dirname(member_path.rstrip("/")) + "/"
        if member_path.endswith("/"):  # Include contents of the directory
            extract_members.extend(
                [
                    {"src": mem, "dest": get_dest_path(mem, replace_str)}
                    for mem in namelist
                    if mem.startswith(member_path)
                ]
            )
        else:
            extract_members.append({"src": member_path, "dest": get_dest_path(member_path, replace_str)})

    return extract_members


def members_to_extract(zip_ref: ZipFile, members: List[str] = None):
    namelist = zip_ref.namelist()
    extract_members = []
    if not members:
        extract_members = namelist
    else:
        for member in members:
            if member.endswith("/"):  # Include contents of the directory
                extract_members.extend([name for name in namelist if name.startswith(member)])
            else:
                extract_members.append(member)
    return list(set(extract_members))


def unzip_file(source_file: str, destination_dir: str, members: List[str] = None, force: str = False):
    logger.info(f"Unzipping {source_file}")
    ret = True
    try:
        if os.path.exists(destination_dir) and force:
            shutil.rmtree(destination_dir)
        os.makedirs(destination_dir, exist_ok=True)
        with ZipFile(source_file, "r") as zip_ref:
            members = members_to_extract(zip_ref, members=members)
            zip_ref.extractall(destination_dir, members=members)
    except (OSError, shutil.Error, FileNotFoundError) as err:
        ret = False
        logger.error(f"Failed to unzip the file: {str(err)}")
    else:
        logger.info(f"Successfully unzipped to: {destination_dir}")

    return ret


def unzip_file_skip_topdir(
    source_file: str, destination_dir: str, members: List[Dict[str, str]] = None, force: str = False
):
    logger.info(f"Unzipping {source_file}")
    ret = True
    try:
        if os.path.exists(destination_dir) and force:
            shutil.rmtree(destination_dir)
        os.makedirs(destination_dir, exist_ok=True)
        with ZipFileExactPath(source_file, "r") as zip_ref:
            members = members_to_extract_with_dest(zip_ref, members=members)
            for member in members:
                src_path = member["src"]
                dest_path = member["dest"]
                if dest_path:
                    abs_dest_path = os.path.join(destination_dir, dest_path)
                    zip_ref.extract(member=src_path, path=abs_dest_path)
    except (OSError, shutil.Error, FileNotFoundError) as err:
        ret = False
        logger.error(f"Failed to unzip the file: {str(err)}")
    else:
        logger.info(f"Successfully unzipped to: {destination_dir}")

    return ret


def install_softwares(
    softwares_to_install: List[Dict[str, str]],
    installer_path: str,
    logs_dir: str,
    silent: bool = False,
    force_reinstall: bool = False,
    online: bool = False,
):
    sw_error_code = 0
    for software in softwares_to_install:
        sw = SoftwareInstall(
            software=software,
            installers_dir_path=installer_path,
            logs_dir=logs_dir,
            silent=silent,
            force_reinstall=force_reinstall,
            online=online,
        )
        if not sw.install():
            sw_error_code = 1
    return sw_error_code


def install_archives(
    archives_to_install: List[Dict[str, str]],
    installers_dir_path: str,
    installation_dir: str,
    force_reinstall: bool = False,
    online: bool = False,
):
    error_code = 0
    for archive in archives_to_install:
        ar = ArchiveInstall(
            archive=archive,
            installers_dir_path=installers_dir_path,
            installation_dir=installation_dir,
            force_reinstall=force_reinstall,
            online=online,
        )
        if not ar.unarchive():
            error_code = 1
    return error_code


def delete_files(workspace: str, files: List[str] = None):
    exit_value = True
    if not files:
        return True
    for file_name in files:
        try:
            file_path = get_absolute_path(workspace, file_name)
            if os.path.isdir(file_path):
                if re.match(r"^\D:\\+$", file_path):
                    logger.warning(f"Cannot delete drives: {file_path}")
                else:
                    logger.info(f"Removing the directory: {file_path}")
                    shutil.rmtree(file_path)
                    logger.info(f"Successfully removed the directory: {file_path}")
            elif os.path.isfile(file_path):
                logger.info(f"Deleting the file: {file_path}")
                os.remove(file_path)
                logger.info(f"Successfully deleted the file: {file_path}")
        except (OSError, IOError) as err:
            logger.error(f"Error occurred while deleting the file/folder: {str(err)}")
            exit_value &= False
    return exit_value


def uninstall_softwares(
    softwares_to_uninstall: List[Dict[str, str]],
    installer_path: str,
    logs_dir: str,
    workspace: str,
    files_to_delete: List[str] = None,
    silent: bool = False,
):
    sw_error_code = 0
    for software in softwares_to_uninstall:
        sw = SoftwareUninstall(software, installer_path, logs_dir, silent)
        if not sw.uninstall():
            sw_error_code = 1
    if not delete_files(workspace, files_to_delete):
        sw_error_code = 1
    return sw_error_code


def post_install_softwares(
    softwares_to_install: List[Dict[str, str]],
    installer_path: str,
    logs_dir: str,
    silent: bool = False,
    online: bool = False,
):
    sw_error_code = 0
    for software in softwares_to_install:
        sw = SoftwareInstall(
            software=software, installers_dir_path=installer_path, logs_dir=logs_dir, silent=silent, online=online
        )
        if not sw.post_process():
            sw_error_code = 1
    return sw_error_code


def copy_files(source_dir: str, destination_dir: str, files: List[str] = None):
    exit_value = True
    os.makedirs(destination_dir, exist_ok=True)
    try:
        if files:
            for file_name in files:
                try:
                    file_path = get_absolute_path(source_dir, file_name)
                    destination_path = get_absolute_path(destination_dir, file_name)
                    if os.path.isfile(file_path):
                        shutil.copyfile(file_path, destination_path)
                    elif os.path.isdir(file_path):
                        shutil.copytree(file_path, destination_path, dirs_exist_ok=True)
                except (OSError, shutil.Error) as err:
                    logger.error(f"Error occurred while copying the files: {file_path}: {str(err)}")
                    exit_value &= False
        else:
            shutil.copytree(source_dir, destination_dir, dirs_exist_ok=True)
    except (OSError, shutil.Error) as err:
        logger.error(f"Error occurred while copying the files: {source_dir}: {str(err)}")
        exit_value &= False
    return exit_value


def openvino_script(destination_dir):
    setup_script = os.path.join(destination_dir, "scripts", "setupvars", "setupvars.bat")
    if not os.path.isfile(setup_script):
        logger.error("Openvino setup script could not be located")
        return None
    return setup_script


def install_packages(
    workspace,
    venv_python,
    requirements_file,
    local_wheel_dir,
    online: bool = False,
    force_reinstall=False,
    log_file="venv_install.log",
    store_output: bool = False,
):
    logger.info("Installing Python packages ...")
    ret = 0
    local_wheel_dir = get_absolute_path(workspace, local_wheel_dir)
    requirements_file = find_file_in_directory(workspace, requirements_file)
    if not requirements_file:
        logger.error(f"Error occurred while installing packages. Failed to locate requirements.txt")
        return 1
    try:
        pip_cmd = [venv_python, "&&", "python", "-m", "pip", "install", "-r", requirements_file, "--timeout", "120"]
        if not online:
            pip_cmd.extend(["--no-index", "--find-links", local_wheel_dir])
        if force_reinstall:
            pip_cmd.append("--ignore-installed")
        if store_output:
            with open(log_file, "w", encoding="utf-8") as fd:
                subprocess.run(pip_cmd, check=True, stdout=fd, stderr=fd, cwd=workspace)
        else:
            subprocess.run(pip_cmd, check=True, cwd=workspace)
        logger.info("Python packages installed successfully")
    except (subprocess.CalledProcessError, FileNotFoundError, TimeoutError) as ex:
        logger.error(f"Error occurred while installing packages: {str(ex)}")
        logger.error(f"Please check the logs for more details: {log_file}")
        ret = 1
    return ret


def create_venv(workspace: str, venv_path: str):
    python_path = get_python_path()
    os.makedirs(workspace, exist_ok=True)
    venv_path = get_absolute_path(workspace, venv_path)
    logger.info(f"Creating virtual environment: {venv_path}")
    if not os.path.exists(venv_path):
        try:
            subprocess.check_call([python_path, "-m", "venv", venv_path], cwd=workspace)
            logger.info(f"Virtual environment is created at {venv_path}")
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to create virtual environment: {e.stderr}")
            return None
        except FileNotFoundError as e:
            logger.error(f"python exe not found: {e.strerror}")
            return None
    else:
        logger.info(f"Virtual environment is created at {venv_path}")
    return os.path.join(venv_path, "Scripts", "activate.bat")


def get_absolute_path(workspace, path):
    if not os.path.isabs(path):
        path = os.path.join(workspace, path)

    return path


def validate_input(workspace):
    if not os.path.isdir(workspace) or not os.path.isabs(workspace):
        logger.error("The provided root for DevKit is not valid. This should be an absolute existent path.")
        return 1

    try:
        installer_path = get_absolute_path(workspace, default_paths["local_installers_path"])
        if not os.path.isdir(installer_path):
            logger.error(f"The installer path: {installer_path} does not exist")
            return 1

        openvino_source_dir = get_absolute_path(workspace, default_paths["openvino_source_dir"])
        if not os.path.isdir(openvino_source_dir):
            logger.error(f"The openvino source directory: {openvino_source_dir} does not exist")
            return 1

        default_python_whls = default_paths["local_python_wheel_dir"]
        python_whls_dir = get_absolute_path(workspace, default_python_whls)
        if not os.path.isdir(python_whls_dir):
            logger.error(f"The local directory path for installing python wheels: {default_python_whls} does not exist")
            return 1

        samples_dir = get_absolute_path(workspace, default_paths["samples_dir"])
        if not os.path.isdir(samples_dir):
            logger.error(f"The AI samples directory: {samples_dir} does not exist")
            return 1
    except KeyError as ex:
        logger.error(f"The path is not defined: {str(ex)}")
        return 1

    return 0


def create_batch_file(
    workspace: str,
    file_path: str,
    file_name: str,
    prepend_lines: List[str] = None,
    call_scripts: List[str] = None,
    append_lines: List[str] = None,
):
    bat_file = BatchFileCreation(workspace=workspace, file_path=file_path, file_name=file_name)
    try:
        bat_file.create_empty()
        if prepend_lines:
            for line in prepend_lines:
                bat_file.add_line(line)
        if call_scripts:
            for script in call_scripts:
                bat_file.add_bat_file_call(script)
        if append_lines:
            for line in append_lines:
                bat_file.add_line(line)
    except (IOError, subprocess.CalledProcessError) as ex:
        logger.error(f"Failed to create the file {bat_file.file_name}: {str(ex)}")
        return None

    logger.info(f"Successfully created the batch file: {bat_file.file_name}")
    return bat_file


def setup_logging(log_file, logging_level=logging.DEBUG, output_handler: logging.Handler = None):
    if not output_handler:
        output_handler = logging.StreamHandler()
    fmt_stdout = "[AIPCDevKitInstaller - %(levelname)-8s] %(message)s"
    fmt_file = "%(asctime)s [AIPCDevKitInstaller - %(levelname)-8s] %(message)s"
    formatter_file = logging.Formatter(fmt_file, datefmt="%Y-%m-%d %H:%M:%S")
    formatter_stdout = logging.Formatter(fmt_stdout)
    logger = logging.getLogger()

    # Clear existing handlers
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)

    output_handler.setFormatter(formatter_stdout)
    file_handler = logging.FileHandler(log_file, mode="w")
    file_handler.setFormatter(formatter_file)
    logger.setLevel(logging_level)
    logger.addHandler(output_handler)
    logger.addHandler(file_handler)
    return logger


def main(args=None, ui_log_handler: logging.Handler = None):
    parser = argparse.ArgumentParser(formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument(
        "--workspace", "-w", default=CURRENT_DIR_PATH, help="Workspace path for all the relative computations"
    )
    parser.add_argument(
        "--installation-dir",
        default=default_paths.get("installation_dir", CURRENT_DIR_PATH),
        help="Absolute Path to installation directory",
    )
    parser.add_argument(
        "--venv-path", default=default_paths.get("venv_path", "aipc-venv"), help="Virtual environment path"
    )
    parser.add_argument(
        "--force-reinstall", "-f", action="store_true", help="Set this flag to force re-install the packages"
    )
    parser.add_argument("--post-install-only", "-po", action="store_true", help="Set this flag to do post installation")
    parser.add_argument("--silent", "-s", action="store_true", help="Set this flag for silent installation of packages")
    parser.add_argument("--uninstall", action="store_true", help="Set this flag to uninstall packages")
    parser.add_argument("--online", action="store_true", help="Set this flag to install from online", default=True)
    parser.add_argument("--version", action="store_true", help="Print the version information and exit")
    parser.add_argument(
        "--only-softwares",
        nargs="*",
        help="Space delimeted list of softwares to install/uninstall",
        action="store",
        choices=SoftwaresToInstall().names(),
    )

    pargs = parser.parse_args(args)
    if pargs.version:
        print(VERSION)
        return 0

    logs_dir = get_absolute_path(pargs.workspace, default_paths.get("logs_dir", "SetupLogs"))
    logs_file = get_absolute_path(logs_dir, "install.log")
    if pargs.uninstall:
        logs_dir = get_absolute_path(pargs.workspace, default_paths.get("uninstall_logs_dir", "UninstallLogs"))
        logs_file = get_absolute_path(logs_dir, "uninstall.log")

    os.makedirs(logs_dir, exist_ok=True)
    set_logger = setup_logging(logs_file, output_handler=ui_log_handler)
    global logger
    logger = set_logger
    logger.info(f"Intel AI PC Development Kit version {VERSION}")
    local_installers_path = os.path.expandvars(default_paths["local_installers_path"])
    openvino_dest_dir = default_paths.get("openvino_dest_dir", CURRENT_DIR_PATH)
    installer_path = get_absolute_path(pargs.workspace, local_installers_path)
    installation_dir = get_absolute_path(pargs.workspace, os.path.expandvars(pargs.installation_dir))
    softwares_to_install = SoftwaresToInstall().get_list(software_names=pargs.only_softwares)
    if pargs.uninstall:
        sw_error_code = uninstall_softwares(
            softwares_to_uninstall=softwares_to_install,
            installer_path=installer_path,
            logs_dir=logs_dir,
            workspace=installation_dir,
            files_to_delete=default_paths.get("delete_files", [])
            + [openvino_dest_dir, os.path.expandvars(pargs.venv_path)],
            silent=pargs.silent,
        )
        if sw_error_code:
            logger.error(
                f"ERROR: Not all the software is un-installed properly. Please check the logs: {logs_file} for more details"
            )
        return sw_error_code

    if default_paths.get("copy_files"):
        copy_files(pargs.workspace, installation_dir, files=default_paths["copy_files"])

    if not pargs.online:
        invalid_input = validate_input(pargs.workspace)
        if invalid_input:
            return invalid_input

    requirements_file = get_absolute_path(EXE_PATH, default_paths["python_requirements_file"])
    python_whls_dir = default_paths["local_python_wheel_dir"]
    samples_dir = default_paths["samples_dir"]

    if pargs.post_install_only:
        return post_install_softwares(softwares_to_install, installer_path, logs_dir, pargs.silent, pargs.online)

    sw_error_code = install_softwares(
        softwares_to_install, installer_path, logs_dir, pargs.silent, pargs.force_reinstall, pargs.online
    )
    archives_to_install = configurations.get("archive_installations", [])
    sw_error_code |= install_archives(
        archives_to_install=archives_to_install,
        installers_dir_path=installer_path,
        installation_dir=installation_dir,
        force_reinstall=pargs.force_reinstall,
        online=pargs.online,
    )
    openvino_setup_script = openvino_script(openvino_dest_dir)
    if not openvino_setup_script:
        sw_error_code = 1

    samples_dir = get_absolute_path(pargs.workspace, samples_dir)

    logger.info(f"Copying samples to {installation_dir}")
    if not copy_files(samples_dir, installation_dir):
        logger.error("Failed to copy the samples")
        sw_error_code = 1
    else:
        logger.info("Samples copied successfully")
    aipc_env_path = get_absolute_path(installation_dir, pargs.venv_path)

    venv_python = create_venv(installation_dir, pargs.venv_path)
    if venv_python:
        venv_log_file = get_absolute_path(logs_dir, "venv_install.log")
        if install_packages(
            workspace=pargs.workspace,
            venv_python=venv_python,
            requirements_file=requirements_file,
            local_wheel_dir=python_whls_dir,
            online=pargs.online,
            force_reinstall=pargs.force_reinstall,
            log_file=venv_log_file,
            store_output=ui_log_handler is not None,
        ):
            sw_error_code = 1
    else:
        sw_error_code = 1

    setup_message = ["AI PC Development Kit setup is now complete."]
    if sw_error_code:
        setup_message.append(
            f"ERROR: Not all the software is installed properly. Please check the logs: {logs_file} for more details"
        )
    bat_file_obj = create_batch_file(
        workspace=pargs.workspace,
        file_path=aipc_env_path,
        file_name="aipcdevkit.bat",
        call_scripts=[openvino_setup_script, venv_python],
    )
    if not bat_file_obj:
        sw_error_code = 1
    jupyter_bat_obj = create_batch_file(
        workspace=pargs.workspace,
        file_path=installation_dir,
        file_name="start_lab.cmd",
        call_scripts=[bat_file_obj.file_name],
        append_lines=[
            f'start /D "{installation_dir}\\openvino_notebooks" jupyter lab',
            "start https://microsoft.github.io/webnn-developer-preview",
            "start https://github.com/webmachinelearning/awesome-webnn",
            f'cmd /K cd "{installation_dir}"',
        ],
    )
    if not jupyter_bat_obj:
        sw_error_code = 1

    logger.info("\n\n".join(setup_message))
    jupyter_bat_obj.run_file()

    return sw_error_code


if __name__ == "__main__":
    try:
        if isUserAdmin():
            sys.exit(main())
        else:
            logging.warning("This installer should be executed with admin privilege !!!")
            time.sleep(20)
            sys.exit(0)
    except KeyboardInterrupt:
        sys.exit(0)
