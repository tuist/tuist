defmodule Tuist.Repo.Migrations.CreateRunnerBuildkiteInstallations do
  use Ecto.Migration

  def change do
    create table(:runner_buildkite_installations) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :organization_slug, :string, null: false
      add :cluster_name, :string, null: false, default: ""
      # Identifies this controller to Buildkite's Stacks API. Scoped per
      # installation rather than global so two installations pointing at the
      # same cluster (a migration, a staging mirror) reserve independently.
      add :stack_key, :string, null: false
      add :agent_token, :binary, null: false
      add :enabled, :boolean, null: false, default: true
      add :last_polled_at, :timestamptz
      add :last_error, :text
      add :last_error_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_buildkite_installations, [:account_id])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_buildkite_installations, [:stack_key])
  end
end
