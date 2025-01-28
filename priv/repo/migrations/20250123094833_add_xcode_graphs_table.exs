defmodule Tuist.Repo.Migrations.AddXcodeGraphsTable do
  use Ecto.Migration

  def change do
    create table(:xcode_graphs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :name, :string, null: false

      # We can't add this as a reference as command_events is a hypertable
      add :command_event_id, :id, null: false

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:xcode_graphs, [:command_event_id])
  end
end
