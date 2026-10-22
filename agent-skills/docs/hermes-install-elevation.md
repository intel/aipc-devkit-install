# Hermes — Dev Kit install elevation (UAC)

Intel Dev Kit **install** requires **Administrator**. Hermes normally runs as a **standard user**. The install invoker supports **UAC elevation** so the agent can drive the install without asking the user to open a separate elevated PowerShell.

## User experience

1. Hermes explains that install needs **Administrator** and asks for **approval** (skill `-Approve` + chat consent).
2. Hermes runs the install invoker with **`-Elevate`**.
3. Windows shows a **UAC** dialog — the user clicks **Yes** (this is the elevation approval).
4. A **separate elevated PowerShell window** runs Setup_1 / Setup_2 (may take hours). Hermes returns immediately with `functional_status: partial` and an **`install_job`** id.
5. Hermes **polls** by re-invoking the **`intel-devkit-install`** skill with **`-WaitInstallJob -InstallJobId <id>`** (from JSON **`install_job.job_id`** / **`install_poll`**) until `functional_status` is `pass` or `fail`. Do **not** paste script paths to the user.
6. After **`pass`**, tell the user the Dev Kit install completed. Invoke **`intel-devkit-verify`**, OVMS, provider config, or smoke only when the user asked for that step, from the **non-elevated** session.

## Commands (from `agent-skills` root)

**Start install (agent / Hermes — always use `-Elevate` on standard-user sessions):**

```powershell
.\scripts\windows\invoke-devkit-install.ps1 -Approve -Elevate
```

**Poll until complete (repeat while `partial` and `install_job.phase` is `running`):**

```powershell
.\scripts\windows\invoke-devkit-install.ps1 -WaitInstallJob -InstallJobId '<job_id from JSON>'
```

Job artifacts: `C:\temp\logs\install\jobs\<job_id>\` (`progress.json`, `skill-result.json`, `manifest.json`).

## Hermes configuration

| Setting | Recommendation |
|---------|----------------|
| `approvals.mode` | `approve` — user confirms the elevation command in chat |
| `terminal.timeout` | Default **180s** is enough for **poll** commands only; install runs **detached** in the elevated window |
| Long install | Roadmap: progress events in JSON; today use `install_log_tail` on poll responses |

Hermes **command approval** is not Windows elevation. **UAC** is always required once per elevated install launch.

## Skill instructions

Portable: [`skills/software-development/intel-devkit-install/SKILL.md`](../skills/software-development/intel-devkit-install/SKILL.md).  
Hermes overlay: [`adapters/hermes/skills/intel-devkit-install/SKILL.md`](../adapters/hermes/skills/intel-devkit-install/SKILL.md).

## Errors

| Code | Meaning |
|------|---------|
| `UAC_DENIED` | User declined UAC or elevated process exited before `running` |
| `INSTALL_JOB_ID_REQUIRED` | Poll without `-InstallJobId` |
| `I1-admin` fail (no `-Elevate`) | Legacy path — use `-Elevate` for Hermes |

After successful install, do **not** keep using an elevated Hermes session for OVMS (see [admin-vs-user-runtime.md](admin-vs-user-runtime.md)).
