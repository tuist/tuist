defmodule Tuist.Repo.Migrations.MigrateOktaToOauth2Fields do
  use Ecto.Migration

  def up do
    # Copy Okta credentials into the unified oauth2 fields
    # and populate the endpoint URLs from the Okta domain
    execute """
    UPDATE organizations
    SET oauth2_client_id = okta_client_id,
        oauth2_encrypted_client_secret = okta_encrypted_client_secret,
        oauth2_authorize_url = 'https://' || sso_organization_id || '/oauth2/v1/authorize',
        oauth2_token_url = 'https://' || sso_organization_id || '/oauth2/v1/token',
        oauth2_user_info_url = 'https://' || sso_organization_id || '/oauth2/v1/userinfo'
    WHERE sso_provider = 1
      AND okta_client_id IS NOT NULL
    """

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
