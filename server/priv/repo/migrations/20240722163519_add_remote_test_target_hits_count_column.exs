defmodule Tuist.Repo.Migrations.AddRemoteTestTargetHitsCountColumn do
  use Ecto.Migration

  def change do
    alter table(:command_events) do
      add(:remote_test_target_hits_count, :integer, required: true, default: 0)
    end

    create index("command_events", :remote_test_target_hits_count)
  end
end
