#  OVMS Launcher

A PowerShell script that downloads, configures, and starts OpenVINO Model Server.

## Quick Start

```powershell
# Start text model on GPU (default)
.\ovms_setup.ps1

# Start text model on CPU
.\ovms_setup.ps1 -Target CPU

# Start text model on NPU (Intel AI PC)
.\ovms_setup.ps1 -Target NPU

# Start image generation on GPU
.\ovms_setup.ps1 -Model image

# Start custom model
.\ovms_setup.ps1 -Model "OpenVINO/Mistral-7B-Instruct-v0.2-int4-cw-ov" -Target NPU
```

## Features

- **One Command**: Downloads OVMS, downloads models, starts server
- **Smart Defaults**: Automatically selects best model for each device
- **Auto Download**: Models download automatically from Hugging Face
- **Device Optimized**: Different models optimized for GPU/CPU/NPU

## Default Models

### Text Generation
- **GPU/CPU**: `OpenVINO/Phi-3.5-mini-instruct-int4-ov`
- **NPU**: `OpenVINO/Phi-3.5-mini-instruct-int4-cw-ov` (NPU-optimized)

### Image Generation
- **GPU**: `OpenVINO/FLUX.1-schnell-int4-ov`
- **CPU**: `OpenVINO/stable-diffusion-v1-5-int8-ov`

## Parameters

- `-Model`: "text" (default), "image", or full OpenVINO model name
- `-Target`: "GPU" (default), "CPU", or "NPU"
- `-Port`: REST API port (default: 8000)
- `-Help`: Show detailed help message

## Getting Help

The script includes comprehensive help options:

```powershell
# Show built-in help with examples
.\ovms_setup.ps1 -Help

# PowerShell native help
Get-Help .\ovms_setup.ps1
Get-Help .\ovms_setup.ps1 -Examples
Get-Help .\ovms_setup.ps1 -Detailed
```

## Examples

```powershell
# Basic usage
.\ovms_setup.ps1                                    # Phi-3 on GPU
.\ovms_setup.ps1 -Target CPU                        # Phi-3 on CPU
.\ovms_setup.ps1 -Target NPU                        # Phi-3 on NPU
.\ovms_setup.ps1 -Model image                       # FLUX on GPU

# Custom models
.\ovms_setup.ps1 -Model "OpenVINO/gpt-j-6b-int4-cw-ov" -Target NPU
.\ovms_setup.ps1 -Model "OpenVINO/stable-diffusion-v1-5-fp16-ov" -Target GPU
.\ovms_setup.ps1 -Model "OpenVINO/Mistral-7B-Instruct-v0.2-int4-cw-ov" -Target CPU

# Custom port
.\ovms_setup.ps1 -Port 9000
```

## API Access

Once started, the API is available at: `http://localhost:8000/v3`

### Test with curl:
```bash
(Invoke-WebRequest -Uri "http://localhost:8000/v3/chat/completions" `
 -Method POST `
 -Headers @{ "Content-Type" = "application/json" } `
 -Body '{"model": "OpenVINO/Phi-3.5-mini-instruct-int4-ov", "max_tokens": 30, "temperature": 0, "stream": false, "messages": [{"role": "system", "content": "You are a helpful assistant."}, {"role": "user", "content": "What are the 3 main tourist attractions in Paris?"}]}').Content
 
```

### Test with Python:
```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8000/v3",
    api_key="unused"
)

response = client.chat.completions.create(
    model="OpenVINO/Phi-3.5-mini-instruct-int4-ov",
    messages=[{"role": "user", "content": "Hello!"}],
    max_tokens=50
)

print(response.choices[0].message.content)
```

## What It Does

1. **Downloads OVMS**: Automatically downloads OpenVINO Model Server v2025.2.1 if not present
2. **Initializes Environment**: Runs setupvars.ps1 to properly configure OpenVINO environment
3. **Selects Model**: Chooses the best model for your target device
4. **Downloads Model**: Downloads the model from Hugging Face Hub automatically
5. **Starts Server**: Launches OVMS with optimal parameters for the model type
6. **Ready to Use**: API available immediately at the specified port

## Requirements

- Windows PowerShell 5.1+ or PowerShell Core 7+
- Internet connection (for downloads)
- For NPU: Intel AI PC with NPU drivers

## Device Recommendations

- **GPU**: Fastest performance, best for production
- **CPU**: Works everywhere, good for development
- **NPU**: power efficient

## Stop Server

Press `Ctrl+C` to stop the server.
