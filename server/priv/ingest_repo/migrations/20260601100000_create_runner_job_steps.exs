defmodule Tuist.IngestRepo.Migrations.CreateRunnerJobSteps do
  use Ecto.Migration

  # One row per workflow_job step, captured from the
  # `workflow_job.completed` webhook (GitHub only populates the steps
  # array at completion). Replaces the JSON `steps` column previously
  # carried on `runner_jobs` so step-level analytics — failure rate per
  # step name, p95 of `Build` duration, slowest steps in a workflow —
  # become first-class ClickHouse queries instead of JSON parses in
  # application code.
  #
  # `account_id` is denormalized so dashboards can scope by tenant
  # without joining `runner_jobs`. `started_at` / `completed_at` are
  # nullable for skipped or never-run steps.
  #
  # ReplacingMergeTree on `(workflow_job_id, number)` collapses
  # webhook retries (GitHub redelivers `workflow_job.completed` on its
  # own budget) into one row per step, with `inserted_at` as the
  # version column.
  def up do
    create table(:runner_job_steps,
             primary_key: false,
             engine: "ReplacingMergeTree(inserted_at)",
             options: "PARTITION BY toYYYYMM(inserted_at) ORDER BY (workflow_job_id, number)"
           ) do
      add :workflow_job_id, :Int64, null: false
      add :account_id, :Int64, null: false

      # GitHub's per-job step sequence (1-based, contiguous within a
      # workflow_job). Doubles as the natural display order and the
      # RMT dedup key.
      add :number, :UInt16, null: false

      add :name, :string, null: false, default: ""
      add :status, :"LowCardinality(String)", null: false, default: ""
      add :conclusion, :"LowCardinality(String)", null: false, default: ""

      add :started_at, :"Nullable(DateTime64(6, 'UTC'))", default: nil
      add :completed_at, :"Nullable(DateTime64(6, 'UTC'))", default: nil

      add :inserted_at, :"DateTime64(6, 'UTC')", null: false, default: fragment("now64(6)")
    end
  end

  def down do
    drop table(:runner_job_steps)
  end
end
