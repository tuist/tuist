# Cache Action Items

- Keep inserts idempotent on the project/hash conflict key.
- Sort bulk rows by `{project_id, hash}` at the insert boundary for consistent lock acquisition across concurrent batches; `ON CONFLICT DO NOTHING` still waits on conflicting uncommitted inserts.
