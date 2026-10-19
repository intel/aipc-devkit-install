# Share `agent-skills` on GitHub

## Inner source (recommended): `training.developer.aipc`

**Branch name:** `DevKit4.0` — first commit on this branch adds **`agent-skills/`** at repo root (sibling to `Windows_Software_Installation/`). Optionally add **`AGENT-SKILLS.md`** at repo root (index only — **do not** replace the installer `README.md`).

Copy the entire **`agent-skills/`** folder to the **root** of the installer repo. Planning docs already live under `agent-skills/docs/planning/`.

```powershell
git clone https://github.com/intel-innersource/training.developer.aipc.git
cd training.developer.aipc
git fetch origin
git checkout -b DevKit4.0 origin/main   # use origin/master if that is the default branch

robocopy "C:\Users\mjdomeik\source\devkit4.0\agent-skills" `
         ".\agent-skills" /E

git add agent-skills
# Optional index (no conflict with installer README.md):
# copy AGENT-SKILLS.md from your devkit4.0 workspace to repo root, then: git add AGENT-SKILLS.md
git commit -m "Add agent-skills directory (DevKit 4.0 Quick Agent Track MVP)"
git push -u origin DevKit4.0
```

Do **not** commit Intel-confidential `.pptx` / `.docx` (keep them outside git).

---

## Standalone repo (optional)

If you keep a separate working repo (this `devkit4.0` folder):

```powershell
cd C:\Users\mjdomeik\source\devkit4.0
git init   # skip if already initialized
git add agent-skills AGENT-SKILLS.md .gitignore
git commit -m "Add agent-skills pack and planning docs"
git remote add origin https://github.com/YOUR_ORG/YOUR_REPO.git
git push -u origin main
```

---

## Zip handoff

```powershell
Compress-Archive -Path "C:\Users\mjdomeik\source\devkit4.0\agent-skills" `
  -DestinationPath "C:\Users\mjdomeik\source\devkit4.0\agent-skills.zip" -Force
```

---

## After landing in installer repo

1. Scripts auto-detect installer root when `agent-skills/` sits beside `Windows_Software_Installation/` (no extra config). Optional: `AIPC_DEVKIT_INSTALL_ROOT` for custom paths.
2. Add a short **Agent skills** section to the installer `README.md` linking to `agent-skills/README.md` (customer guide). Point contributors to `agent-skills/docs/implementation-status.md`.
3. Track HW runs in `agent-skills/tests/integration/MANUAL-HW-LAB.md`.
