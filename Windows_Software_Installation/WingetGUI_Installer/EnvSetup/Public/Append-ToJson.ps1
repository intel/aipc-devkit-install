
<#
    Helper function to append to a JSON file
    Appends Hashtables, formatted in either a Winget application format, or a External Application format
    Made specifically for this script, especially the uninstall portion
#>
function AppendToJson([string]$json_location, [hashtable]$data) {
    # Validate that data has the required structure
    if (-not $data.ContainsKey('winget_applications') -or -not $data.ContainsKey('external_applications')) {
        throw "Data must contain winget_applications and external_applications keys"
    }

    # Check if the file exists
    if (Test-Path -Path $json_location) {
        # Load existing data
        $existing_data = Get-Content -Path $json_location -Raw | ConvertFrom-Json

        # Set merged data to existing so we can add without altering immediately
        $merged_data = $existing_data

        # Initialize arrays if they don't exist
        if (-not $merged_data.winget_applications) {
            $merged_data.winget_applications = @()
        }
        if (-not $merged_data.external_applications) {
            $merged_data.external_applications = @()
        }

        # Append winget_applications if not already present
        if ($data.ContainsKey('winget_applications')) {
            foreach ($new_app in $data.winget_applications) {
                # Check if application already exists (by name)
                $exists = $merged_data.winget_applications | Where-Object { $_.name -eq $new_app.name }
                if (-not $exists) {
                    $merged_data.winget_applications += $new_app
                }
            }
        }
        else {
            $merged_data.winget_applications = @()
        }

        # Append external_applications if not already present
        if ($data.ContainsKey('external_applications')) {
            foreach ($new_app in $data.external_applications) {
                # Check if application already exists (by name)
                $exists = $merged_data.external_applications | Where-Object { $_.name -eq $new_app.name }
                if (-not $exists) {
                    $merged_data.external_applications += $new_app
                }
            }
        }
        else {
            $merged_data.external_applications = @()
        }

        # Convert merged data back to JSON and save
        $json_string = $merged_data | ConvertTo-Json -Depth 5
        Set-Content -Path $json_location -Value $json_string
    }
    else {
        # File doesn't exist, create new with data
        $json_dir = Split-Path -Parent $json_location
        if (-not (Test-Path $json_dir)) {
            New-Item -Path $json_dir -ItemType Directory
        }
        New-Item -Path $json_location -ItemType File
        $json_string = $data | ConvertTo-Json -Depth 5
        Set-Content -Path $json_location -Value $json_string
    }
}
