defmodule Tuist.Repo.Migrations.AddHeldReasonToKuraRolloutServers do
  use Ecto.Migration

  def change do
    alter table(:kura_rollout_servers) do
      add :held_reason, :string
    end
  end
end
