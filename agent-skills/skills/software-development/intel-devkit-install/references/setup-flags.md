# intel-devkit-install setup flags

Run these from the `agent-skills` repository root, in addition to the commands in `SKILL.md`.

Silent CLI install is the default (`Setup_1.ps1 install` in a child PowerShell process).

| Flag | Effect |
|---|---|
| `-Setup2Full` | Full upstream `Setup_2.ps1` (hours) instead of the default **genai-minimal** path (fast, enough for verify **V3**) |
| `-Setup2Only` | Skip Setup_1 |
| `-Setup2StopWhenGenAiReady` | Stop full Setup_2 once `openvino_genai` is ready |
| `-PreflightOnly` | Check only; do not install. Still requires `-Approve` |
| `-InstallRoot` | Installer root override |
| `-DevKitWorkingDir` | Working directory override (default `C:\Intel`) |

OVMS is not part of Setup_1 or Setup_2. After a passing install, verify, then `intel-ovms-agentic-setup`, as a standard user.
