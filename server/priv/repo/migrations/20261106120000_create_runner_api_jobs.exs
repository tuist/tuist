defmodule Tuist.Repo.Migrations.CreateRunnerApiJobs do
  use Ecto.Migration

  def change do
    # A separate range keeps API-created jobs out of the GitHub, Buildkite,
    # GitLab and Bitrise keyspaces.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "CREATE SEQUENCE runner_api_job_ids START WITH 4000000000000000",
      "DROP SEQUENCE runner_api_job_ids"
    )

    create table(:runner_api_jobs, primary_key: false) do
      add :workflow_job_id, :bigint,
        primary_key: true,
        default: fragment("nextval('runner_api_job_ids')")

      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :idempotency_key, :string
      add :name, :string, null: false
      add :repository, :string, null: false
      add :repository_url, :string, null: false
      add :ref, :string, null: false, default: ""
      add :commit_sha, :string, null: false
      add :payload, :binary
      add :cancel_requested_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_api_jobs, [:account_id, :idempotency_key])
  end
end
