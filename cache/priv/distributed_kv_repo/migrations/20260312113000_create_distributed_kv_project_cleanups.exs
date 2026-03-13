defmodule Cache.DistributedKV.Repo.Migrations.CreateDistributedKvProjectCleanups do
  use Ecto.Migration

  def change do
    create table(:distributed_kv_project_cleanups, primary_key: false) do
      add :account_handle, :text, primary_key: true
      add :project_handle, :text, primary_key: true
      add :cleanup_started_at, :timestamptz, null: false
      add :lease_expires_at, :timestamptz, null: false
      add :updated_at, :timestamptz, null: false
    end

    create index(:distributed_kv_project_cleanups, [:lease_expires_at])
  end
end
