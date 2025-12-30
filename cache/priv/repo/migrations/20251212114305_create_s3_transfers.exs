defmodule Cache.Repo.Migrations.CreateS3Transfers do
  use Ecto.Migration

  def change do
    create table(:s3_transfers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :type, :string, null: false
      add :account_handle, :string, null: false
      add :project_handle, :string, null: false
      add :artifact_id, :string, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    create unique_index(:s3_transfers, [:type, :account_handle, :project_handle, :artifact_id])
    create index(:s3_transfers, [:type])
  end
end
