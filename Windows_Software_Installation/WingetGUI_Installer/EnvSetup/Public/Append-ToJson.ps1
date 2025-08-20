
<#
    Helper function to append to a JSON file
    Appends an object to a specified section of a JSON file
#>
function Append-ToJson {
    param (
        [Parameter(Mandatory=$true)]
        [string]$jsonFilePath,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("winget_applications", "external_applications")]
        [string]$section,
        
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$newObject
    )
    
    # Check if the JSON file exists
    if (-not (Test-Path -Path $jsonFilePath)) {
        # Create the directory if it doesn't exist
        $jsonDir = Split-Path -Parent $jsonFilePath
        if (-not (Test-Path $jsonDir)) {
            New-Item -Path $jsonDir -ItemType Directory -Force | Out-Null
        }
        
        # Create a new JSON file with empty arrays
        $baseJson = @{
            "winget_applications" = @()
            "external_applications" = @()
        }
        $baseJson | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonFilePath
    }
    
    # Read the existing JSON
    $jsonContent = Get-Content -Path $jsonFilePath -Raw | ConvertFrom-Json
    
    # Ensure the section exists - safely add it if missing or handle existing property
    if (-not ($jsonContent.PSObject.Properties.Name -contains $section)) {
        # Section property doesn't exist at all, so add it
        $jsonContent | Add-Member -MemberType NoteProperty -Name $section -Value @()
    } elseif ($null -eq $jsonContent.$section) {
        # Section exists but is null, replace with empty array
        $jsonContent.$section = @()
    }
    
    # Check if object already exists by name
    $exists = $jsonContent.$section | Where-Object { $_.name -eq $newObject.name }
    
    # Add the object if it doesn't exist, otherwise update it
    if (-not $exists) {
        # Make sure the section is an array
        if ($null -eq $jsonContent.$section) {
            $jsonContent.$section = @()
        }
        
        # Add new object to the array
        $sectionArray = @($jsonContent.$section)
        $sectionArray += $newObject
        $jsonContent.$section = $sectionArray
    } else {
        # Replace the existing object with the new one
        $index = 0
        $foundIndex = -1
        
        foreach ($item in $jsonContent.$section) {
            if ($item.name -eq $newObject.name) {
                $foundIndex = $index
                break
            }
            $index++
        }
        
        if ($foundIndex -ge 0) {
            $jsonContent.$section[$foundIndex] = $newObject
        }
    }
    
    # Save the updated JSON
    $jsonContent | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonFilePath
}

# Maintain compatibility with older code that uses this function name
function AppendToJson {
    param (
        [string]$json_location, 
        [hashtable]$data
    )
    
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
