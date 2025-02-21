# Lint Action

This GitHub Action performs linting for the project using various tools.

## Inputs

- `run_linting` (required): Run linting and also upload to Artifactory. Default is `false`.
- `upload_to_artifactory` (optional): Flag to control whether to upload reports to Artifactory. Default is `false`.

## Permissions

This action requires read permissions for all available permissions.
```yaml
permissions: read-all
```

## Parameters

```yaml
  upload_to_artifactory:
    description: 'Flag to control whether to upload reports to Artifactory'
    required: false
    default: 'false'
  run_linting:
    description: 'Run Linting and also upload to artifactory'
    required: true
    default: 'false'
```
## This step sets up the Python environment with the specified version.
```yaml
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.10.11'
```

## This step installs the necessary linting tools using pip.
```yaml
    - name: Install linting tools
      run: |
        python -m pip install --upgrade pip
        pip install flake8 pylint black isort
        pip install flake8-html pylint-report
      shell: bash
```

## This step runs Black to check the formatting of the code and outputs the results to a file.
```yaml
    - name: Run Black Formatting Check
      continue-on-error: true
      run: |
        mkdir -p reports/black
        black --check . > reports/black/formatting-check.txt
      shell: bash
```

## This step runs Flake8 to lint the code and outputs the results in HTML format.
```yaml
    - name: Run Flake8 Linting
      continue-on-error: true
      run: |
        mkdir -p reports/flake8
        flake8 --format=html --htmldir=reports/flake8 .
      shell: bash
```

## This step runs Pylint to lint the Python files and outputs the results to a file.
```yaml
    - name: Run Pylint
      continue-on-error: true
      run: |
        mkdir -p reports/pylint
        pylint **/*.py > reports/pylint/pylint-report.txt
      shell: bash
```

## This step runs Isort to check the import sorting and outputs the results to a file.
```yaml
    - name: Run Isort Import Sorting Check
      continue-on-error: true
      run: |
        mkdir -p reports/isort
        isort --check-only . > reports/isort/import-check.txt
      shell: bash
```

## This step uploads the linting reports to Artifactory if the corresponding flags are set.
```yaml
    - name: Upload Linting Reports
      if: ${{ inputs.upload_to_artifactory == 'true' || inputs.run_linting == 'true' }}
      uses: actions/upload-artifact@v4
      with:
        name: linting-reports
        path: reports/
```