# OVMS Agentic Launcher

A PowerShell script that downloads, configures, and starts OpenVINO Model Server with full
**tool/function calling**, **reasoning parser**, and **agentic workflow** support (v2026.0).

## Quick Start

```powershell
# Qwen3-8B on GPU (default) — hermes3 tool parser + qwen3 reasoning parser
.\ovms_agentic_setup.ps1

# Phi-4-mini on CPU — phi4 tool parser
.\ovms_agentic_setup.ps1 -Model phi4 -Target CPU

# Qwen3-8B on NPU (NPU-optimized variant)
.\ovms_agentic_setup.ps1 -Model qwen3-8b -Target NPU

# Mistral-7B on GPU — auto-downloads chat_template.jinja
.\ovms_agentic_setup.ps1 -Model mistral -Target GPU


# Image generation on GPU
.\ovms_agentic_setup.ps1 -Model image -Target GPU
```

## Features

- **Tool/Function Calling**: Auto-configured `--tool_parser` per model
- **Reasoning Parsers**: Qwen3 thinking mode and GPT-oss reasoning supported
- **One Command**: Downloads OVMS, configures model flags, starts server
- **Smart Defaults**: Qwen3-8B on GPU/NPU, Phi-4-mini on CPU
- **MoE Workaround**: Automatic `MOE_USE_MICRO_GEMM_PREFILL=0` for Qwen3-Coder
- **Chat Template Auto-Download**: Mistral and Phi-4 templates fetched automatically
- **Built-in Tests**: `-Test` switch runs API tests against a running server

## Default Models

### Text Generation
| Device | Model | Tool Parser | Reasoning Parser |
|--------|-------|-------------|-----------------|
| **GPU** | `OpenVINO/Qwen3-8B-int4-ov` | hermes3 | qwen3 |
| **CPU** | `OpenVINO/Phi-4-mini-instruct-int4-ov` | phi4 | — |
| **NPU** | `OpenVINO/Qwen3-8B-int4-cw-ov` | hermes3 | — |

### Image Generation
| Device | Model |
|--------|-------|
| **GPU** | `OpenVINO/FLUX.1-schnell-int4-ov` |
| **CPU** | `OpenVINO/stable-diffusion-v1-5-int8-ov` |
| **NPU** | `OpenVINO/FLUX.1-schnell-int8-ov` |

## Model Shorthands

| Shorthand | Model | Tool Parser | Notes |
|-----------|-------|-------------|-------|
| `qwen3-8b` | `OpenVINO/Qwen3-8B-int4-ov` | hermes3 | + qwen3 reasoning (GPU/CPU) |
| `qwen3-4b` | `OpenVINO/Qwen3-4B-int4-ov` | hermes3 | |
| `phi4` | `OpenVINO/Phi-4-mini-instruct-int4-ov` | phi4 | + chat_template auto-download |
| `mistral` | `OpenVINO/Mistral-7B-Instruct-v0.3-int4-ov` | mistral | + chat_template auto-download |
| `qwen3-coder-int4` | `OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int4-ov` | qwen3coder | ~19GB VRAM, MoE workaround |
| `qwen3-coder-int8` | `OpenVINO/Qwen3-Coder-30B-A3B-Instruct-int8-ov` | qwen3coder | ~34GB VRAM, MoE workaround |
| `gpt-oss` | `OpenVINO/gpt-oss-20b-int4-ov` | gptoss | + gptoss reasoning, ~16GB VRAM |

## Parameters

- `-Model`: `text` (default), `image`, shorthand, or full OpenVINO model ID
- `-Target`: `GPU` (default), `CPU`, or `NPU`
- `-Port`: REST API port (default: 8000)
- `-CacheDir`: Compiled model cache directory (default: `.ovcache`)
- `-ModelRepositoryPath`: Model storage directory (default: `models`)
- `-Pull`: Pre-download the model before starting the server
- `-ModelName`: Override the API-facing model name
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
# Default: Qwen3-8B on GPU
.\ovms_agentic_setup.ps1

# Specific models
.\ovms_agentic_setup.ps1 -Model qwen3-4b -Target GPU
.\ovms_agentic_setup.ps1 -Model phi4 -Target CPU
.\ovms_agentic_setup.ps1 -Model mistral -Target GPU

.\ovms_agentic_setup.ps1 -Model gpt-oss -Target GPU

# NPU
.\ovms_agentic_setup.ps1 -Model qwen3-8b -Target NPU

# Large models (high VRAM)
.\ovms_agentic_setup.ps1 -Model qwen3-coder-int4 -Target GPU   # 19GB+
.\ovms_agentic_setup.ps1 -Model qwen3-coder-int8 -Target GPU   # 34GB+

# Pre-download then start
.\ovms_agentic_setup.ps1 -Pull -Model qwen3-8b

# Full model ID with custom port
.\ovms_agentic_setup.ps1 -Model "OpenVINO/Qwen3-8B-int4-ov" -Target GPU -Port 9000
```

## API Access

Once started, the API is available at: `http://localhost:8000/v3`

> **Note**: For Qwen3-8B the API model name is `Qwen3-8B` (auto-set by `--model_name`).
> For models without a name override, use the full model ID (e.g. `OpenVINO/Qwen3-4B-int4-ov`).

### Test with PowerShell (Invoke-WebRequest):

```powershell
# Text generation
(Invoke-WebRequest -Uri "http://localhost:8000/v3/chat/completions" `
 -Method POST `
 -UseBasicParsing `
 -Headers @{ "Content-Type" = "application/json" } `
 -Body '{"model": "Qwen3-8B", "max_tokens": 30, "temperature": 0, "stream": false, "messages": [{"role": "system", "content": "You are a helpful assistant."}, {"role": "user", "content": "What are the 3 main tourist attractions in Paris?"}]}').Content
```

```powershell
# Tool/function calling
(Invoke-WebRequest -Uri "http://localhost:8000/v3/chat/completions" `
 -Method POST `
 -UseBasicParsing `
 -Headers @{ "Content-Type" = "application/json" } `
 -Body '{"model": "Qwen3-8B", "max_tokens": 200, "temperature": 0, "stream": false, "tools": [{"type": "function", "function": {"name": "get_current_weather", "description": "Get the current weather", "parameters": {"type": "object", "properties": {"location": {"type": "string"}}, "required": ["location"]}}}], "messages": [{"role": "user", "content": "What is the weather in Paris?"}]}').Content
```

```powershell
# Code generation (Qwen3-Coder) — tool call to execute code
(Invoke-WebRequest -Uri "http://localhost:8000/v3/chat/completions" `
 -Method POST `
 -UseBasicParsing `
 -Headers @{ "Content-Type" = "application/json" } `
 -Body '{"model": "Qwen3-Coder-30B-A3B-Instruct", "max_tokens": 300, "temperature": 0, "stream": false, "tool_choice": "required", "tools": [{"type": "function", "function": {"name": "run_code", "description": "Execute a code snippet and return the output", "parameters": {"type": "object", "properties": {"code": {"type": "string", "description": "The code to execute"}, "language": {"type": "string", "enum": ["python", "javascript", "bash"]}}, "required": ["code", "language"]}}}], "messages": [{"role": "system", "content": "You are an expert coding assistant."}, {"role": "user", "content": "Write and run a Python function that returns the first 10 Fibonacci numbers."}]}').Content
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
    model="Qwen3-8B",
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
    model="Qwen3-8B",
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
    model="Qwen3-Coder-30B-A3B-Instruct",
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
# Test default model (Qwen3-8B) on port 8000
.\ovms_agentic_setup.ps1 -Test

# Test a specific model shorthand
.\ovms_agentic_setup.ps1 -Test -Model qwen3-4b -Target GPU

# Test on a custom port
.\ovms_agentic_setup.ps1 -Test -Model phi4 -Port 9000

# Test image generation endpoint
.\ovms_agentic_setup.ps1 -Test -Model image
```

The test suite runs:
1. **Connectivity check** — `GET /v3/models`
2. **Text generation** — Paris tourist attractions prompt
3. **Tool call** — Weather function call test

## Model Name Reference

When making API calls, use the correct model name for each model:

| Shorthand | API Model Name |
|-----------|---------------|
| `qwen3-8b` (default) | `Qwen3-8B` |
| `qwen3-4b` | `OpenVINO/Qwen3-4B-int4-ov` |
| `phi4` | `OpenVINO/Phi-4-mini-instruct-int4-ov` |
| `mistral` | `OpenVINO/Mistral-7B-Instruct-v0.3-int4-ov` |
| `qwen3-coder-int4` / `qwen3-coder-int8` | `Qwen3-Coder-30B-A3B-Instruct` |
| `gpt-oss` | `gpt-oss-20b` |

> You can also override the API name at startup: `.\ovms_agentic_setup.ps1 -Model qwen3-4b -ModelName "my-model"`

## Requirements

- Windows PowerShell 5.1+ or PowerShell Core 7+
- Internet connection (for OVMS and model downloads)
- For NPU: Intel AI PC with NPU drivers
- For large models (Qwen3-Coder, GPT-oss): 16–34GB GPU VRAM

## Stop Server

Press `Ctrl+C` to stop the server.
