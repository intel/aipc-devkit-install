# Build The Project

This GitHub Action builds the project and uploads it to the Artifactory.

## Inputs

- `upload_to_artifactory` (optional): Flag to control whether to upload to Artifactory. Default is `false`.

## Permissions

This action requires read permissions for all available permissions.
```yaml
permissions: read-all
```

## Parameters

```yaml
  upload_to_artifactory:
    description: 'Flag to control whether to upload to Artifactory'
    required: false
    default: 'false'
```

## This step runs the build script using PowerShell.
```yaml
    - name: Run Build
      run: .\build\Build.bat
      shell: pwsh
 ``` 

## This step prepares the files for upload by copying them to the upload directory.  
```yaml
    - name: Prepare files for upload
      run: |
        mkdir -p upload
        cp dist/* upload/
        cp -r AIDevKit upload/
        cp CHANGELOG.md upload/
        cp License.txt upload/
        cp Installation_Guide.md upload/README.md
      shell: pwsh
 ```
     
## This step uploads the prepared files as an artifact to Artifactory if the corresponding flag is set.
 ```yaml
    - name: Upload binary as artifact
      if: ${{ inputs.upload_to_artifactory == 'true' }}
      uses: actions/upload-artifact@v4
      with:
        name: ArtifactAIPC
        path: upload/
 ```     