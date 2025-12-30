defmodule Tuist.OAuth.Okta do
  @moduledoc """
  Okta OAuth configuration handler for SSO OAuth integration.
  """

  alias Tuist.Accounts.Organization

  def config_for_organization(%Organization{
        sso_provider: :okta,
        sso_organization_id: sso_organization_id,
        okta_client_id: okta_client_id,
        okta_encrypted_client_secret: okta_encrypted_client_secret
      })
      when not is_nil(okta_client_id) and not is_nil(okta_encrypted_client_secret) and not is_nil(sso_organization_id) do
    {:ok,
     %{
       domain: sso_organization_id,
       client_id: okta_client_id,
       client_secret: okta_encrypted_client_secret,
       authorize_url: "/oauth2/v1/authorize",
       token_url: "/oauth2/v1/token",
       user_info_url: "/oauth2/v1/userinfo"
     }}
  end

  def config_for_organization(_organization) do
    {:error, :okta_not_configured}
  end
end
