defmodule Tuist.Repo.Migrations.AddKuraRolloutServerOutboxExtremes do
  use Ecto.Migration

  def change do
    alter table(:kura_rollout_servers) do
      add :outbox_peak, :bigint
      add :outbox_low_water, :bigint
    end
  end
end
