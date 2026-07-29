defmodule Tuist.IngestRepo.Migrations.RenameRepoToRepositoryOnRunnerJobs do
  use Ecto.Migration

  # Aligns the ClickHouse column with the rest of the codebase
  # (LiveView assigns, URL params, GitHub webhook payloads, OIDC
  # claims) which all spell the full handle as `repository`. The
  # `runner_sessions` Postgres table is renamed in the same patch.
  #
  # `ALTER TABLE … RENAME COLUMN` on ReplacingMergeTree is a
  # metadata-only operation in ClickHouse (>= 20.4) — no part
  # rewrite, no downtime, no cluster-wide stall. Safe to run
  # online.
  def up do
    execute("ALTER TABLE runner_jobs RENAME COLUMN repo TO repository")
  end

  def down do
    execute("ALTER TABLE runner_jobs RENAME COLUMN repository TO repo")
  end
end
