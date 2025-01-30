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

import sys
import ctypes
import logging
import time
import os

from installer import main as installer_main


def isUserAdmin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except:
        return False


if __name__ == "__main__":
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        from pyi_rth_installer import restore_original

        global ACLS_CHANGED

        application_dir = os.path.dirname(sys.executable)
        relocation_dir = os.path.join(application_dir, "temporary_folder_AIDevKit")
        restore_original(relocation_dir, application_dir, acl_changed=ACLS_CHANGED)

    if isUserAdmin():
        sys.exit(installer_main(["--uninstall", "--silent"]))
    else:
        logging.warning("This un-installer should be executed with admin privilege !!!")
        time.sleep(20)
        sys.exit(0)
