defmodule Tuist.Repo.Migrations.DropOktaColumnsFromOrganizations do
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety
  use Ecto.Migration

  # The data was already copied to oauth2_client_id and
  # oauth2_encrypted_client_secret in migration 20260324103000.
  # These columns have been unused since the custom OAuth2 SSO PR landed.

  def up do
    alter table(:organizations) do
      remove :okta_client_id
      remove :okta_encrypted_client_secret
    end
  end

  def down do
    alter table(:organizations) do
      add :okta_client_id, :string
      add :okta_encrypted_client_secret, :binary
    end

    execute """
    UPDATE organizations
    SET okta_client_id = oauth2_client_id,
        okta_encrypted_client_secret = oauth2_encrypted_client_secret
    WHERE sso_provider = 1
    """
  end
end
