# ClamAV Security Scan

This GitHub Action performs virus scanning using ClamAV.

## Inputs

- `exclude_paths` (optional): Directories to exclude from scan, provided as a comma-separated string (e.g., `node_modules,.git,__pycache__`). Default is `.git`.
- `run_clamav_scan` (required): Flag to control whether to run the ClamAV scan and upload to Artifactory. Default is `false`.
- `report_name` (optional): The name of the report file. Default is `clamscan-results`.
- `artifact_name` (optional): Provide the Artifact Name to download for Artifact Scanning.
- `artifact_path` (optional): Provide the Artifact Download Location for Artifact Scanning. Default is `./ArtifactAIPC`.
- `upload_to_artifactory` (optional): Flag to control whether to upload to Artifactory. Default is `false`.

## Permissions

This action requires read permissions for all available permissions.
```yaml
permissions: read-all
```

## Parameters

```yaml
  report_name:
    description: 'Name of the report file'
    required: false
    default: 'clamscan-results'
  exclude_paths:
    description: 'Directories to exclude from scan, provide with a comma separated string. i.e. node_modules,.git,__pycache__'
    required: false
    default: '.git'
  artifact_name:
    description: 'Provide the Artifact Name to download for Artifact Scanning'
    required: false
  artifact_path:
    description: 'Provide the Artifact Download Location for Artifact Scanning'
    required: false
    default: './ArtifactAIPC'
  upload_to_artifactory:
    description: 'Flag to control whether to upload to Artifactory'
    required: false
    default: 'false'
  run_clamav_scan:
    description: 'run clamav and also upload to artifactory'
    required: true
    default: 'false'
```

## This step downloads the specified artifact if the artifact name and path are provided and the upload to Artifactory flag is set to do the virus Scan on the Artifacts.
```yaml
    - name: Download artifact
      if: ${{ inputs.artifact_name != '' && inputs.artifact_path != '' && inputs.upload_to_artifactory == 'true' }}
      uses: actions/download-artifact@v4
      with:
        name: ${{ inputs.artifact_name }}
        path: ${{ inputs.artifact_path }}
```

## This step lists the contents of the downloaded artifact if the artifact name and path are provided and the upload to Artifactory flag is set.
```yaml
    - name: Show downloaded artifact content
      if: ${{ inputs.artifact_name != '' && inputs.artifact_path != '' && inputs.upload_to_artifactory == 'true' }}
      run: |
        echo "Listing contents of the downloaded artifact:"
        ls -R ${{ inputs.artifact_path }}
      shell: bash
```

## This step installs ClamAV and stops the freshclam service.
```yaml      
    - name: Install ClamAV
      run: |
        sudo apt-get update
        sudo apt-get install -y clamav clamav-daemon
        sudo systemctl stop clamav-freshclam
      shell: bash
```

## This step updates the ClamAV virus database and starts the freshclam service.
```yaml
    - name: Update Virus Database
      run: |
        sudo freshclam
        sudo systemctl start clamav-freshclam
      shell: bash
```

## This step verifies the ClamAV installation by checking its version.
```yaml
    - name: Verify installation
      run: |
        clamscan --version
      shell: bash
```

## This step runs the ClamAV virus scan on the specified directory, excluding the specified paths, and outputs the results to a log file.
```yaml
    - name: Run ClamAV Virus Scan
      shell: bash
      continue-on-error: true
      run: |
        # Define directories to exclude
        EXCLUDE_DIRS="${{ inputs.exclude_paths }}"

        # Build the --exclude-dir flags
        EXCLUDE_FLAGS=""
        IFS=',' read -ra DIRS <<< "$EXCLUDE_DIRS"
        for DIR in "${DIRS[@]}"; do
          EXCLUDE_FLAGS+="--exclude-dir=$DIR "
        done

        # Determine the directory to scan
        if [ -n "${{ inputs.artifact_name }}" ]; then
          SCAN_DIR="${{ inputs.artifact_path }}"
        else
          SCAN_DIR="."
        fi

        # Run ClamAV scan
        clamscan -r $SCAN_DIR $EXCLUDE_FLAGS --verbose --detect-pua --alert-broken --log=${{ inputs.report_name }}.log

        # Check scan results
        SCAN_RESULT=$?

        cat ${{ inputs.report_name }}.log

        # Fail the workflow if viruses are found
        # Exit codes: 0 = No viruses, 1 = Viruses found, 2 = Error
        if [ $SCAN_RESULT -eq 1 ]; then
          echo "**ClamAV**: ⚠️ Virus detected! Please review the ClamAV scan reports."
          exit 1
        elif [ $SCAN_RESULT -eq 2 ]; then
          echo "ClamAV scan encountered an error!"
        fi
```

 ## This step uploads the ClamAV scan results to Artifactory if the corresponding flags are set.
 ```yaml
    - name: Upload ClamAV Scan Results
      if: ${{ inputs.upload_to_artifactory == 'true' || inputs.run_clamav_scan == 'true'}}
      uses: actions/upload-artifact@v4
      with:
        name: ${{ inputs.report_name }}
        path: ${{ inputs.report_name }}.log
```