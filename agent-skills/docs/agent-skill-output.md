# Agent skill JSON — user vs diagnostic output

Skill invokers print one JSON object on stdout (`schema_id`: `skill-result-2026-08`). **Hermes and other agents should speak to users using the user channel only.**

## User channel (read aloud / show in UI)

| Field | Purpose |
|-------|---------|
| `user_message` | The only sentence to say by default |
| `blocked_reason` | Why the run stopped, when `functional_status` is `blocked` or `fail`, and only when the user asks what happened |
| `agent_inference_ready` | **true** only when the large agent model is on `GET /v3/models` |
| `smoke_inference_ready` | **true** when the small verify model is advertised |
| `readiness_tier` | `none` \| `smoke` \| `agent` |

Do **not** quote milestone ids (D1, D9, M1), check ids (O2, V4), or internal regex paths from these fields.

**Agentic inference checks:** `A1-agentic-inference` (OVMS setup skill), `V6-agentic-inference` (verify). If either **fails**, say smoke-only or agent-not-loaded — not “ready for agentic chat.”

## Machine / lab channel

| Field | Purpose |
|-------|---------|
| `functional_status`, `exit_code`, `next_skill` | Automation. Follow `next_skill` only when the user's request includes that step. Do not say the skill id. |
| `summary`, `next_steps`, `warnings` | Not spoken by default. `next_steps` stays empty so it is not read aloud. |
| `install_job`, `install_poll` | Elevated install job status; **`install_poll`** tells agents how to poll (**same skill**, `-WaitInstallJob` + job id). Not for user copy-paste. |
| `checks[]` | Contract tests, golden reports (`id`, `status`, technical `message`). Include only when the user asks for verbose output or why it failed. |
| `diagnostics` | `error`, `agent_next_steps`, `catalog_model_id`, `advertised_match_pattern`, `milestone_refs`, `notes`. `agent_next_steps` is how the agent continues. Include it only when the user asks for verbose output. |
| `logs[]` | Script paths, PIDs, junction details |

Agents troubleshooting deep issues may read `diagnostics.error.code` and `checks[]` only when the user asks for technical detail.

## Registry

User-facing text for checks and skills is driven by [`schemas/check-registry.json`](../schemas/check-registry.json). Engineers edit the registry or invoker diagnostic messages; avoid embedding D1/D9 in PowerShell user strings.

## Hermes provider handoff

Use `local_provider_handoff.hermes_cli_steps` for switch-to-local flows. Prefer `model` (advertised id) over `catalog_model_id` in `diagnostics`.
