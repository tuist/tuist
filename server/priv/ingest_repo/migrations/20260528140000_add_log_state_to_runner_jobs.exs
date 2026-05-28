defmodule Tuist.IngestRepo.Migrations.AddLogStateToRunnerJobs do
  use Ecto.Migration

  # Tracks the lifecycle of a job's captured logs (stored line-by-line
  # in `runner_job_logs`) on the job row itself, so the detail page
  # knows whether to live-tail (`streaming`) or read a finished stream
  # (`complete`/`partial`) without a separate lookup.
  #
  #   ''         — no logs captured (default; pre-feature rows, or jobs
  #                that never streamed)
  #   streaming  — the shipper is actively appending lines
  #   complete   — the stream closed cleanly
  #   partial    — the runner/stream died before a clean close
  #
  # `log_line_count` is denormalized at finalization (one extra
  # state-transition INSERT) so the jobs list can show a logs
  # indicator without counting `runner_job_logs` per row. It stays 0
  # while streaming; the live view counts via the stream instead.
  def up do
    execute("""
    ALTER TABLE runner_jobs
      ADD COLUMN IF NOT EXISTS log_state LowCardinality(String) DEFAULT '',
      ADD COLUMN IF NOT EXISTS log_line_count UInt32 DEFAULT 0
    """)
  end

  def down do
    execute("ALTER TABLE runner_jobs DROP COLUMN IF EXISTS log_state")
    execute("ALTER TABLE runner_jobs DROP COLUMN IF EXISTS log_line_count")
  end
end
