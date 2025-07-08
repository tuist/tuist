defmodule Tuist.Repo.Migrations.DropClientIdForeignKeyInOauthTokens do
  use Ecto.Migration

  def up do
    drop constraint(:oauth_tokens, "oauth_tokens_client_id_fkey")
  end

  def down do
    alter table(:oauth_tokens) do
      # excellent_migrations:safety-assured-for-next-line column_reference_added
      modify :client_id, references(:oauth_clients, on_delete: :delete_all, type: :uuid)
    end
  end
end
