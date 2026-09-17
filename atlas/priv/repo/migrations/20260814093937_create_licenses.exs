defmodule Atlas.Repo.Migrations.CreateLicenses do
  use Ecto.Migration

  def change do
    create table(:licenses, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :restrict), null: false

      add :key, :binary, null: false
      add :key_hash, :binary, null: false
      add :signing_key, :binary, null: false
      add :expires_on, :date, null: false

      timestamps()
    end

    create unique_index(:licenses, [:key_hash])
    create index(:licenses, [:account_id])
    create index(:licenses, [:expires_on])
  end
end
