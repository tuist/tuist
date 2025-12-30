defmodule Tuist.Repo.Migrations.AddCustomS3StorageToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :s3_bucket_name, :string
      add :s3_access_key_id, :binary
      add :s3_secret_access_key, :binary
      add :s3_region, :string
      add :s3_endpoint, :string
    end
  end
end
