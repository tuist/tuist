defmodule Tuist.Repo.Migrations.AddMcpOauthScope do
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO oauth_scopes (id, name, label, public, inserted_at, updated_at)
    VALUES (gen_random_uuid(), 'mcp', 'MCP read-only access', true, NOW(), NOW())
    ON CONFLICT (name) DO NOTHING
    """
  end

  def down do
    execute """
    DELETE FROM oauth_scopes WHERE name = 'mcp'
    """
  end
end
