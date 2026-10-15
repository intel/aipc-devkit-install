# intel-ovms-agentic-setup blocked results

The commands are in `SKILL.md`. A blocked run can set `error.code` to one of:

| Code | Meaning |
|---|---|
| `DISK_INSUFFICIENT` | Not enough free disk for the pull |
| `PORT_CONFLICT` | Port 8000 is held. Retry only with `-ApproveStopOvms` after the user agrees to stop `ovms.exe` |
| `PULL_IN_PROGRESS` | A download is already running |
| `RETRY_PULL_REQUIRES_APPROVAL` | Resume or re-pull needs `-ApproveRetryPull` |
| `MODEL_ADVERTISED_MISMATCH` | The catalog id does not match `GET /v3/models` |

Default endpoint: `http://localhost:8000/v3`.
