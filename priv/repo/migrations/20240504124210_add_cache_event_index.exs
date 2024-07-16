defmodule Tuist.Repo.Migrations.AddCacheEventIndex do
  use Ecto.Migration

  def change do
    create index(:cache_events, [:hash, :event_type])
  end
end
