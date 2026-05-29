defmodule Tuist.IngestRepo.Migrations.AddLogArchiveKeyToRunnerJobs do
  use Ecto.Migration

  # S3 object key of the job's compressed log archive. The per-line
  # logs in `runner_job_logs` are the live/searchable source of truth;
  # once a job finishes, `ArchiveLogsWorker` gzips the full stream and
  # uploads it to S3 so the "Download logs" endpoint can hand back a
  # presigned URL instead of re-streaming ClickHouse. Empty until the
  # archive lands (pre-feature rows, in-flight jobs, or jobs whose
  # archive hasn't been built yet) — the download falls back to the
  # chunked ClickHouse stream in that window.
  def up do
    execute("""
    ALTER TABLE runner_jobs
      ADD COLUMN IF NOT EXISTS log_archive_key String DEFAULT ''
    """)
  end

  def down do
    execute("ALTER TABLE runner_jobs DROP COLUMN IF EXISTS log_archive_key")
  end
end
