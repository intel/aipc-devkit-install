<#
    Script that has user accept to all EULA agreements for software installed by this script
    Author: Ben Odom (benjamin.j.odom@intel.com)
#>


Add-Type -AssemblyName System.Windows.Forms
$disclaimer = @'

This exclusive remote desktop session includes pre-installed software and models
governed by various end-user license agreements ("EULAs") (the term "Session" refers
to this exclusive remote desktop session and all included software and models). 
Please click below for more information:

By clicking Agree and Continue, I hereby agree and consent to these EULAs. 
Intel is providing access to this Session for the sole purpose of demonstrating Intel 
technology and enabling me to optimize software for Intel systems, and my use of the 
Session is strictly limited to this purpose. I further agree that the 
Session is provided by Intel "as is" without any express or implied warranty of any kind. 
My use of the Session is at my own risk. Intel will not be liable to me under any legal 
theory for any losses or damages in connection with the Session
'@
$box = New-Object -TypeName System.Windows.Forms.Form
$box.ClientSize = New-Object -TypeName System.Drawing.Size -ArgumentList 600, 380
$box.Text = "Legal Disclaimer"
$box.StartPosition = "CenterScreen"
$box.ControlBox = $false
$box.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog

$label = New-Object -TypeName System.Windows.Forms.Label
$label.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 10, 10
$label.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 450, 260
$label.Text = $disclaimer
$label.Font = New-Object -TypeName System.Drawing.Font -ArgumentList "Arial", 10
$label.AutoSize = $true
$label.Padding = New-Object -TypeName System.Windows.Forms.Padding -ArgumentList 10, 10, 10, 10

$alink = New-Object -TypeName System.Windows.Forms.LinkLabel
$alink.Text = "Click here for the list of applications and their corresponding EULA"
$alink.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 10, 280
$alink.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 580, 20
$alink.LinkBehavior = [System.Windows.Forms.LinkBehavior]::AlwaysUnderline
$alink.Font = New-Object -TypeName System.Drawing.Font -ArgumentList "Arial", 10
$alink.Add_Click({
        Start-Process -FilePath "https://sdpconnect.intel.com/html/intel_aipc_cloud_access_agreement.htm"
    })



$check_box = New-Object System.Windows.Forms.CheckBox
$check_box.Text = "I have read and understand all the license agreements."
$check_box.AutoSize = $true
$check_box.Location = New-Object System.Drawing.Point -ArgumentList 10, 250
$box.Controls.Add($check_box)

# Text to pop up of the button is clicked and the checkbox has not been checked
$check_the_box = New-Object -TypeName System.Windows.Forms.Label
$check_the_box.Location = New-Object -TypeName System.Drawing.Point 10, 230
$check_the_box.AutoSize = $true
$check_the_box.Text = "Must check the box acknowledging that you have read and understand the terms"
$check_the_box.ForeColor = [System.Drawing.Color]::Red
$check_the_box.Visible = $false
$box.Controls.Add($check_the_box)



$accept_button = New-Object -TypeName System.Windows.Forms.Button
$accept_button.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 150, 310
$accept_button.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 150, 45
$accept_button.Text = "Agree and Continue"

$accept_button.Font = New-Object -TypeName System.Drawing.Font -ArgumentList "Arial", 12
$accept_button.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
$accept_button.Add_Click( {
        if ($check_box.Checked) {
            # Return true (0) for agree
            $box.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $box.Close() 
        }
        else {
            $check_the_box.Visible = $true
        } 
    })



$disagree_button = New-Object -TypeName System.Windows.Forms.Button
$disagree_button.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 310, 310
$disagree_button.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 150, 45
$disagree_button.Text = "Do not accept"

$disagree_button.Font = New-Object -TypeName System.Drawing.Font -ArgumentList "Arial", 12
$disagree_button.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
$disagree_button.Add_Click( {
        # Return false (!0) for disagree
        $box.DialogResult = [System.Windows.Forms.DialogResult]::No
        $box.Close()
    })


$box.Controls.Add($label)
$box.Controls.Add($alink)
$box.Controls.Add($accept_button)
$box.Controls.Add($disagree_button)

# Show the dialog box and return the result
$box.ShowDialog() | Out-Null
# Return the dialog result
if ($box.DialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
    exit 0
} else {
    exit 1
}