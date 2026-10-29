defmodule Tuist.Repo.Migrations.CreateRunnerBitriseConnections do
  use Ecto.Migration

  def change do
    create table(:runner_bitrise_connections) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :workspace_slug, :string, null: false
      add :api_token, :binary, null: false
      add :enabled, :boolean, null: false, default: true
      add :last_polled_at, :timestamptz
      add :last_error, :string
      add :last_error_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_bitrise_connections, [:account_id])

    create table(:runner_bitrise_pools) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      add :connection_id, references(:runner_bitrise_connections, on_delete: :delete_all),
        null: false

      add :stack_identifier, :string, null: false
      add :profile_label, :string, null: false
      add :intro_secret, :binary, null: false
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_bitrise_pools, [:connection_id, :stack_identifier])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_bitrise_pools, [:account_id])

    # A separate range keeps Bitrise builds out of the GitHub, Buildkite and
    # GitLab keyspaces.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "CREATE SEQUENCE runner_bitrise_build_ids START WITH 3000000000000000",
      "DROP SEQUENCE runner_bitrise_build_ids"
    )

    create table(:runner_bitrise_builds, primary_key: false) do
      add :workflow_job_id, :bigint,
        primary_key: true,
        default: fragment("nextval('runner_bitrise_build_ids')")

      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :connection_id, references(:runner_bitrise_connections, on_delete: :nilify_all)
      add :build_slug, :string, null: false
      add :app_slug, :string, null: false
      add :stack_identifier, :string, null: false
      add :build_number, :bigint, null: false, default: 0
      add :runner_name, :string
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_bitrise_builds, [:build_slug])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_bitrise_builds, [:account_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_bitrise_builds, [:connection_id])
  end
end
