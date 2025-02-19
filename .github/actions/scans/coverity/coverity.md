# Coverity Scan with Community Credentials

This GitHub Action installs a specific version of Coverity and performs a scan.

## Inputs

- `project` (optional): Project name in Coverity Scan. Default is `${{ github.repository }}`.
- `token` (required): Secret project token for accessing Coverity Scan.
- `email` (required): Where Coverity Scan should send notifications.
- `build_language` (optional): Which Coverity Scan language pack to download. Default is `cxx`.
- `build_platform` (optional): Which Coverity Scan platform pack to download. Default is `linux64`.
- `command` (optional): Command to pass to `cov-build`. Default is `make`.
- `working-directory` (optional): Working directory to set for all steps. Default is `${{ github.workspace }}`.
- `version` (optional): (Informational) The source version being built. Default is `${{ github.sha }}`.
- `description` (optional): (Informational) A description for this particular build. Default is `coverity-scan-action ${{ github.repository }} / ${{ github.ref }}`.
- `report_name` (optional): The name of the report file. Default is `coverity-results`.
- `upload_to_artifactory` (optional): Flag to control whether to upload to Artifactory. Default is `false`.
- `run_coverity_scan` (optional): Flag to control whether to run the Coverity scan and upload to Artifactory. Default is `false`.

## Permissions

This action requires read permissions for all available permissions.

## Usage

```yaml
name: Coverity Scan with Community Credentials
description: "This action installs a specific version of Coverity."

inputs:
  project:
    description: Project name in Coverity Scan.
    default: ${{ github.repository }}
    required: false
  token:
    description: Secret project token for accessing Coverity Scan.
    required: true
  email:
    description: Where Coverity Scan should send notifications.
    required: true
  build_language:
    description: Which Coverity Scan language pack to download.
    default: cxx
    required: false
  build_platform:
    description: Which Coverity Scan platform pack to download.
    default: linux64
    required: false
  command:
    description: Command to pass to cov-build.
    default: make
    required: false
  working-directory:
    description: Working directory to set for all steps.
    default: ${{ github.workspace }}
    required: false
  version:
    description: (Informational) The source version being built.
    default: ${{ github.sha }}
    required: false
  description:
    description: (Informational) A description for this particular build.
    default: coverity-scan-action ${{ github.repository }} / ${{ github.ref }}
    required: false
  report_name:
    description: 'Name of the report file'
    required: false
    default: 'coverity-results'
  upload_to_artifactory:
    description: 'Flag to control whether to upload to Artifactory'
    required: false
    default: 'false'
  run_coverity_scan:
    description: 'run coverity scan and also upload to artifactory'
    required: false
    default: 'false'

permissions: read-all

runs: 
  using: "composite"
  steps:
    - name: URL encode project name
      id: project
      run: echo "project=${{ inputs.project }}" | sed -e 's:/:%2F:g' -e 's/ /%20/g' >> $GITHUB_OUTPUT
      shell: bash

    - name: Lookup Coverity Build Tool hash
      id: coverity-cache-lookup
      run: |
        hash=$(curl https://scan.coverity.com/download/${{ inputs.build_language }}/${{ inputs.build_platform }} \
                --data "token=${TOKEN}&project=${{ steps.project.outputs.project }}&md5=1"); \
        echo "hash=${hash}" >> $GITHUB_OUTPUT
      shell: bash
      env:
        TOKEN: ${{ inputs.token }}

    - name: Cache Coverity Build Tool
      id: cov-build-cache
      uses: actions/cache@v4
      with:
        path: ${{ inputs.working-directory }}/cov-analysis
        key: cov-build-${{ inputs.build_language }}-${{ inputs.build_platform }}-${{ steps.coverity-cache-lookup.outputs.hash }}

    - name: Download Coverity Build Tool (${{ inputs.build_language }} / ${{ inputs.build_platform }})
      if: "steps.cov-build-cache.outputs.cache-hit != 'true'"
      run: |
        curl https://scan.coverity.com/download/${{ inputs.build_language }}/${{ inputs.build_platform }} \
          --no-progress-meter \
          --output cov-analysis.tar.gz \
          --data "token=${TOKEN}&project=${{ steps.project.outputs.project }}"
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        TOKEN: ${{ inputs.token }}

    - if: steps.cov-build-cache.outputs.cache-hit != 'true'
      run: mkdir -p cov-analysis
      shell: bash
      working-directory: ${{ inputs.working-directory }}
  
    - if: steps.cov-build-cache.outputs.cache-hit != 'true'
      run: tar -xzf cov-analysis.tar.gz --strip 1 -C cov-analysis
      shell: bash
      working-directory: ${{ inputs.working-directory }}

    - name: Build with cov-build
      run: |
        export PATH="${PWD}/cov-analysis/bin:${PATH}"
        cov-build --dir cov-int --no-command --fs-capture-search ./ --fs-capture-search-exclude-regex "cov-analysis"
      shell: bash
      working-directory: ${{ inputs.working-directory }}
    
    - name: Archive results
      run: tar -czvf ${{ inputs.report_name }}.tgz cov-int
      shell: bash
      working-directory: ${{ inputs.working-directory }}
    
    - name: Upload Coverity Scan Results
      if: ${{ inputs.upload_to_artifactory == 'true' || inputs.run_coverity_scan == 'true'}}
      uses: actions/upload-artifact@v4
      with:
        name: ${{ inputs.report_name }}
        path: ${{ inputs.report_name }}.tgz

    - name: Submit results to Coverity Scan
      run: |
        curl \
          --form token="${TOKEN}" \
          --form email="${{ inputs.email }}" \
          --form file=@${{ inputs.report_name }}.tgz \
          --form version="${{ inputs.version }}" \
          --form description="${{ inputs.description }}" \
          "https://scan.coverity.com/builds?project=${{ steps.project.outputs.project }}"
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        TOKEN: ${{ inputs.token }}