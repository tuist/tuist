defmodule Tuist.Repo.Migrations.CreateRunnerGitlabConnections do
  use Ecto.Migration

  def change do
    create table(:runner_gitlab_connections) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :url, :string, null: false
      add :profile_label, :string, null: false
      add :runner_token, :binary, null: false
      add :enabled, :boolean, null: false, default: true
      add :last_polled_at, :timestamptz
      add :last_error, :string
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_gitlab_connections, [:account_id, :profile_label])

    # A separate range keeps GitLab's numeric IDs out of the GitHub and
    # Buildkite keyspaces, including IDs from independent GitLab instances.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "CREATE SEQUENCE runner_gitlab_job_ids START WITH 2000000000000000",
      "DROP SEQUENCE runner_gitlab_job_ids"
    )

    create table(:runner_gitlab_jobs, primary_key: false) do
      add :workflow_job_id, :bigint,
        primary_key: true,
        default: fragment("nextval('runner_gitlab_job_ids')")

      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :connection_id, references(:runner_gitlab_connections, on_delete: :nilify_all)
      add :url, :string, null: false
      add :job_id, :bigint, null: false
      add :project_path, :string, null: false
      add :pipeline_id, :bigint, null: false
      add :payload, :binary
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_gitlab_jobs, [:url, :job_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_gitlab_jobs, [:connection_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_gitlab_jobs, [:account_id])
  end
end
