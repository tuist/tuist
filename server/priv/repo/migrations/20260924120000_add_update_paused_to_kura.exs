defmodule Tuist.Repo.Migrations.AddUpdatePausedToKura do
  use Ecto.Migration

  def change do
    alter table(:kura_servers) do
      add :update_paused, :map
    end

    alter table(:kura_deployments) do
      add :blocked_reason, :text
    end
  end
end
