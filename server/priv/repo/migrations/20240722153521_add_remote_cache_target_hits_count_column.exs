defmodule Tuist.Repo.Migrations.AddRemoteCacheTargetHitsCountColumn do
  use Ecto.Migration

  def change do
    alter table(:command_events) do
      add(:remote_cache_target_hits_count, :integer, required: true, default: 0)
    end

    create index("command_events", :remote_cache_target_hits_count)
  end
end
