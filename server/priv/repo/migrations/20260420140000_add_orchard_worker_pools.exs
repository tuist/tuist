defmodule Tuist.Repo.Migrations.AddOrchardWorkerPools do
  use Ecto.Migration

  def change do
    create table(:orchard_worker_pools, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :enabled, :boolean, default: true, null: false
      add :desired_size, :integer, default: 0, null: false
      add :scaleway_zone, :string, null: false
      add :scaleway_server_type, :string, null: false
      add :scaleway_os, :string, null: false
      add :last_reconciled_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    create unique_index(:orchard_worker_pools, [:account_id, :name])
    create index(:orchard_worker_pools, [:enabled])

    execute("DELETE FROM orchard_workers", "")

    alter table(:orchard_workers) do
      add :pool_id, references(:orchard_worker_pools, type: :uuid, on_delete: :delete_all),
        null: false
    end

    create index(:orchard_workers, [:pool_id])
  end
end
