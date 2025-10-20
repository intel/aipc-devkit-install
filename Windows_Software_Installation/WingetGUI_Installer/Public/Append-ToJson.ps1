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
    
    # Simple retry mechanism with exponential backoff
    $maxRetries = 5
    $retryCount = 0
    $success = $false
    
    while ($retryCount -lt $maxRetries -and -not $success) {
        try {
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
                $baseJson | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonFilePath -Encoding UTF8
            }
            
            # Read the existing JSON with error handling
            $jsonContent = $null
            try {
                $jsonText = Get-Content -Path $jsonFilePath -Raw -Encoding UTF8
                if ([string]::IsNullOrWhiteSpace($jsonText)) {
                    # Empty file, create default structure
                    $jsonContent = @{
                        "winget_applications" = @()
                        "external_applications" = @()
                    }
                } else {
                    $jsonContent = $jsonText | ConvertFrom-Json
                }
            }
            catch {
                Write-Warning "JSON file appears to be corrupted. Creating new file."
                # Create a new JSON file with empty arrays
                $jsonContent = @{
                    "winget_applications" = @()
                    "external_applications" = @()
                }
            }
            
            # Ensure the section exists
            if (-not ($jsonContent.PSObject.Properties.Name -contains $section)) {
                $jsonContent | Add-Member -MemberType NoteProperty -Name $section -Value @()
            } elseif ($null -eq $jsonContent.$section) {
                $jsonContent.$section = @()
            }
            
            # Use the array directly (do not wrap in @())
            $sectionArray = $jsonContent.$section
            
            # Check if object already exists by name or id
            $exists = $false
            $foundIndex = -1
            
            for ($i = 0; $i -lt $sectionArray.Count; $i++) {
                $item = $sectionArray[$i]
                # Check for match by id first (more reliable), then by name
                if (($newObject.PSObject.Properties.Name -contains "id" -and 
                     $item.PSObject.Properties.Name -contains "id" -and 
                     $item.id -eq $newObject.id) -or 
                    ($item.name -eq $newObject.name)) {
                    $exists = $true
                    $foundIndex = $i
                    break
                }
            }
            
            # Add the object if it doesn't exist, otherwise update it
            if (-not $exists) {
                # Add new object to the array
                $sectionArray += $newObject
                $jsonContent.$section = $sectionArray
                
                # Log the addition for debugging
                Write-Host "Added new application to ${section}: $($newObject.name)" -ForegroundColor Green
            } else {
                # Update existing object
                if ($foundIndex -ge 0) {
                    # Create a combined object
                    $combinedObject = $sectionArray[$foundIndex].PSObject.Copy()
                    
                    # Update properties from the new object
                    foreach ($property in $newObject.PSObject.Properties) {
                        if ($combinedObject.PSObject.Properties.Name -contains $property.Name) {
                            $combinedObject.$($property.Name) = $property.Value
                        } else {
                            $combinedObject | Add-Member -MemberType NoteProperty -Name $property.Name -Value $property.Value
                        }
                    }
                    
                    # Update the array
                    $sectionArray[$foundIndex] = $combinedObject
                    $jsonContent.$section = $sectionArray
                    
                    # Log the update for debugging
                    Write-Host "Updated existing application in ${section}: $($newObject.name)" -ForegroundColor Cyan
                }
            }
            
            # Save the updated JSON with proper encoding
            $jsonString = $jsonContent | ConvertTo-Json -Depth 5
            Set-Content -Path $jsonFilePath -Value $jsonString -Encoding UTF8
            
            $success = $true
        }
        catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                # Exponential backoff: wait longer each time
                $waitTime = [Math]::Min(1000, 50 * [Math]::Pow(2, $retryCount))
                Start-Sleep -Milliseconds $waitTime
            } else {
                throw "Failed to update JSON file after $maxRetries attempts: $_"
            }
        }
    }
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
                # Check if application already exists (by id first, then by name)
                $exists = $false
                $foundIndex = -1
                $index = 0
                
                foreach ($existing_app in $merged_data.winget_applications) {
                    # Check for match by id first (more reliable), then by name
                    if (($new_app.PSObject.Properties.Name -contains "id" -and 
                         $existing_app.PSObject.Properties.Name -contains "id" -and 
                         $existing_app.id -eq $new_app.id) -or 
                        ($existing_app.name -eq $new_app.name)) {
                        $exists = $true
                        $foundIndex = $index
                        break
                    }
                    $index++
                }
                
                if (-not $exists) {
                    # Add new application
                    $merged_data.winget_applications += $new_app
                    Write-Host "Added new winget application: $($new_app.name)" -ForegroundColor Green
                } else {
                    # Update existing application with combined properties
                    $combinedApp = $merged_data.winget_applications[$foundIndex].PSObject.Copy()
                    
                    # Update properties from the new object
                    foreach ($property in $new_app.PSObject.Properties) {
                        if ($combinedApp.PSObject.Properties.Name -contains $property.Name) {
                            # Update existing property
                            $combinedApp.$($property.Name) = $property.Value
                        } else {
                            # Add new property
                            $combinedApp | Add-Member -MemberType NoteProperty -Name $property.Name -Value $property.Value
                        }
                    }
                    
                    # Update in array
                    $merged_data.winget_applications[$foundIndex] = $combinedApp
                    Write-Host "Updated existing winget application: $($new_app.name)" -ForegroundColor Cyan
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
                $exists = $false
                $foundIndex = -1
                $index = 0
                
                foreach ($existing_app in $merged_data.external_applications) {
                    if ($existing_app.name -eq $new_app.name) {
                        $exists = $true
                        $foundIndex = $index
                        break
                    }
                    $index++
                }
                
                if (-not $exists) {
                    # Add new application
                    $merged_data.external_applications += $new_app
                    Write-Host "Added new external application: $($new_app.name)" -ForegroundColor Green
                } else {
                    # Update existing application with combined properties
                    $combinedApp = $merged_data.external_applications[$foundIndex].PSObject.Copy()
                    
                    # Update properties from the new object
                    foreach ($property in $new_app.PSObject.Properties) {
                        if ($combinedApp.PSObject.Properties.Name -contains $property.Name) {
                            # Update existing property
                            $combinedApp.$($property.Name) = $property.Value
                        } else {
                            # Add new property
                            $combinedApp | Add-Member -MemberType NoteProperty -Name $property.Name -Value $property.Value
                        }
                    }
                    
                    # Update in array
                    $merged_data.external_applications[$foundIndex] = $combinedApp
                    Write-Host "Updated existing external application: $($new_app.name)" -ForegroundColor Cyan
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

<#
    Helper function to remove an object from a specified section of a JSON file by id
#>
function Remove-FromJsonById {
    param (
        [Parameter(Mandatory=$true)]
        [string]$jsonFilePath,
        [Parameter(Mandatory=$true)]
        [ValidateSet("winget_applications", "external_applications")]
        [string]$section,
        [Parameter(Mandatory=$true)]
        [string]$id
    )

    Write-Host "Remove-FromJsonById called with: $jsonFilePath, $section, $id" -ForegroundColor Magenta

    if (-not (Test-Path -Path $jsonFilePath)) {
        Write-Warning "JSON file does not exist: $jsonFilePath"
        return
    }

    $jsonText = Get-Content -Path $jsonFilePath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        Write-Warning "JSON file is empty: $jsonFilePath"
        return
    }

    $jsonContent = $jsonText | ConvertFrom-Json

    if (-not ($jsonContent.PSObject.Properties.Name -contains $section)) {
        Write-Warning "Section '$section' does not exist in JSON."
        return
    }

    # Always treat as array, even if only one object
    $sectionArray = @()
    if ($jsonContent.$section -is [System.Collections.IEnumerable] -and
        -not ($jsonContent.$section -is [string])) {
        $sectionArray = @($jsonContent.$section)
    } elseif ($null -ne $jsonContent.$section) {
        $sectionArray = @($jsonContent.$section)
    }

    # Flatten in case it's an array of arrays (PowerShell quirk)
    $flatArray = @()
    foreach ($item in $sectionArray) {
        if ($item -is [System.Collections.IEnumerable] -and -not ($item -is [string])) {
            $flatArray += $item
        } else {
            $flatArray += ,$item
        }
    }

    # Remove the entry by id (case-insensitive, trimmed)
    $filteredArray = @()
    foreach ($item in $flatArray) {
        $itemId = ""
        if ($item.PSObject.Properties.Name -contains "id") {
            $itemId = ($item.id | Out-String).Trim()
        }
        if ($itemId -ieq $id.Trim()) {
            Write-Host "Match found: Removing item.id '$itemId' (target id: '$($id.Trim())')" -ForegroundColor DarkYellow
            # Do not add to filteredArray, i.e., remove it
        } else {
            $filteredArray += $item
        }
    }

    $jsonContent.$section = $filteredArray

    # If both arrays are empty, delete the file
    $wingetEmpty = -not $jsonContent.winget_applications -or $jsonContent.winget_applications.Count -eq 0
    $externalEmpty = -not $jsonContent.external_applications -or $jsonContent.external_applications.Count -eq 0

    if ($wingetEmpty -and $externalEmpty) {
        Remove-Item -Path $jsonFilePath -Force
        Write-Host "All applications removed. Deleted $jsonFilePath." -ForegroundColor Red
    } else {
        # Save the updated JSON
        $jsonString = $jsonContent | ConvertTo-Json -Depth 5
        Set-Content -Path $jsonFilePath -Value $jsonString -Encoding UTF8
        Write-Host "Removed application from $section by id: $id" -ForegroundColor Yellow
    }
}
