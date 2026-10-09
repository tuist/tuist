# Database Performance Experiments

This directory contains reproducible local experiments and the evidence behind database optimizations.

- Production inspection uses Atlas/Grafana read-only tools with bounded statements. Never run writes, index builds, extensions, resets, or maintenance against production from these experiments.
- `closed_runner_session_index.sql` seeds synthetic runner sessions in a new schema inside a transaction and rolls everything back. It measures missing/existing closed-pod reads and the index-maintenance and WAL cost of open/close batches. It does not measure commit latency, network latency, PgBouncer, or pool queueing.
- Run local scripts through the Unix socket (`psql -X -h /tmp -d postgres`), not an environment-provided production URL. Use a disposable database with no application tables or replication; both PostgreSQL scripts check this before writing. Never copy authentication codes, customer rows, or query parameters into benchmark fixtures.
- Compare identical inputs, alternate baseline/candidate order, use several repetitions, and record unsuccessful candidates too. Do not label local speedups as measured production improvements.
- `check_closed_session_index.exs` runs the actual concurrent Ecto migration and rollback in a disposable local schema outside a transaction. The SQL benchmark's transactional index build is not that check. Use random names for cross-process isolation: BEAM's `System.unique_integer/1` is unique only within one VM.
- `repo_metrics.exs` runs the two focused monitoring test files with real compiled dependencies and local ClickHouse `SELECT`s, without booting the whole server. Keep its compile-time dynamic-repo default aligned with `config/test.exs`; explicit per-test dynamic repos still target local named pools. Clean temporary beams on bootstrap exceptions as well as after the suite. This is isolated validation, not the full application's `mix test` lifecycle.
- Commit reproducible methods and synthetic local results, not production database roles, datasource identifiers, customer-table volumes, or review conversations.
