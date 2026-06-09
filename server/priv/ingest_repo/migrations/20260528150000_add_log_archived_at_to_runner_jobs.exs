defmodule Tuist.IngestRepo.Migrations.AddLogArchivedAtToRunnerJobs do
  use Ecto.Migration

  # Marks when the job's gzipped log archive landed in S3. The per-line
  # logs in `runner_job_logs` are the live/searchable source of truth;
  # once a job finishes, `ArchiveLogsWorker` gzips the full stream and
  # uploads it so the "Download logs" endpoint can hand back a
  # presigned URL instead of re-streaming ClickHouse. `NULL` until the
  # archive lands; the download falls back to the chunked ClickHouse
  # stream in that window.
  #
  # The S3 key itself is derived by convention from
  # `(account_id, workflow_job_id)` — see
  # `Tuist.Runners.Workers.ArchiveLogsWorker.archive_key/2` — so it
  # doesn't need its own column. The timestamp doubles as the prune
  # cursor: the daily cleanup deletes archives whose
  # `log_archived_at < now() - 90d`.
  def up do
    execute("""
    ALTER TABLE runner_jobs
      ADD COLUMN IF NOT EXISTS log_archived_at Nullable(DateTime64(6, 'UTC')) DEFAULT NULL
    """)
  end

  def down do
    execute("ALTER TABLE runner_jobs DROP COLUMN IF EXISTS log_archived_at")
  end
end
