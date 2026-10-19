# Agent Skills open standard compatibility

Intel AI PC Developer Kit **Agent Skills** are packaged for the open **[Agent Skills](https://agentskills.io/home)** format ([specification](https://agentskills.io/specification)): a folder with **`SKILL.md`** (YAML frontmatter + instructions), optionally plus scripts and references.

That format is supported across many agents (for example **Cursor**, **Claude Code**, **Gemini CLI**, **OpenCode**, **Goose**, **GitHub Copilot**, **OpenHands**, **Hermes Agent**, **OpenClaw**, and others listed on [agentskills.io](https://agentskills.io/home)).

## What we ship

| Layer | Location | Purpose |
|-------|----------|---------|
| **Portable skills (standard)** | [`skills/`](../skills/) | Copy or point your agent at these folders — works with any Agent Skills–compatible host |
| **Windows invokers** | [`scripts/windows/`](../scripts/windows/) | PowerShell entry points; JSON on stdout |
| **Host adapters (optional)** | [`adapters/`](../adapters/) | Extra metadata for **Hermes** and **OpenClaw** (validated on Intel AI PC) |
| **Skill cards (internal)** | [`skill-cards/`](../skill-cards/) | Intel pack metadata, risk class, schemas |

## Install in your agent

1. Clone or copy the `agent-skills` folder from this Dev Kit repository.
2. Register the [`skills/`](../skills/) directory using your agent’s Agent Skills / skills path (see your product docs on [agentskills.io](https://agentskills.io/home)).
3. Run invokers from the **`agent-skills` repository root** in PowerShell unless your skill instructions say otherwise.

Example (verify, read-only):

```powershell
cd path\to\agent-skills
.\scripts\windows\invoke-devkit-verify.ps1
```

## Hermes and OpenClaw

These hosts are **first-class on Windows** for local OVMS provider setup:

- [`configure-hermes-ovms.ps1`](../scripts/windows/configure-hermes-ovms.ps1)
- [`configure-openclaw-ovms.ps1`](../scripts/windows/configure-openclaw-ovms.ps1)

Other Agent Skills–compatible agents can run the same **`scripts/windows/`** invokers; only **provider configuration** steps differ by product (see `intel-agent-provider-config` skill).

## Specification notes

- Skill **`name`** matches the folder name (lowercase, hyphens).
- Use **`compatibility`** in frontmatter for Windows / Dev Kit / network requirements.
- Intel-specific fields live under **`metadata`** (string keys and string values per spec).

Open standard discussion: [github.com/agentskills/agentskills](https://github.com/agentskills/agentskills).
