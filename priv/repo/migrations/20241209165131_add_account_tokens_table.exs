defmodule Tuist.Repo.Migrations.AddAccountTokensTable do
  use Ecto.Migration

  def change do
    create table(:account_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :encrypted_token_hash, :string, null: false
      add :scopes, {:array, :integer}, null: false
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:account_tokens, [:account_id, :encrypted_token_hash])
  end
end
