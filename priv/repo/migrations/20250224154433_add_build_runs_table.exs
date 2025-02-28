defmodule Tuist.Repo.Migrations.AddBuildRunssTable do
  use Ecto.Migration

  def up do
    create table(:build_runs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :duration, :integer, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :macos_version, :string
      add :xcode_version, :string
      add :is_ci, :boolean, null: false
      add :model_identifier, :string
      add :scheme, :string

      add :inserted_at, :timestamptz, primary_key: true, null: false
    end

    flush()

    # excellent_migrations:safety-assured-for-next-line operation_timescale_available?
    if Tuist.Repo.timescale_available?() do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute("SELECT create_hypertable('build_runs', 'inserted_at');")
    end
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:build_runs)
  end
end
