defmodule Atlas.Repo.Migrations.SeedMcpOauthScope do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO oauth_scopes (id, name, label, public, inserted_at, updated_at)
    VALUES (
      'db412c81-2af4-45b6-9805-2dcfd3898615',
      'mcp',
      'Atlas MCP access',
      true,
      current_timestamp,
      current_timestamp
    )
    ON CONFLICT (name) DO UPDATE SET
      label = EXCLUDED.label,
      public = true,
      updated_at = current_timestamp
    """)
  end

  def down do
    execute("DELETE FROM oauth_scopes WHERE name = 'mcp'")
  end
end
