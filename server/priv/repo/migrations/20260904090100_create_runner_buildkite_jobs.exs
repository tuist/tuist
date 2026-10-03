defmodule Tuist.Repo.Migrations.CreateRunnerBuildkiteJobs do
  use Ecto.Migration

  # Buildkite identifies a job by UUID; every lifecycle, claim, session,
  # log, step and metric table in the runners subsystem is keyed on a
  # 64-bit `workflow_job_id`, and the ClickHouse side keys `runner_jobs`,
  # `runner_job_logs`, `runner_job_steps` and `runner_job_machine_metrics`
  # on `Int64` with a ReplacingMergeTree ORDER BY over it.
  #
  # Widening that key to a string would mean rewriting those ClickHouse
  # tables and every query and projection over them, for a provider that
  # carries none of the existing history. Instead each Buildkite job UUID
  # is assigned a surrogate 64-bit id here, once, and the rest of the
  # subsystem is untouched: Buildkite jobs flow through the same claim,
  # session and billing machinery as GitHub's.
  #
  # The surrogate must never collide with a real GitHub workflow_job id.
  # GitHub's are currently ~5e10 and grow with GitHub's global job
  # volume; this sequence starts at 1e15, roughly 20,000x above them, and
  # sits 9,000x below `Int64` max. Both halves of the keyspace have room
  # to grow for far longer than the partition needs to hold.
  @surrogate_floor 1_000_000_000_000_000

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("CREATE SEQUENCE runner_buildkite_job_ids START WITH #{@surrogate_floor}")

    create table(:runner_buildkite_jobs, primary_key: false) do
      add :job_uuid, :string, primary_key: true, null: false

      add :workflow_job_id, :bigint,
        null: false,
        default: fragment("nextval('runner_buildkite_job_ids')")

      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :organization_slug, :string, null: false
      add :pipeline_slug, :string, null: false, default: ""
      add :build_uuid, :string, null: false, default: ""
      add :build_number, :bigint, null: false, default: 0
      add :queue_key, :string, null: false, default: ""
      # When our Stacks-API reservation lapses and Buildkite returns the
      # job to `scheduled`. The poller uses it to avoid re-reserving a
      # job it already holds, and the recovery sweep to spot jobs whose
      # reservation outlived the Pod that claimed them.
      add :reserved_until, :timestamptz

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER SEQUENCE runner_buildkite_job_ids OWNED BY runner_buildkite_jobs.workflow_job_id"
    )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_buildkite_jobs, [:workflow_job_id])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_buildkite_jobs, [:account_id, :reserved_until])
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:runner_buildkite_jobs)
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP SEQUENCE IF EXISTS runner_buildkite_job_ids")
  end
end
