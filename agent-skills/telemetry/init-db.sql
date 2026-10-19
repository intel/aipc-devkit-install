CREATE TABLE IF NOT EXISTS skill_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL,
  skill_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_skill_events_run ON skill_events(run_id);
CREATE INDEX IF NOT EXISTS idx_skill_events_skill ON skill_events(skill_id);
CREATE INDEX IF NOT EXISTS idx_skill_events_type ON skill_events(event_type);
