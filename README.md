# aipc-devkit-install
AI PC Dev Kit Installation Scripts

* Run the script on a test system per the instructions below.
* Please also see the setup and usage instructions for these independent sub-project(s): 
   * [WebNN demo](WebNN-demo/WebNN-demo.md)

# One-time setup instructions
1. Install Windows on the system.
2. Open an administrative PowerShell
3. Enable PowerShell scripts execution, either in dev Settings or by running the command:  
   ```Set-ExecutionPolicy -ExecutionPolicy bypass -Force```
4. Download and rename the file IntelOpenVinoSetupV5.txt to IntelOpenVinoSetupV5.ps1. Run the script ```./IntelOpenVinoSetupV5.ps1```
   (Note that there may be some installation errors due to connection issue when running the installation script. Please run multiple times of this installation script if you get errors when running the following command.)
5. The script downloads and runs through installation of various AI software. Please accept licenses accordingly.  
6. Run the command ```benchmark_app -h```.  The last line of output should look something like this:
   ```
      Available target devices:   CPU  GPU  NPU
   ```
   If benchmark_app is not found, then activate the virtual environment with the following command and try again.
   ```
   C:\Intel\venv\Scripts\activate.ps1
   ```

# Instructions for running Notebooks
0. After running the install script, cd to C:\Intel\openvino_notebooks.
   Assuming you are still in a Powershell: ```Set-Location C:\Intel\openvino_notebooks```.
1. Start Jupyter Notebooks
   * To run notebooks in a browser:
      * Start the notebooks by running this in command prompt
   ```jupyter lab notebooks```, and follow the instructions to start the interface on browser (e.g., localhost:8080/lab)
   * Or to run notebooks in Visual Studio Code
      * Type the command ```code notebooks```

2. In the browser or VSCode sidebar navigate to one of the following notebooks and run it to verify correct execution (requires internet connection).
   * hello-world\hello-world.ipynb
   * llm-chatbot\llm-chatbot.ipynb
   * yolov8-optimization\yolov8-instance-segmentation.ipynb

# Notebooks Showcases
https://openvinotoolkit.github.io/openvino_notebooks/


