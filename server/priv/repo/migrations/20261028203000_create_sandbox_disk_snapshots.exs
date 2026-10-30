defmodule Tuist.Repo.Migrations.CreateSandboxDiskSnapshots do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:sandbox_disk_snapshots, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :amp_snapshot_id, :string, null: false
      add :source_sandbox_id, references(:sandboxes, type: :uuid, on_delete: :nilify_all)
      add :node_name, :string, null: false
      add :template, :string, null: false
      add :template_tag, :string
      add :workspace_gb, :integer, null: false
      add :state, :string, null: false, default: "saving"
      add :last_used_at, :timestamptz, null: false
      timestamps(type: :timestamptz)
    end

    create index(:sandbox_disk_snapshots, [:account_id, :amp_snapshot_id], concurrently: true)
    create index(:sandbox_disk_snapshots, [:node_name], concurrently: true)
    create index(:sandbox_disk_snapshots, [:source_sandbox_id], concurrently: true)
  end
end
