<#
.SYNOPSIS
    JSON file helpers for tracking installed applications.

.DESCRIPTION
    Functions for appending to, updating, and removing entries from the
    uninstall tracking JSON file.
#>

function Append-ToJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$jsonFilePath,

        [Parameter(Mandatory=$true)]
        [ValidateSet("winget_applications", "external_applications")]
        [string]$section,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$newObject
    )

    $maxRetries = 5
    $retryCount = 0
    $success = $false

    while ($retryCount -lt $maxRetries -and -not $success) {
        try {
            # Create file with default structure if it doesn't exist
            if (-not (Test-Path -Path $jsonFilePath)) {
                $jsonDir = Split-Path -Parent $jsonFilePath
                if (-not (Test-Path $jsonDir)) {
                    New-Item -Path $jsonDir -ItemType Directory -Force | Out-Null
                }
                $baseJson = @{
                    "winget_applications"    = @()
                    "external_applications"  = @()
                }
                $baseJson | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonFilePath -Encoding UTF8
            }

            # Read existing JSON
            $jsonContent = $null
            try {
                $jsonText = Get-Content -Path $jsonFilePath -Raw -Encoding UTF8
                if ([string]::IsNullOrWhiteSpace($jsonText)) {
                    $jsonContent = @{
                        "winget_applications"   = @()
                        "external_applications" = @()
                    }
                } else {
                    $jsonContent = $jsonText | ConvertFrom-Json
                }
            }
            catch {
                Write-Warning "JSON file appears to be corrupted. Creating new file."
                $jsonContent = @{
                    "winget_applications"   = @()
                    "external_applications" = @()
                }
            }

            # Ensure section exists
            if (-not ($jsonContent.PSObject.Properties.Name -contains $section)) {
                $jsonContent | Add-Member -MemberType NoteProperty -Name $section -Value @()
            } elseif ($null -eq $jsonContent.$section) {
                $jsonContent.$section = @()
            }

            $sectionArray = $jsonContent.$section

            # Check if object already exists by id or name
            $exists = $false
            $foundIndex = -1
            for ($i = 0; $i -lt $sectionArray.Count; $i++) {
                $item = $sectionArray[$i]
                if (($newObject.PSObject.Properties.Name -contains "id" -and
                     $item.PSObject.Properties.Name -contains "id" -and
                     $item.id -eq $newObject.id) -or
                    ($item.name -eq $newObject.name)) {
                    $exists = $true
                    $foundIndex = $i
                    break
                }
            }

            if (-not $exists) {
                $sectionArray += $newObject
                $jsonContent.$section = $sectionArray
                Write-Host "Added new application to ${section}: $($newObject.name)" -ForegroundColor Green
            } else {
                if ($foundIndex -ge 0) {
                    $combinedObject = $sectionArray[$foundIndex].PSObject.Copy()
                    foreach ($property in $newObject.PSObject.Properties) {
                        if ($combinedObject.PSObject.Properties.Name -contains $property.Name) {
                            $combinedObject.$($property.Name) = $property.Value
                        } else {
                            $combinedObject | Add-Member -MemberType NoteProperty -Name $property.Name -Value $property.Value
                        }
                    }
                    $sectionArray[$foundIndex] = $combinedObject
                    $jsonContent.$section = $sectionArray
                    Write-Host "Updated existing application in ${section}: $($newObject.name)" -ForegroundColor Cyan
                }
            }

            $jsonString = $jsonContent | ConvertTo-Json -Depth 5
            Set-Content -Path $jsonFilePath -Value $jsonString -Encoding UTF8
            $success = $true
        }
        catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                $waitTime = [Math]::Min(1000, 50 * [Math]::Pow(2, $retryCount))
                Start-Sleep -Milliseconds $waitTime
            } else {
                throw "Failed to update JSON file after $maxRetries attempts: $_"
            }
        }
    }
}

# Legacy compatibility wrapper
function AppendToJson {
    [CmdletBinding()]
    param(
        [string]$json_location,
        [hashtable]$data
    )

    if (-not $data.ContainsKey('winget_applications') -or -not $data.ContainsKey('external_applications')) {
        throw "Data must contain winget_applications and external_applications keys"
    }

    if (Test-Path -Path $json_location) {
        $existing_data = Get-Content -Path $json_location -Raw | ConvertFrom-Json
        $merged_data = $existing_data

        if (-not $merged_data.winget_applications)   { $merged_data.winget_applications   = @() }
        if (-not $merged_data.external_applications) { $merged_data.external_applications = @() }

        if ($data.ContainsKey('winget_applications')) {
            foreach ($new_app in $data.winget_applications) {
                $exists = $false
                $foundIndex = -1
                $index = 0
                foreach ($existing_app in $merged_data.winget_applications) {
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
                    $merged_data.winget_applications += $new_app
                } else {
                    $combinedApp = $merged_data.winget_applications[$foundIndex].PSObject.Copy()
                    foreach ($property in $new_app.PSObject.Properties) {
                        if ($combinedApp.PSObject.Properties.Name -contains $property.Name) {
                            $combinedApp.$($property.Name) = $property.Value
                        } else {
                            $combinedApp | Add-Member -MemberType NoteProperty -Name $property.Name -Value $property.Value
                        }
                    }
                    $merged_data.winget_applications[$foundIndex] = $combinedApp
                }
            }
        } else {
            $merged_data.winget_applications = @()
        }

        if ($data.ContainsKey('external_applications')) {
            foreach ($new_app in $data.external_applications) {
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
                    $merged_data.external_applications += $new_app
                } else {
                    $combinedApp = $merged_data.external_applications[$foundIndex].PSObject.Copy()
                    foreach ($property in $new_app.PSObject.Properties) {
                        if ($combinedApp.PSObject.Properties.Name -contains $property.Name) {
                            $combinedApp.$($property.Name) = $property.Value
                        } else {
                            $combinedApp | Add-Member -MemberType NoteProperty -Name $property.Name -Value $property.Value
                        }
                    }
                    $merged_data.external_applications[$foundIndex] = $combinedApp
                }
            }
        } else {
            $merged_data.external_applications = @()
        }

        $json_string = $merged_data | ConvertTo-Json -Depth 5
        Set-Content -Path $json_location -Value $json_string
    }
    else {
        $json_dir = Split-Path -Parent $json_location
        if (-not (Test-Path $json_dir)) {
            New-Item -Path $json_dir -ItemType Directory | Out-Null
        }
        New-Item -Path $json_location -ItemType File | Out-Null
        $json_string = $data | ConvertTo-Json -Depth 5
        Set-Content -Path $json_location -Value $json_string
    }
}

function Remove-FromJsonById {
    [CmdletBinding()]
    param(
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

    # Always treat as array
    $sectionArray = @()
    if ($jsonContent.$section -is [System.Collections.IEnumerable] -and
        -not ($jsonContent.$section -is [string])) {
        $sectionArray = @($jsonContent.$section)
    } elseif ($null -ne $jsonContent.$section) {
        $sectionArray = @($jsonContent.$section)
    }

    # Flatten in case of nested arrays
    $flatArray = @()
    foreach ($item in $sectionArray) {
        if ($item -is [System.Collections.IEnumerable] -and -not ($item -is [string])) {
            $flatArray += $item
        } else {
            $flatArray += ,$item
        }
    }

    # Remove matching entry
    $filteredArray = @()
    foreach ($item in $flatArray) {
        $itemId = ""
        if ($item.PSObject.Properties.Name -contains "id") {
            $itemId = ($item.id | Out-String).Trim()
        }
        if ($itemId -ieq $id.Trim()) {
            Write-Host "Match found: Removing item.id '$itemId' (target id: '$($id.Trim())')" -ForegroundColor DarkYellow
        } else {
            $filteredArray += $item
        }
    }

    $jsonContent.$section = $filteredArray

    # Delete file if both arrays are now empty
    $wingetEmpty   = -not $jsonContent.winget_applications   -or $jsonContent.winget_applications.Count -eq 0
    $externalEmpty = -not $jsonContent.external_applications -or $jsonContent.external_applications.Count -eq 0

    if ($wingetEmpty -and $externalEmpty) {
        Remove-Item -Path $jsonFilePath -Force
        Write-Host "All applications removed. Deleted $jsonFilePath." -ForegroundColor Red
    } else {
        $jsonString = $jsonContent | ConvertTo-Json -Depth 5
        Set-Content -Path $jsonFilePath -Value $jsonString -Encoding UTF8
        Write-Host "Removed application from $section by id: $id" -ForegroundColor Yellow
    }
}
