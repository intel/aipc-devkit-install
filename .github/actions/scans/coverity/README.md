# Coverity Scan with Community Credentials

This GitHub Action installs a specific version of Coverity and performs a scan.

## Inputs

- `project` (required): Project name in Coverity Scan. Default is `${{ github.repository }}`.
- `token` (required): Secret project token for accessing Coverity Scan.
- `email` (required): Where Coverity Scan should send notifications.
- `build_language` (required): Which Coverity Scan language pack to download. Default is `other`.
- `build_platform` (required): Which Coverity Scan platform pack to download. Default is `linux64`.
- `command` (required): Command to pass to `cov-build`. Default is `make`.
- `working-directory` (optional): Working directory to set for all steps. Default is `${{ github.workspace }}`.
- `version` (required): (Informational) The source version being built. Default is `${{ github.sha }}`.
- `description` (optional): (Informational) A description for this particular build. Default is `coverity-scan-action ${{ github.repository }} / ${{ github.ref }}`.
- `report_name` (optional): The name of the report file. Default is `coverity-results`.
- `upload_to_artifactory` (optional): Flag to control whether to upload to Artifactory. Default is `false`.
- `run_coverity_scan` (optional): Flag to control whether to run the Coverity scan and upload to Artifactory. Default is `false`.

## Permissions

This action requires read permissions for all available permissions.
```yaml
permissions: read-all
```

## Parameters

```yaml
  project:
    description: Project name in Coverity Scan.
    default: ${{ github.repository }}
    required: true
  token:
    description: Secret project token for accessing Coverity Scan.
    required: true
  email:
    description: Where Coverity Scan should send notifications.
    required: true
  build_language:
    description: Which Coverity Scan language pack to download.
    default: other
    required: true
  build_platform:
    description: Which Coverity Scan platform pack to download.
    default: linux64
    required: true
  command:
    description: Command to pass to cov-build.
    default: make
    required: true
  working-directory:
    description: Working directory to set for all steps.
    default: ${{ github.workspace }}
    required: false
  version:
    description: (Informational) The source version being built.
    default: ${{ github.sha }}
    required: true
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
```

## This step encodes the project name for use in URLs and HTTP forms.
```yaml
    - name: URL encode project name
      id: project
      run: echo "project=${{ inputs.project }}" | sed -e 's:/:%2F:g' -e 's/ /%20/g' >> $GITHUB_OUTPUT
      shell: bash
```

## This step looks up the hash of the Coverity Build Tool to determine if there's been an update.
```yaml
    - name: Lookup Coverity Build Tool hash
      id: coverity-cache-lookup
      run: |
        hash=$(curl https://scan.coverity.com/download/${{ inputs.build_language }}/${{ inputs.build_platform }} \
                --data "token=${TOKEN}&project=${{ steps.project.outputs.project }}&md5=1"); \
        echo "hash=${hash}" >> $GITHUB_OUTPUT
      shell: bash
      env:
        TOKEN: ${{ inputs.token }}
```

## This step caches the Coverity Build Tool to avoid downloading the archive on every run.
```yaml
    - name: Cache Coverity Build Tool
      id: cov-build-cache
      uses: actions/cache@v4
      with:
        path: ${{ inputs.working-directory }}/cov-analysis
        key: cov-build-${{ inputs.build_language }}-${{ inputs.build_platform }}-${{ steps.coverity-cache-lookup.outputs.hash }}
```

## Downloads the Coverity Build Tool if it's not already cached.
```yaml
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
  ```

## This step creates the `cov-analysis` directory if it's not already cached.
```yaml
    - if: steps.cov-build-cache.outputs.cache-hit != 'true'
      run: mkdir -p cov-analysis
      shell: bash
      working-directory: ${{ inputs.working-directory }}
 ```

 ## This step extracts the Coverity Build Tool if it's not already cached.
 ```yaml
    - if: steps.cov-build-cache.outputs.cache-hit != 'true'
      run: tar -xzf cov-analysis.tar.gz --strip 1 -C cov-analysis
      shell: bash
      working-directory: ${{ inputs.working-directory }}
```

## This step builds the project using `cov-build`.
```yaml
    - name: Build with cov-build
      run: |
        export PATH="${PWD}/cov-analysis/bin:${PATH}"
        cov-build --dir cov-int ${{ inputs.command }} --fs-capture-search-exclude-regex "cov-analysis"
      shell: bash
      working-directory: ${{ inputs.working-directory }}
```

##  This step archives the Coverity scan results.
```yaml    
    - name: Archive results
      run: tar -czvf ${{ inputs.report_name }}.tgz cov-int
      shell: bash
      working-directory: ${{ inputs.working-directory }}
```

## This step uploads the Coverity scan results to Artifactory if the corresponding flags are set.
```yaml
    - name: Upload Coverity Scan Results
      if: ${{ inputs.upload_to_artifactory == 'true' || inputs.run_coverity_scan == 'true'}}
      uses: actions/upload-artifact@v4
      with:
        name: ${{ inputs.report_name }}
        path: ${{ inputs.report_name }}.tgz
```

## This step submits the Coverity scan results to Coverity Scan.
```yaml
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
```