defmodule Tuist.Repo.Migrations.CreateClickhouseInserts do
  @moduledoc """
  ClickHouse inserts whose rows a later write waits for on every replica
  (`Tuist.ClickHouse.Inserts`): one row per table and unit of rows (`key`),
  replaced when the unit is written again. Rows only matter while
  replication can lag and are pruned after a day.
  """
  use Ecto.Migration

  def change do
    create table(:clickhouse_inserts, primary_key: false) do
      add :clickhouse_table, :string, null: false, primary_key: true
      add :key, :string, null: false, primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      # The `inserted_at` the insert's rows share in ClickHouse.
      add :rows_inserted_at, :timestamptz, null: false
      add :synced_at, :timestamptz
      add :inserted_at, :timestamptz, null: false
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:clickhouse_inserts, [:inserted_at])
  end
end
