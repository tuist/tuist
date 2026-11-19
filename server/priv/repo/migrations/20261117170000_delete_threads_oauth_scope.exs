defmodule Tuist.Repo.Migrations.DeleteThreadsOauthScope do
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety
  use Ecto.Migration

  # Tuist Guild became a first-party client, so nothing requests `threads` anymore.
  # Grants that already hold it still refresh, with the default user scopes
  # (`Tuist.OAuth.TokenGenerator`).
  def up do
    execute """
    DELETE FROM oauth_scopes WHERE name = 'threads'
    """
  end

  def down do
    execute """
    INSERT INTO oauth_scopes (id, name, label, public, inserted_at, updated_at)
    VALUES (gen_random_uuid(), 'threads', 'Private AI threads', true, NOW(), NOW())
    ON CONFLICT (name) DO NOTHING
    """
  end
end
