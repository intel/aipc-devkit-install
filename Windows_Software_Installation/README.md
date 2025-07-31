# AI Dev Kit Repository Downloader

A PowerShell script that downloads and extracts AI/ML repositories for Intel AI Dev Kit setup with parallel downloads, retry logic, and progress tracking.

## Features

- ✅ **Parallel Downloads**: Downloads up to 5 repositories simultaneously
- ✅ **Retry Logic**: Automatic retry with exponential backoff (2s, 4s, 8s delays)
- ✅ **Progress Tracking**: Real-time download progress and completion status
- ✅ **Smart Skipping**: Skips existing directories and downloaded files
- ✅ **Automatic Extraction**: Extracts ZIP files and organizes into proper directories
- ✅ **Error Handling**: Comprehensive error handling and status reporting
- ✅ **Resume Capability**: Can be run multiple times safely

## Quick Start

### Prerequisites
- Windows PowerShell 5.1 or PowerShell Core
- Internet connection
- Administrative privileges (recommended)

### Basic Usage

1. **Run with default settings** (downloads to `C:\Intel`):
   ```powershell
   .\get_repos.ps1
   ```

2. **Specify custom directory**:
   ```powershell
   .\get_repos.ps1 -DevKitWorkingDir "D:\MyAIProjects"
   ```

3. **Change retry attempts**:
   ```powershell
   .\get_repos.ps1 -MaxRetries 5
   ```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `DevKitWorkingDir` | String | `C:\Intel` | Target directory for downloads |
| `MaxRetries` | Integer | `3` | Maximum retry attempts per download |

## Current Repositories

The script downloads the following AI/ML repositories:

1. **OpenVINO Notebooks** - Jupyter notebooks for OpenVINO toolkit
2. **OpenVINO Build & Deploy** - Build and deployment examples
3. **Ollama IPEX-LLM** - Ollama with Intel Extension for PyTorch
4. **OpenVINO GenAI** - Generative AI examples and tools
5. **WebNN Workshop** - Web Neural Network API workshop materials
6. **Open Model Zoo** - Pre-trained models collection

## Directory Structure

After successful execution, you'll have:

```
C:\Intel\
├── openvino_notebooks\
├── openvino_build_deploy\
├── ollama-ipex-llm\
├── openvino_genai\
├── webnn_workshop\
└── open_model_zoo\
```

## Adding New Repositories

### Step 1: Add to Repository Array

Open `get_repos.ps1` and locate the `$repos` array (around line 74). Add your new repository:

```powershell
$repos = @(
    # ... existing repos ...
    @{ Name = "your_repo_name"; Uri = "https://github.com/owner/repo/archive/refs/heads/main.zip"; File = "repo.zip" }
)
```

### Step 2: Repository Entry Format

Each repository entry requires three properties:

```powershell
@{ 
    Name = "final_directory_name";           # Directory name after extraction
    Uri = "https://download.url/file.zip";   # Download URL
    File = "downloaded_filename.zip"         # Local filename for download
}
```

### Step 3: Common URL Patterns

**GitHub Repository Downloads:**
- **Main/Master Branch**: `https://github.com/owner/repo/archive/refs/heads/main.zip`
- **Specific Branch**: `https://github.com/owner/repo/archive/refs/heads/branch-name.zip`
- **Tagged Release**: `https://github.com/owner/repo/archive/refs/tags/v1.0.0.zip`
- **Release Asset**: `https://github.com/owner/repo/releases/download/v1.0.0/filename.zip`

### Step 4: Handle Special Extraction (If Needed)

If your repository extracts to a different directory name than expected, add a case to the extraction switch statement (around line 235):

```powershell
switch ($name) {
    # ... existing cases ...
    "your_repo_name" { 
        if (Test-Path "extracted-directory-name") {
            Rename-Item "extracted-directory-name" $name 
        }
    }
}
```

## Troubleshooting

### Common Issues

**1. Download Failures**
- Check internet connection
- Verify URLs are accessible
- Some repositories may require authentication

**2. Extraction Errors**
- Ensure sufficient disk space
- Check file permissions
- Verify ZIP file integrity

**3. Permission Errors**
- Run PowerShell as Administrator
- Check write permissions to target directory

### Script Behavior

**Re-running the Script:**
- Skips existing directories automatically
- Skips already downloaded ZIP files
- Only downloads/extracts missing items
- Safe to run multiple times

**Progress Display:**
- Shows download completion count (e.g., "Downloads completed: 3/6")
- Individual download progress every 5MB
- Color-coded status messages

## Output Examples

### Successful Run
```
Waiting for 6 downloads to complete... (0 skipped)
Downloads completed: 0/6
Downloads completed: 1/6
Downloads completed: 6/6

Extracting 2025.2.zip -> openvino_notebooks...
SUCCESS: openvino_notebooks ready.
...
Script completed successfully!
```

### Subsequent Run (Skipping Existing)
```
SKIP: openvino_notebooks directory already exists, skipping download.
SKIP: openvino_build_deploy directory already exists, skipping download.
...
No downloads needed - all repositories already exist or are downloaded.
```

## Performance Notes

- **Parallel Downloads**: Up to 5 simultaneous downloads
- **Memory Usage**: ~1MB buffer per download stream
- **Retry Strategy**: Exponential backoff (2s, 4s, 8s delays)
- **Progress Checking**: Every 500ms for completion status

## License

This script is provided as-is for Intel AI Dev Kit setup. Individual repositories have their own licenses.
