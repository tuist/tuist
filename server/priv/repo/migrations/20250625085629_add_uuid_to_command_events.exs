defmodule Tuist.Repo.Migrations.AddUuidToCommandEvents do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
          CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    """

    # This is non-blocking and safe above PostgreSQL 11.
    alter table(:command_events) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :uuid, :uuid, default: fragment("uuid_generate_v4()"), null: false
    end

    # Concurrent index creation is not supported by Timescale hypertables.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:command_events, [:uuid])
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    drop index(:command_events, [:uuid])

    alter table(:command_events) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :uuid
    end
  end
end
