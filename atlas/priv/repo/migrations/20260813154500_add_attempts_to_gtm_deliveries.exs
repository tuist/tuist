defmodule Atlas.Repo.Migrations.AddAttemptsToGtmDeliveries do
  use Ecto.Migration

  def change do
    alter table(:gtm_deliveries) do
      add :attempts, :integer, null: false, default: 0
    end

    # The resume worker sweeps deliveries that never reached a terminal state,
    # so it queries by status and how long they have been sitting there.
    create index(:gtm_deliveries, [:status, :updated_at])
  end
end
