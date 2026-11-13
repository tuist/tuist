defmodule Tuist.Repo.Migrations.CreateSandboxDiskSnapshotCopies do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Extra node copies of a disk snapshot, downloaded from its archive so a
  # popular project snapshot can be cloned on nodes other than the one that
  # saved it. A copy goes with its snapshot.
  def change do
    create table(:sandbox_disk_snapshot_copies, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :disk_snapshot_id,
          references(:sandbox_disk_snapshots, type: :uuid, on_delete: :delete_all), null: false

      add :node_name, :string, null: false
      add :state, :string, null: false, default: "copying"
      add :last_used_at, :timestamptz, null: false
      timestamps(type: :timestamptz)
    end

    create unique_index(:sandbox_disk_snapshot_copies, [:disk_snapshot_id, :node_name],
             concurrently: true
           )

    create index(:sandbox_disk_snapshot_copies, [:node_name], concurrently: true)
  end
end
