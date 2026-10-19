# Intel AI PC Developer Kit — Agent Skills (DevKit 4.0)

This document indexes the **Agent Skills** package for the Intel AI PC Developer Kit. It is intentionally **not** named `README.md` so it can sit beside the installer repository’s main README without a merge conflict.

Skills follow the open **[Agent Skills](https://agentskills.io/home)** standard and work with Hermes, OpenClaw, Cursor, Claude Code, and [other compatible agents](https://agentskills.io/home).

| Location | Description |
|----------|-------------|
| [`agent-skills/`](agent-skills/) | Agent skills, scripts, and documentation — **start with the [Agent Skills README](agent-skills/README.md)** |
| `Windows_Software_Installation/` | Dev Kit installer (in the full `training.developer.aipc` repository) |

## Quick links

- **Users:** [agent-skills/README.md](agent-skills/README.md) — setup, requirements, and commands  
- **Agent Skills hosts:** [agent-skills/docs/agent-skills-compatibility.md](agent-skills/docs/agent-skills-compatibility.md)  
- **Implementers:** [agent-skills/docs/implementation-status.md](agent-skills/docs/implementation-status.md)  

When `agent-skills/` sits next to `Windows_Software_Installation/` in the installer repo, scripts detect the Dev Kit root automatically.

## Merging into `training.developer.aipc`

1. Copy the **`agent-skills/`** folder to the installer repo root (see [`agent-skills/docs/planning/GITHUB-SHARE.md`](agent-skills/docs/planning/GITHUB-SHARE.md)).  
2. Optionally copy this file to the installer repo root as **`AGENT-SKILLS.md`**.  
3. Add a short **Agent skills** subsection to the installer **`README.md`** linking to `agent-skills/README.md` — do not replace the existing README.
