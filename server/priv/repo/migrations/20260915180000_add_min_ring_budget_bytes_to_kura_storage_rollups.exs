defmodule Tuist.Repo.Migrations.AddMinRingBudgetBytesToKuraStorageRollups do
  use Ecto.Migration

  def change do
    alter table(:kura_storage_rollups) do
      add :min_ring_budget_bytes, :bigint
    end
  end
end
