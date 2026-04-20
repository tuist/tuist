defmodule Tuist.Repo.Migrations.MigrateOktaToOauth2Fields do
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety
  use Ecto.Migration

  # Copies Okta credentials into the unified oauth2 fields. The old
  # okta_client_id and okta_encrypted_client_secret columns are kept
  # intentionally so we can revert the code without losing data. A
  # follow-up PR will drop them once we're confident everything works.

  def up do
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
  end

  def down do
    execute """
    UPDATE organizations
    SET okta_client_id = oauth2_client_id,
        okta_encrypted_client_secret = oauth2_encrypted_client_secret
    WHERE sso_provider = 1
    """
  end
end
