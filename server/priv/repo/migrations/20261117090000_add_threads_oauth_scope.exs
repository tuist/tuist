defmodule Tuist.Repo.Migrations.AddThreadsOauthScope do
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety
  use Ecto.Migration

  # Public so dynamically registered clients such as Tuist Guild can request it.
  def up do
    execute """
    INSERT INTO oauth_scopes (id, name, label, public, inserted_at, updated_at)
    VALUES (gen_random_uuid(), 'threads', 'Private AI threads', true, NOW(), NOW())
    ON CONFLICT (name) DO NOTHING
    """
  end

  def down do
    execute """
    DELETE FROM oauth_scopes WHERE name = 'threads'
    """
  end
end
