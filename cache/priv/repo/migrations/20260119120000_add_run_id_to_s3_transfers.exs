defmodule Cache.Repo.Migrations.AddRunIdToS3Transfers do
  use Ecto.Migration

  def change do
    alter table(:s3_transfers) do
      add :run_id, :string
    end
  end
end
