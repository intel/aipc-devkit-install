# Bandit Actions Scan

This GitHub Action performs security scanning using Bandit.

## Inputs

- `report_name` (optional): The name of the report file. Default is `bandit-results`.
- `upload_to_artifactory` (optional): Flag to control whether to upload to Artifactory. Default is `false`.
- `run_bandit_scan` (optional): Flag to control whether to run the Bandit scan and upload to Artifactory. Default is `false`.

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
    default: 'bandit-results'
  upload_to_artifactory:
    description: 'Flag to control whether to upload to Artifactory'
    required: false
    default: 'false'
  run_bandit_scan:
    description: 'run bandit scan and also upload to artifactory'
    required: false
    default: 'false'
```

## This step sets up the Python environment with the specified version.

```yaml    
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.10.11'
```
## This step installs Bandit using pip.

```yaml
    - name: Install Bandit
      shell: bash
      run: |
        python -m pip install --upgrade pip
        pip install bandit
```

## This step runs the Bandit scan on the repository and outputs the results in JSON format.     
```yaml
    - name: Run Bandit Scan
      shell: bash
      continue-on-error: true
      run: |
        bandit -r . -f json -o ${{ inputs.report_name }}.json
```

## This step uploads the Bandit scan results to Artifactory if the corresponding flags are set.
```yaml
    - name: Upload Bandit Scan Results
      if: ${{ inputs.upload_to_artifactory == 'true' || inputs.run_bandit_scan == 'true' }}
      uses: actions/upload-artifact@v4
      with:
        name: ${{ inputs.report_name }}
        path: ${{ inputs.report_name }}.json
```
      