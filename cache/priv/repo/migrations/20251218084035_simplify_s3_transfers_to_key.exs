defmodule Cache.Repo.Migrations.SimplifyS3TransfersToKey do
  use Ecto.Migration

  def up do
    # s3_transfers is a transient queue for pending uploads/downloads.
    # Any pending transfers at migration time will be re-discovered and
    # re-enqueued by the normal cache flow, so we can safely truncate.
    execute "DELETE FROM s3_transfers"

    drop index(:s3_transfers, [:type, :account_handle, :project_handle, :artifact_id])

    alter table(:s3_transfers) do
      remove :artifact_id
      add :artifact_type, :string, null: false
      add :key, :string, null: false
    end

    create unique_index(:s3_transfers, [:type, :key])
  end

  def down do
    drop index(:s3_transfers, [:type, :key])

    alter table(:s3_transfers) do
      remove :key
      remove :artifact_type
      add :artifact_id, :string
    end

    create unique_index(:s3_transfers, [:type, :account_handle, :project_handle, :artifact_id])
  end
end
