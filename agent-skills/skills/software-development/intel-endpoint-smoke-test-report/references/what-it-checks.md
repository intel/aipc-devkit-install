# What the smoke test checks

`endpoint-smoke-test.ps1` calls `GET {base}/models`, picks an advertised id that matches the requested catalog model, then sends one chat completion.

| Choice | When |
|---|---|
| Default model | Quick check after `-Profile verify` |
| `-Model` set to the agent id from `GET /v3/models` | After `-Profile agent` on recommended hardware |
| `-BaseUrl` | Endpoint is not `http://localhost:8000/v3` |
| `-IncludeToolTest` | Also exercise a tool-call check |

If no advertised id matches, the check fails. The catalog path (`OpenVINO/...-int4-ov`) is not the id OVMS lists on `GET /v3/models`.
