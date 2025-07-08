defmodule Tuist.Repo.Migrations.AddCommandEventsHypertable do
  use Ecto.Migration

  def up do
    if Tuist.Repo.timescale_available?() do
      execute("ALTER TABLE command_events DROP CONSTRAINT command_events_pkey;")
      execute("ALTER TABLE command_events ADD PRIMARY KEY (id, created_at);")
      execute("SELECT create_hypertable('command_events', 'created_at', migrate_data => true);")
      create index(:command_events, [:name, :project_id, :created_at])
    end
  end

  def down do
    # We can't provide down for create_hypertable as that would require dropping the whole command_events table: https://docs.timescale.com/use-timescale/latest/hypertables/drop/
    # The rest for down would be as following, but can't be run with the hypertable in place:
    # execute("ALTER TABLE command_events DROP CONSTRAINT command_events_pkey;")
    # execute("ALTER TABLE command_events ADD PRIMARY KEY (id);")
    # drop index(:command_events, [:name, :project_id, :created_at])
  end
end
