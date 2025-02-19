# Trivy Vulnerability Scan

This GitHub Action performs vulnerability scanning using Trivy.

## Inputs

- `scan-ref` (optional): Scan reference. Default is `requirements.txt`.
- `scan-type` (optional): Scan type to use for scanning vulnerability. Default is `fs`.
- `scanners` (optional): Comma-separated list of security issues to detect. Default is `vuln,secret,misconfig,license`.
- `severity` (optional): Severities of vulnerabilities to display. Default is `UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL`.
- `report_name` (optional): Name of the report file. Default is `trivy-results`.
- `upload_to_artifactory` (optional): Flag to control whether to upload the results to Artifactory. Default is `false`.
- `run_trivy_scan` (optional): Flag to control whether to run the Trivy scan and upload to Artifactory. Default is `false`.

## Permissions

This action requires read permissions for all available permissions.

## Usage

```yaml
name: Trivy Vulnerability Scan
description: Perform vulnerability scanning using Trivy
inputs:
  scan-ref:
    description: 'Scan reference'
    required: false
    default: 'requirements.txt'
  scan-type:
    description: 'Scan type to use for scanning vulnerability'
    required: false
    default: 'fs'
  scanners:
    description: 'Comma-separated list of security issues to detect'
    required: false
    default: 'vuln,secret,misconfig,license'
  severity:
    description: 'Severities of vulnerabilities to display'
    required: false
    default: 'UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL'
  report_name:
    description: 'Name of the report file'
    required: false
    default: 'trivy-results'
  upload_to_artifactory:
    description: 'Flag to control whether to upload the results to Artifactory'
    required: false
    default: 'false'
  run_trivy_scan:
    description: 'run trivy scan and also upload to artifactory'
    required: false
    default: 'false'

permissions: read-all

runs:
  using: 'composite'
  steps:
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.10.11'
    
    - name: Run Trivy vulnerability scanner in fs mode
      uses: aquasecurity/trivy-action@0.28.0
      with:
        scan-type: 'fs'
        scan-ref: 'Prerequisites/PythonModules/requirements.txt'
        severity: 'UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL'
        format: 'json'
        output: 'trivy-results.json'
        scanners: 'vuln,secret,misconfig,license'                                        

    - name: Upload Vulnerability Scan Results
      if: ${{ inputs.upload_to_artifactory == 'true' || inputs.run_trivy_scan == 'true' }}
      uses: actions/upload-artifact@v4
      with:
        name: ${{ inputs.report_name }}
        path: ${{ inputs.report_name }}.json