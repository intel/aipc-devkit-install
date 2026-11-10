# OVMS Agentic Launcher

A PowerShell script that downloads, configures, and starts OpenVINO Model Server with full
**tool/function calling**, **reasoning parser**, and **agentic workflow** support (v2026.4.0).

## Quick Start

```powershell
# Device-default text model (Qwen3-8B on GPU)
.\ovms_agentic_setup.ps1

# Qwen3.6-35B-A3B on GPU
.\ovms_agentic_setup.ps1 -Model OpenVINO/Qwen3.6-35B-A3B-int4-ov -Target GPU

# Gemma 4 26B-A4B on GPU
.\ovms_agentic_setup.ps1 -Model OpenVINO/gemma-4-26b-a4b-it-int4-ov -Target GPU

# Phi-4-mini on CPU — auto-downloads chat_template.jinja
.\ovms_agentic_setup.ps1 -Model OpenVINO/Phi-4-mini-instruct-int4-ov -Target CPU

# Qwen3-8B on NPU (NPU-optimized variant)
.\ovms_agentic_setup.ps1 -Model OpenVINO/Qwen3-8B-int4-cw-ov -Target NPU

# Image generation on GPU
.\ovms_agentic_setup.ps1 -Model image -Target GPU

# Qwen3.8-27B int4 on GPU (large VRAM — see warnings at startup)
.\ovms_agentic_setup.ps1 -Pull -Model OpenVINO/Qwen3.8-27B-int4-ov -Target GPU
```

## Upgrading OVMS

If you previously downloaded an older OVMS bundle (for example v2026.0), delete the `ovms` folder next to these scripts and run again so the script can fetch **OVMS 2026.4.0** from [OpenVINO storage](https://storage.openvinotoolkit.org/repositories/openvino_model_server/packages/2026.4.0/).

## Minimal prerequisites (without full Dev Kit Setup_1 / Setup_2)

Use **`Setup_OVMS_Prerequisites.ps1`** when you only need OVMS, not Visual Studio, Python, or OpenVINO GenAI from Setup_2.

```powershell
# Elevated PowerShell — installs VC++ x64, Git.Git, and winget if missing
.\Setup_OVMS_Prerequisites.ps1

# Checks only
.\Setup_OVMS_Prerequisites.ps1 -VerifyOnly -Target GPU
```

Package list: `JSON\ovms_prerequisites.json`. Then run `ovms_agentic_setup.ps1` as a **standard user**.

## Features

- **Tool/Function Calling**: Tool and reasoning parsers are auto-detected by OVMS 2026.4 (no `--tool_parser` / `--reasoning_parser` flags); `--enable_tool_guided_generation true` is passed for text models (except NPU)
- **One Command**: Downloads OVMS, configures model flags, starts server
- **Full Model IDs**: Pass the full `OpenVINO/...` model ID to `-Model` (no shorthands); `text` / `image` select the device default
- **Smart Defaults**: Qwen3-8B on GPU/NPU, Phi-4-mini on CPU
- **MoE Workaround**: Automatic `MOE_USE_MICRO_GEMM_PREFILL=0` for Qwen3-Coder
- **Chat Template Auto-Download**: Mistral and Phi-4 templates fetched automatically
- **Built-in Tests**: `-Test` switch runs API tests against a running server

## Default Models

Selected with `-Model text` (the default) or `-Model image`.

### Text Generation
| Device | Model |
|--------|-------|
| **GPU** | `OpenVINO/Qwen3-8B-int4-ov` |
| **CPU** | `OpenVINO/Phi-4-mini-instruct-int4-ov` |
| **NPU** | `OpenVINO/Qwen3-8B-int4-cw-ov` |

### Image Generation
| Device | Model |
|--------|-------|
| **GPU** | `OpenVINO/FLUX.1-schnell-int4-ov` |
| **CPU** | `OpenVINO/stable-diffusion-v1-5-int8-ov` |
| **NPU** | `OpenVINO/FLUX.1-schnell-int8-ov` |

## Supported Models

Pass the full model ID to `-Model`.

| Model | Notes |
|-------|-------|
| `OpenVINO/Qwen3.6-35B-A3B-int4-ov` | Large; GPU recommended; startup warnings |
| `OpenVINO/gemma-4-26b-a4b-it-int4-ov` | Large; GPU recommended; startup warnings |
| `OpenVINO/Qwen3.8-27B-int4-ov` | Large; GPU recommended; startup warnings |
| `OpenVINO/Muse-Glimmer-30B-int4-ov` | **Experimental** (text + image input); may need development builds of OpenVINO/OVMS; startup warnings |
| `OpenVINO/Qwen3.5-27B-int4-ov` | Large; GPU recommended |
| `OpenVINO/Qwen3-8B-int4-ov` | GPU/CPU; use `OpenVINO/Qwen3-8B-int4-cw-ov` on NPU |
| `OpenVINO/Qwen3-4B-int4-ov` | |
| `OpenVINO/Phi-4-mini-instruct-int4-ov` | chat_template auto-download |
| `OpenVINO/Mistral-7B-Instruct-v0.3-int4-ov` | chat_template auto-download |
| `OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int4-ov` | ~19GB VRAM, MoE workaround |
| `OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int8-ov` | ~34GB VRAM, MoE workaround |
| `OpenVINO/gpt-oss-20b-int4-ov` | ~16GB VRAM |

## Parameters

- `-Model`: Full OpenVINO model ID, or `text` (default) / `image` for the device default
- `-Target`: `GPU` (default), `CPU`, or `NPU`
- `-Port`: REST API port (default: 8000)
- `-CacheDir`: Compiled model cache directory (default: `.ovcache`)
- `-ModelRepositoryPath`: Model storage directory (default: `models`)
- `-Pull`: Pre-download the model before starting the server
- `-ModelName`: Override the API-facing model name (default: the full model ID)
- `-Test`: Test a running server without starting a new one
- `-Help`: Show detailed help message

## Getting Help

```powershell
# Built-in help with all options and examples
.\ovms_agentic_setup.ps1 -Help

# PowerShell native help
Get-Help .\ovms_agentic_setup.ps1
Get-Help .\ovms_agentic_setup.ps1 -Examples
Get-Help .\ovms_agentic_setup.ps1 -Detailed
```

## Examples

```powershell
# Default: device-default text model (Qwen3-8B on GPU)
.\ovms_agentic_setup.ps1

# Recommended examples
.\ovms_agentic_setup.ps1 -Model OpenVINO/Qwen3.6-35B-A3B-int4-ov -Target GPU
.\ovms_agentic_setup.ps1 -Model OpenVINO/gemma-4-26b-a4b-it-int4-ov -Target GPU

# Other models
.\ovms_agentic_setup.ps1 -Model OpenVINO/Qwen3-4B-int4-ov -Target GPU
.\ovms_agentic_setup.ps1 -Model OpenVINO/Phi-4-mini-instruct-int4-ov -Target CPU
.\ovms_agentic_setup.ps1 -Model OpenVINO/gpt-oss-20b-int4-ov -Target GPU

# NPU
.\ovms_agentic_setup.ps1 -Model OpenVINO/Qwen3-8B-int4-cw-ov -Target NPU

# Large models (high VRAM)
.\ovms_agentic_setup.ps1 -Pull -Model OpenVINO/Qwen3.8-27B-int4-ov -Target GPU   # see startup warnings
.\ovms_agentic_setup.ps1 -Model OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int4-ov -Target GPU   # 19GB+
.\ovms_agentic_setup.ps1 -Model OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int8-ov -Target GPU   # 34GB+

# Pre-download then start with a custom port
.\ovms_agentic_setup.ps1 -Pull -Model OpenVINO/Qwen3.6-35B-A3B-int4-ov -Target GPU -Port 9000
```

## API Access

Once started, the API is available at: `http://localhost:8000/v3`

> **Note**: The API model name is the full model ID (e.g. `OpenVINO/Qwen3.6-35B-A3B-int4-ov`)
> unless you override it with `-ModelName`. The examples below use Qwen3.6-35B-A3B and Gemma 4.

### Test with PowerShell (Invoke-WebRequest):

```powershell
# Text generation
(Invoke-WebRequest -Uri "http://localhost:8000/v3/chat/completions" `
 -Method POST `
 -UseBasicParsing `
 -Headers @{ "Content-Type" = "application/json" } `
 -Body '{"model": "OpenVINO/gemma-4-26b-a4b-it-int4-ov", "max_tokens": 30, "temperature": 0, "stream": false, "messages": [{"role": "system", "content": "You are a helpful assistant."}, {"role": "user", "content": "What are the 3 main tourist attractions in Paris?"}]}').Content
```

```powershell
# Tool/function calling
(Invoke-WebRequest -Uri "http://localhost:8000/v3/chat/completions" `
 -Method POST `
 -UseBasicParsing `
 -Headers @{ "Content-Type" = "application/json" } `
 -Body '{"model": "OpenVINO/Qwen3.6-35B-A3B-int4-ov", "max_tokens": 200, "temperature": 0, "stream": false, "tools": [{"type": "function", "function": {"name": "get_current_weather", "description": "Get the current weather", "parameters": {"type": "object", "properties": {"location": {"type": "string"}}, "required": ["location"]}}}], "messages": [{"role": "user", "content": "What is the weather in Paris?"}]}').Content
```

```powershell
# Code generation (Qwen3-Coder) — tool call to execute code
(Invoke-WebRequest -Uri "http://localhost:8000/v3/chat/completions" `
 -Method POST `
 -UseBasicParsing `
 -Headers @{ "Content-Type" = "application/json" } `
 -Body '{"model": "OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int4-ov", "max_tokens": 300, "temperature": 0, "stream": false, "tool_choice": "required", "tools": [{"type": "function", "function": {"name": "run_code", "description": "Execute a code snippet and return the output", "parameters": {"type": "object", "properties": {"code": {"type": "string", "description": "The code to execute"}, "language": {"type": "string", "enum": ["python", "javascript", "bash"]}}, "required": ["code", "language"]}}}], "messages": [{"role": "system", "content": "You are an expert coding assistant."}, {"role": "user", "content": "Write and run a Python function that returns the first 10 Fibonacci numbers."}]}').Content
```

### Test with Python:

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8000/v3",
    api_key="unused"
)

# Basic text generation
response = client.chat.completions.create(
    model="OpenVINO/gemma-4-26b-a4b-it-int4-ov",
    messages=[{"role": "user", "content": "Hello!"}],
    max_tokens=50
)
print(response.choices[0].message.content)
```

```python
# Tool/function calling
import json

from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8000/v3",
    api_key="unused"
)

tools = [
    {
        "type": "function",
        "function": {
            "name": "get_current_weather",
            "description": "Get the current weather in a given location",
            "parameters": {
                "type": "object",
                "properties": {
                    "location": {"type": "string", "description": "City name, e.g. Paris"},
                    "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
                },
                "required": ["location"]
            }
        }
    }
]

response = client.chat.completions.create(
    model="OpenVINO/Qwen3.6-35B-A3B-int4-ov",
    messages=[{"role": "user", "content": "What's the weather like in Paris right now?"}],
    tools=tools,
    max_tokens=200
)

choice = response.choices[0]
if choice.message.tool_calls:
    tool_call = choice.message.tool_calls[0]
    print(f"Function: {tool_call.function.name}")
    print(f"Args:     {tool_call.function.arguments}")
else:
    print(choice.message.content)
```

```python
# Code generation tool call (Qwen3-Coder)
import json
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8000/v3",
    api_key="unused"
)

code_tools = [
    {
        "type": "function",
        "function": {
            "name": "run_code",
            "description": "Execute a code snippet and return the output",
            "parameters": {
                "type": "object",
                "properties": {
                    "code": {"type": "string", "description": "The code to execute"},
                    "language": {"type": "string", "enum": ["python", "javascript", "bash"]}
                },
                "required": ["code", "language"]
            }
        }
    }
]

response = client.chat.completions.create(
    model="OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int4-ov",
    messages=[
        {"role": "system", "content": "You are an expert coding assistant."},
        {"role": "user", "content": "Write and run a Python function that returns the first 10 Fibonacci numbers."}
    ],
    tools=code_tools,
    tool_choice="required",   # force a tool call instead of a plain text reply
    max_tokens=300
)

choice = response.choices[0]
if choice.message.tool_calls:
    tool_call = choice.message.tool_calls[0]
    args = json.loads(tool_call.function.arguments)
    print(f"Function: {tool_call.function.name}")
    print(f"Language: {args.get('language')}")
    print(f"Code:\n{args.get('code')}")
else:
    print(choice.message.content)
```

## Built-in Test Mode

The `-Test` switch runs API tests against an already-running server without starting a new one:

```powershell
# Test the default text model on port 8000
.\ovms_agentic_setup.ps1 -Test

# Test a specific model
.\ovms_agentic_setup.ps1 -Test -Model OpenVINO/Qwen3.6-35B-A3B-int4-ov -Target GPU

# Test on a custom port
.\ovms_agentic_setup.ps1 -Test -Model OpenVINO/gemma-4-26b-a4b-it-int4-ov -Port 9000

# Test image generation endpoint
.\ovms_agentic_setup.ps1 -Test -Model image
```

The test suite runs:
1. **Connectivity check** — `GET /v3/models`
2. **Text generation** — Paris tourist attractions prompt
3. **Tool call** — Weather function call test

## Model Name Reference

The API model name is the full model ID, e.g. `OpenVINO/Qwen3.6-35B-A3B-int4-ov` or
`OpenVINO/gemma-4-26b-a4b-it-int4-ov`. Use the same string in the `model` field of API requests.

> You can override the API name at startup: `.\ovms_agentic_setup.ps1 -Model OpenVINO/Qwen3-4B-int4-ov -ModelName "my-model"`

## Requirements

- Windows PowerShell 5.1+ or PowerShell Core 7+
- Internet connection (for OVMS and model downloads)
- For NPU: Intel AI PC with NPU drivers
- For large models (Qwen3.8-27B, Qwen3-Coder, GPT-oss): substantial GPU VRAM; Qwen3.8-27B shows warnings at startup

## Stop Server

Press `Ctrl+C` to stop the server.
