defmodule Tuist.Repo.Migrations.CreateScimTokens do
  use Ecto.Migration

  def change do
    create table(:scim_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :encrypted_token_hash, :string, null: false
      add :name, :string
      add :last_used_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    create index(:scim_tokens, [:organization_id])
  end
end
