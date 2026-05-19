# AI PC Application Installer

## Version

- Current release: v3.0

## Objective

The AI PC Application Installer provides a unified way to set up Intel AI PC development environments for engagements, workshops, and events.

It is designed to:

- Standardize setup across supported operating systems
- Install and configure required development tools and runtimes
- Handle dependencies and installation order
- Track installed components for maintenance and uninstall workflows

## Key Features

- Unified installer framework for Windows and Linux setup flows
- Package-based and script-driven installation support
- Dependency-aware install experience
- Installation tracking and uninstall support
- Logging for troubleshooting and validation

## Supported Operating Systems

- Windows
- Linux

## Apps Supported

### Windows

Supported via the Windows installer flow:

- Visual Studio Code
- Visual Studio Community 2026 Edition
- Python 3.12
- Clink
- Git for Windows
- CMake
- uv
- Vulkan SDK
- Node.js LTS
- Foundry Local
- Ollama
- Continue (VS Code Extension)
- npm (Node Package Manager)
- Intel AI Playground
- NuGet Installation

Windows Installation Step by Step Guide:
- [Windows_Software_Installation/README.md](Windows_Software_Installation/README.md)

### Linux

Supported via the Linux setup flow:

- Intel GPU and NPU driver setup (Ubuntu 24.04)
- OpenVINO toolkit environment
- OpenVINO GenAI setup
- Ollama setup for local LLM workflows
- Python tooling via uv and virtual environments
- Google Chrome
- Visual Studio Code
- OpenVINO notebooks and AI workshop repositories

Linux Installation Step by Step Guide:
- [Linux_Software_Installation/README.md](Linux_Software_Installation/README.md)

## Installation Guides

For detailed, OS-specific installation steps, use:

- Windows installation guide: [Windows_Software_Installation/README.md](Windows_Software_Installation/README.md)
- Linux installation guide: [Linux_Software_Installation/README.md](Linux_Software_Installation/README.md)

## Repository Structure

- Windows installer assets: [Windows_Software_Installation](Windows_Software_Installation)
- Linux installer assets: [Linux_Software_Installation](Linux_Software_Installation)

## Support

- Vijay: vijay.chandrashekar@intel.com
- Praveen: praveen.k.kundurthy@intel.com

## License

MIT License

Copyright (c) 2025 Intel

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


