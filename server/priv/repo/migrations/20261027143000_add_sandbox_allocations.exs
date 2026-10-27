defmodule Tuist.Repo.Migrations.AddSandboxAllocations do
  use Ecto.Migration

  def change do
    alter table(:sandbox_nodes) do
      add :allocation_observed_at, :utc_datetime_usec
      add :allocation_memory_bytes, :bigint
      add :allocation_free_bytes, :bigint
      add :allocation_reclaim, :boolean, null: false, default: true
    end
  end
end
