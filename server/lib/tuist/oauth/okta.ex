defmodule Tuist.OAuth.Okta do
  @moduledoc """
  Okta OAuth configuration handler for SSO OAuth integration.
  """

  alias Tuist.Accounts.Organization
  alias Tuist.Environment

  def config_for_organization(%Organization{sso_provider: :okta, sso_organization_id: sso_organization_id} = organization) do
    {:ok,
     %{
       domain: sso_organization_id,
       client_id: Environment.okta_client_id_for_organization_id(organization.id),
       client_secret: Environment.okta_client_secret_for_organization_id(organization.id),
       authorize_url: "/oauth2/default/v1/authorize",
       token_url: "/oauth2/default/v1/token",
       user_info_url: "/oauth2/default/v1/userinfo"
     }}
  end

  def config_for_organization(_organization) do
    {:error, :okta_not_configured}
  end
end
