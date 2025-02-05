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

import tkinter as tk
from tkinter import messagebox, ttk
import threading
import installer  # Ensure this module is secure and handles all installation logic.
import logging
import os
import argparse
import sys
import time
from version import VERSION


class InstallerApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.setup_window_title()
        self.configure(bg="#FFFFFF")
        self.create_styles()
        self.center_window(600, 400)
        self.content_frame = ttk.Frame(self)
        self.content_frame.pack(fill="both", expand=True)
        self.show_license_window()
        self.protocol("WM_DELETE_WINDOW", self.on_close)  # Bind the close event

    def setup_window_title(self):
        self.title(f"Intel AI PC Development Kit Setup - Installation Wizard v.{VERSION}")

    def finish_installation(self):
        self.destroy()

    def on_close(self):
        # If the installation is active, prompt the user before closing
        if messagebox.askyesno(title="Confirm Exit", message="Confirm Exit"):
            self.destroy()

    def create_styles(self):
        style = ttk.Style()
        style.theme_use("clam")

        # Refined color palette
        primary_color = "#2C3E50"  # Dark shade of blue
        secondary_color = "#5D6D7E"  # A softer shade of blue-gray for secondary elements
        background_color = "#F4F6F7"  # A very light gray that's softer than pure white
        foreground_color = "#FFFFFF"  # White for text on primary elements
        text_color = "#17202A"  # A very dark shade of blue-gray for text, providing high contrast
        active_color = "#3498DB"  # A brighter blue for active/hover states
        button_hover = "#D6DBDF"  # A light gray for button hover, less intense than the active color

        # Frame style
        style.configure("TFrame", background=background_color)

        # Button style
        style.configure("TButton", background=secondary_color, foreground=foreground_color, borderwidth=0)
        style.map("TButton", background=[("active", button_hover)], foreground=[("active", foreground_color)])

        # Label style
        style.configure("TLabel", background=background_color, foreground=text_color)

        # Checkbutton style
        style.configure("TCheckbutton", background=background_color, foreground=text_color)

        # Primary button style (for important actions)
        style.configure("Primary.TButton", background=primary_color, foreground=foreground_color)
        style.map("Primary.TButton", background=[("active", active_color)], foreground=[("active", foreground_color)])

    def center_window(self, width, height):
        screen_width = self.winfo_screenwidth()
        screen_height = self.winfo_screenheight()
        x = (screen_width // 2) - (width // 2)
        y = (screen_height // 2) - (height // 2)
        self.geometry(f"{width}x{height}+{x}+{y}")

    def confirm_quit(self):
        if messagebox.askyesno(title="Confirm Cancellation", message="Confirm Cancellation"):
            self.destroy()

    def show_license_window(self):
        # Clear the current content frame
        for widget in self.content_frame.winfo_children():
            widget.destroy()

        software_name = "License Agreement"
        ttk.Label(self.content_frame, text=software_name, font=("calibri", 14, "bold")).pack(pady=(20, 10))

        # Instructions text
        instructions_text = "Please read the following important license agreement before continuing:"
        instructions_label = ttk.Label(self.content_frame, text=instructions_text, font=("Segoe UI", 10))
        # Pack the instructions_label with the same padx as the accept_license_checkbutton
        instructions_label.pack(anchor="w", padx=25, pady=(0, 0))

        # Create a frame for the license text
        license_frame = ttk.Frame(self.content_frame)
        # Pack the license_frame with the same padx as the instructions_label and accept_license_checkbutton
        license_frame.pack(fill="both", expand=True, padx=25, pady=(10, 0))

        # Create a Text widget with no wrap (allows horizontal scrolling)
        text_widget = tk.Text(license_frame, wrap="word", height=10, width=66, font=("Segoe UI", 10))
        text_widget.config(state="disabled", takefocus=False)

        # Unbind mouse events to prevent text selection
        text_widget.bind("<1>", lambda event: "break")  # Unbind left mouse click
        text_widget.bind("<B1-Motion>", lambda event: "break")  # Unbind mouse move while button held

        # Determine the path to the license.txt file relative to the script's directory
        script_dir = os.path.dirname(os.path.realpath(__file__))
        license_file_path = os.path.join(script_dir, "License.txt")

        # License agreement variable and Checkbutton
        self.license_var = tk.BooleanVar(value=False)
        self.accept_license_checkbutton = ttk.Checkbutton(
            self.content_frame,
            text="I accept the license agreement",
            variable=self.license_var,
            state="disable",
            command=self.on_license_accept,  # Link the checkbox to the callback
        )
        self.accept_license_checkbutton.pack(anchor="w", padx=25, pady=(5, 2))

        # Create a vertical scrollbar and attach it to the Text widget
        v_scrollbar = ttk.Scrollbar(license_frame, orient="vertical", command=text_widget.yview)
        text_widget.config(yscrollcommand=v_scrollbar.set)
        v_scrollbar.pack(side="right", fill="y")

        # Create a horizontal scrollbar and attach it to the Text widget
        h_scrollbar = ttk.Scrollbar(license_frame, orient="horizontal", command=text_widget.xview)
        text_widget.config(xscrollcommand=h_scrollbar.set)
        h_scrollbar.pack(side="bottom", fill="x")

        # Pack the Text widget after the scrollbars to ensure it fills the remaining space
        text_widget.pack(side="left", fill="both", expand=True)

        # Define the button container for the "Install" and "Cancel" buttons
        button_container = ttk.Frame(self.content_frame)
        button_container.pack(side="bottom", fill="x", pady=20)

        # Cancel button
        cancel_button = ttk.Button(button_container, text="Cancel", command=self.confirm_quit)
        cancel_button.pack(side="right", padx=25)

        # Install button (initially disabled)
        self.install_button = ttk.Button(
            button_container, text="Install", state="disabled", command=self.perform_installation
        )
        self.install_button.pack(side="right", padx=10)

        # Read the license agreement text from the file
        try:
            with open(license_file_path, "r", encoding="utf-8") as file:
                license_text = file.read()
                text_widget.config(state="normal")
                text_widget.insert("end", license_text)
                text_widget.config(state="disabled")  # Ensure the text widget is read-only
                self.accept_license_checkbutton.config(state="normal")
        except FileNotFoundError:
            logging.error("License file not found.")
            self.disable_ui_elements()
        except Exception as e:
            logging.error(f"Error reading license file: {e}")
            self.disable_ui_elements()

    def disable_ui_elements(self):
        if hasattr(self, "accept_license_checkbutton") and self.accept_license_checkbutton:
            self.accept_license_checkbutton.config(state="disabled")
        # Optionally, display a message box to inform the user
        messagebox.showerror(
            "Installation Error", "The license agreement file is missing. Installation cannot proceed."
        )

    def on_license_accept(self, *args):
        # Enable the "Next" button when the license is accepted
        if self.license_var.get():
            self.install_button.config(state="normal")
        else:
            self.install_button.config(state="disabled")

    def perform_installation(self):
        installation_thread = threading.Thread(target=installer.main)
        installation_thread.start()
        self.finish_installation()


# Main application window
if __name__ == "__main__":
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        from pyi_rth_installer import restore_original

        global ACLS_CHANGED

        application_dir = os.path.dirname(sys.executable)
        relocation_dir = os.path.join(application_dir, "temporary_folder_AIDevKit")
        restore_original(relocation_dir, application_dir, acl_changed=ACLS_CHANGED)

    parser = argparse.ArgumentParser()
    parser.add_argument("--version", action="store_true", help="Print the version information and exit")
    pargs = parser.parse_args()
    if pargs.version:
        print(VERSION)
        sys.exit(0)
    try:
        if installer.isUserAdmin():
            app = InstallerApp()
            app.mainloop()
        else:
            logging.warning("This installer should be executed with admin privilege !!!")
            time.sleep(20)
            sys.exit(0)
    except KeyboardInterrupt:
        sys.exit(0)
    except Exception as e:
        logging.error(f"Application error: {e}")
        messagebox.showerror("Application Error", "An unexpected error occurred.")
