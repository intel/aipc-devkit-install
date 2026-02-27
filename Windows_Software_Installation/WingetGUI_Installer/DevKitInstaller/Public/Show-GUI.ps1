<#
.SYNOPSIS
    WPF GUI functions for the Environment Setup Tool.

.DESCRIPTION
    Provides the main menu, package selection, install/uninstall result
    dialogs — all using WPF (PresentationFramework).
#>

function Show-MainGUI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $applications,

        [string]$install_log_file,
        [string]$json_uninstall_file_path
    )

    if (-not (Ensure-StaThread)) { return }

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Environment Setup - Main Menu" Height="300" Width="500"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize">
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto" />
      <RowDefinition Height="Auto" />
      <RowDefinition Height="Auto" />
      <RowDefinition Height="Auto" />
      <RowDefinition Height="*" />
    </Grid.RowDefinitions>

    <TextBlock Grid.Row="0" Text="Environment Setup Tool" FontSize="16" FontWeight="Bold"
               HorizontalAlignment="Center" Margin="0,10,0,0" />
    <TextBlock Grid.Row="1" Text="Choose an action to perform:" HorizontalAlignment="Center"
               Margin="0,10,0,0" />

    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,20,0,0">
      <Button Name="btnInstall" Content="Install Software" Width="150" Height="40" Margin="0,0,20,0" />
      <Button Name="btnUninstall" Content="Uninstall Software" Width="150" Height="40" />
    </StackPanel>

    <Button Grid.Row="3" Name="btnExit" Content="Exit" Width="100" Height="30"
            HorizontalAlignment="Center" Margin="0,20,0,0" />
  </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $win    = [Windows.Markup.XamlReader]::Load($reader)

    $win.FindName('btnInstall').Add_Click({
        $win.Hide()
        $selectedPackages = Show-PackageSelectionWpf -applications $applications -install_log_file $install_log_file

        if ($selectedPackages) {
            Write-Host 'Installing selected packages...' -ForegroundColor Green

            if (-not [string]::IsNullOrWhiteSpace($json_uninstall_file_path)) {
                $uninstallDir = Split-Path -Path $json_uninstall_file_path -Parent
                if (-not (Test-Path -Path $uninstallDir)) {
                    New-Item -Path $uninstallDir -ItemType Directory -Force | Out-Null
                }
                if (-not (Test-Path -Path $json_uninstall_file_path)) {
                    $json_structure = @{
                        winget_applications   = @()
                        external_applications = @()
                    }
                    $json_structure | ConvertTo-Json | Set-Content -Path $json_uninstall_file_path
                }
            }

            $installResults = Install-SelectedPackages -selectedPackages $selectedPackages -log_file $install_log_file -uninstall_json_file $json_uninstall_file_path

            $username = [Environment]::UserName
            Copy-Item -Path $install_log_file -Destination "C:\Users\$username\Desktop\install_logs.txt" -ErrorAction SilentlyContinue

            Show-InstallResults -installResults $installResults
        }

        $win.Close()
    })

    $win.FindName('btnUninstall').Add_Click({
        $win.Hide()
        $selectedPackages = Show-UninstallWpf -json_uninstall_file_path $json_uninstall_file_path

        if ($selectedPackages) {
            Write-Host 'Uninstalling selected packages...' -ForegroundColor Yellow
            $uninstallResults = Uninstall-SelectedPackages -selectedPackages $selectedPackages -log_file $install_log_file -json_uninstall_file_path $json_uninstall_file_path
            Show-UninstallResults -uninstallResults $uninstallResults
        }

        $win.Close()
    })

    $win.FindName('btnExit').Add_Click({ $win.Close() })

    $null = $win.ShowDialog()
}

function Show-InstallResults {
    [CmdletBinding()]
    param($installResults)

    $resultMessage  = "Installation Summary:`n"
    $resultMessage += "Total packages: $($installResults.TotalPackages)`n"
    $resultMessage += "Successfully installed: $($installResults.SuccessfulInstalls)`n"
    $resultMessage += "Failed installations: $($installResults.FailedInstalls)`n"

    if ($installResults.FailedInstalls -gt 0) {
        $resultMessage += "`nFailed packages:`n"
        foreach ($failedPkg in $installResults.FailedPackages) {
            $resultMessage += "- $failedPkg`n"
        }
    }

    $resultMessage += "`nCheck the install logs on your desktop for details."

    if ($installResults.FailedInstalls -eq 0) {
        $icon  = [System.Windows.MessageBoxImage]::Information
        $title = 'Environment Setup - Installation Completed Successfully'
    } elseif ($installResults.SuccessfulInstalls -eq 0) {
        $icon  = [System.Windows.MessageBoxImage]::Error
        $title = 'Environment Setup - Installation Failed'
    } else {
        $icon  = [System.Windows.MessageBoxImage]::Warning
        $title = 'Environment Setup - Installation Completed with Errors'
    }

    [System.Windows.MessageBox]::Show(
        $resultMessage, $title,
        [System.Windows.MessageBoxButton]::OK, $icon
    )
}

function Show-PackageSelectionWpf {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $applications,
        [string]$install_log_file
    )

    if (-not (Ensure-StaThread)) { return $null }
    $items = Convert-AppsToSelectionItems -applications $applications

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Environment Setup - Select Software to Install" Height="600" Width="1000"
        WindowStartupLocation="CenterScreen">
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="*" />
      <RowDefinition Height="Auto" />
    </Grid.RowDefinitions>

    <DataGrid Name="dg" Grid.Row="0" AutoGenerateColumns="False" CanUserAddRows="False">
      <DataGrid.Columns>
        <DataGridCheckBoxColumn Header="Install?" Binding="{Binding Check}" Width="70" />
        <DataGridTextColumn Header="Package ID" Binding="{Binding Id}" Width="200" IsReadOnly="True" />
        <DataGridTextColumn Header="Name" Binding="{Binding FriendlyName}" Width="200" IsReadOnly="True" />
        <DataGridTextColumn Header="Description" Binding="{Binding Summary}" Width="*" IsReadOnly="True" />
        <DataGridTextColumn Header="Version" Binding="{Binding Version}" Width="100" IsReadOnly="True" />
        <DataGridTextColumn Header="Type" Binding="{Binding Type}" Width="80" IsReadOnly="True" />
      </DataGrid.Columns>
    </DataGrid>

    <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Left" Margin="0,10,0,0">
      <Button Name="btnSelectAll" Content="Select All" Width="90" Margin="0,0,8,0" />
      <Button Name="btnClearAll" Content="Clear All" Width="90" Margin="0,0,8,0" />
      <Button Name="btnInstall" Content="Install Selected" Width="120" Margin="0,0,8,0" />
      <Button Name="btnClose" Content="Close" Width="80" />
    </StackPanel>
  </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $win    = [Windows.Markup.XamlReader]::Load($reader)
    $dg     = $win.FindName('dg')
    $dg.ItemsSource = $items

    $win.FindName('btnSelectAll').Add_Click({
        foreach ($item in $items) { $item.Check = $true }
        $dg.Items.Refresh()
    })
    $win.FindName('btnClearAll').Add_Click({
        foreach ($item in $items) { $item.Check = $false }
        $dg.Items.Refresh()
    })
    $win.FindName('btnInstall').Add_Click({
        $selected = $items | Where-Object { $_.Check }
        if (-not $selected) {
            [System.Windows.MessageBox]::Show(
                'No packages selected.', 'Environment Setup',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )
            return
        }

        $cnt     = @($selected).Count
        $pkgWord = if ($cnt -eq 1) { 'package' } else { 'packages' }
        $confirm = [System.Windows.MessageBox]::Show(
            "You are about to install $cnt $pkgWord. Continue?",
            'Environment Setup - Confirm Installation',
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )

        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }
        $script:selectedPackages = $selected
        $win.DialogResult = $true
        $win.Close()
    })
    $win.FindName('btnClose').Add_Click({ $win.Close() })

    $null = $win.ShowDialog()
    if ($win.DialogResult) { return $script:selectedPackages }
    return $null
}

function Show-UninstallWpf {
    [CmdletBinding()]
    param(
        [string]$json_uninstall_file_path
    )

    if (-not (Ensure-StaThread)) { return $null }

    if (-not (Test-Path -Path $json_uninstall_file_path)) {
        [System.Windows.MessageBox]::Show(
            'No uninstall.json file found. No applications have been tracked for uninstallation.',
            'Environment Setup - No Applications to Uninstall',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        )
        return $null
    }

    $uninstallData = Get-Content -Path $json_uninstall_file_path -Raw | ConvertFrom-Json
    $totalApps = 0
    if ($uninstallData.winget_applications   -and $uninstallData.winget_applications.Count)   { $totalApps += $uninstallData.winget_applications.Count }
    if ($uninstallData.external_applications -and $uninstallData.external_applications.Count) { $totalApps += $uninstallData.external_applications.Count }

    if ($totalApps -eq 0) {
        [System.Windows.MessageBox]::Show(
            'No applications are currently tracked for uninstallation.',
            'Environment Setup - No Applications to Uninstall',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        )
        return $null
    }

    $items = New-Object System.Collections.Generic.List[object]
    if ($uninstallData.winget_applications) {
        foreach ($app in $uninstallData.winget_applications) {
            $items.Add([pscustomobject]@{
                Check        = $false
                Id           = if ($app.id) { $app.id } else { $app.name }
                FriendlyName = if ($app.friendly_name) { $app.friendly_name } elseif ($app.id) { $app.id } else { $app.name }
                Version      = if ($app.version) { $app.version } else { 'Latest' }
                Type         = 'Winget'
            })
        }
    }
    if ($uninstallData.external_applications) {
        foreach ($app in $uninstallData.external_applications) {
            $items.Add([pscustomobject]@{
                Check        = $false
                Id           = $app.name
                FriendlyName = if ($app.friendly_name) { $app.friendly_name } else { $app.name }
                Version      = 'External'
                Type         = 'External'
            })
        }
    }

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Environment Setup - Select Software to Uninstall" Height="500" Width="900"
        WindowStartupLocation="CenterScreen">
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="*" />
      <RowDefinition Height="Auto" />
    </Grid.RowDefinitions>

    <DataGrid Name="dg" Grid.Row="0" AutoGenerateColumns="False" CanUserAddRows="False">
      <DataGrid.Columns>
        <DataGridCheckBoxColumn Header="Uninstall?" Binding="{Binding Check}" Width="80" />
        <DataGridTextColumn Header="Package ID" Binding="{Binding Id}" Width="200" IsReadOnly="True" />
        <DataGridTextColumn Header="Name" Binding="{Binding FriendlyName}" Width="200" IsReadOnly="True" />
        <DataGridTextColumn Header="Version" Binding="{Binding Version}" Width="100" IsReadOnly="True" />
        <DataGridTextColumn Header="Type" Binding="{Binding Type}" Width="80" IsReadOnly="True" />
      </DataGrid.Columns>
    </DataGrid>

    <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Left" Margin="0,10,0,0">
      <Button Name="btnSelectAll" Content="Select All" Width="90" Margin="0,0,8,0" />
      <Button Name="btnClearAll" Content="Clear All" Width="90" Margin="0,0,8,0" />
      <Button Name="btnUninstall" Content="Uninstall Selected" Width="130" Margin="0,0,8,0" />
      <Button Name="btnCancel" Content="Cancel" Width="80" />
    </StackPanel>
  </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $win    = [Windows.Markup.XamlReader]::Load($reader)
    $dg     = $win.FindName('dg')
    $dg.ItemsSource = $items

    $win.FindName('btnSelectAll').Add_Click({
        foreach ($item in $items) { $item.Check = $true }
        $dg.Items.Refresh()
    })
    $win.FindName('btnClearAll').Add_Click({
        foreach ($item in $items) { $item.Check = $false }
        $dg.Items.Refresh()
    })
    $win.FindName('btnUninstall').Add_Click({
        $selected = $items | Where-Object { $_.Check }
        if (-not $selected) {
            [System.Windows.MessageBox]::Show(
                'No packages selected.', 'Environment Setup',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )
            return
        }

        $cnt     = @($selected).Count
        $confirm = [System.Windows.MessageBox]::Show(
            "You are about to uninstall $cnt package(s). This action cannot be undone. Continue?",
            'Environment Setup - Confirm Uninstallation',
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )

        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }
        $script:selectedUninstallPackages = $selected
        $win.DialogResult = $true
        $win.Close()
    })
    $win.FindName('btnCancel').Add_Click({ $win.Close() })

    $null = $win.ShowDialog()
    if ($win.DialogResult) { return $script:selectedUninstallPackages }
    return $null
}

function Show-UninstallResults {
    [CmdletBinding()]
    param($uninstallResults)

    $resultMessage  = "Uninstallation Summary:`n"
    $resultMessage += "Total packages: $($uninstallResults.TotalPackages)`n"
    $resultMessage += "Successfully uninstalled: $($uninstallResults.SuccessfulUninstalls)`n"
    $resultMessage += "Failed uninstallations: $($uninstallResults.FailedUninstalls)`n"

    if ($uninstallResults.FailedUninstalls -gt 0) {
        $resultMessage += "`nFailed packages:`n"
        foreach ($failedPkg in $uninstallResults.FailedPackages) {
            $resultMessage += "- $failedPkg`n"
        }
    }

    if ($uninstallResults.FailedUninstalls -eq 0) {
        $icon  = [System.Windows.MessageBoxImage]::Information
        $title = 'Environment Setup - Uninstallation Completed Successfully'
    } elseif ($uninstallResults.SuccessfulUninstalls -eq 0) {
        $icon  = [System.Windows.MessageBoxImage]::Error
        $title = 'Environment Setup - Uninstallation Failed'
    } else {
        $icon  = [System.Windows.MessageBoxImage]::Warning
        $title = 'Environment Setup - Uninstallation Completed with Errors'
    }

    [System.Windows.MessageBox]::Show(
        $resultMessage, $title,
        [System.Windows.MessageBoxButton]::OK, $icon
    )
}
