defmodule Tuist.Repo.Migrations.AddIndexToCommandEventsPreviewID do
  use Ecto.Migration

  def change do
    # TimescaleDB hypertables do not support concurrent index creation.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:command_events, [:preview_id], concurrently: false)
  end
end
