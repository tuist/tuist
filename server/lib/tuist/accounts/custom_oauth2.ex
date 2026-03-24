defmodule Tuist.Accounts.CustomOAuth2 do
  @moduledoc """
  OAuth2 configuration handler for SSO integrations.

  Handles both Okta (as a preset with well-known endpoint paths) and
  fully custom OAuth2 providers.
  """

  alias Tuist.Accounts.Organization

  @okta_authorize_path "/oauth2/v1/authorize"
  @okta_token_path "/oauth2/v1/token"
  @okta_userinfo_path "/oauth2/v1/userinfo"

  def config_for_organization(%Organization{
        sso_provider: provider,
        sso_organization_id: sso_organization_id,
        oauth2_client_id: client_id,
        oauth2_encrypted_client_secret: client_secret,
        oauth2_authorize_url: authorize_url,
        oauth2_token_url: token_url,
        oauth2_user_info_url: user_info_url
      })
      when provider in [:okta, :oauth2] and not is_nil(sso_organization_id) and not is_nil(client_id) and
             not is_nil(client_secret) and not is_nil(authorize_url) and not is_nil(token_url) and
             not is_nil(user_info_url) do
    site = if provider == :okta, do: "https://#{sso_organization_id}", else: sso_organization_id

    {:ok,
     %{
       site: site,
       provider_organization_id: sso_organization_id,
       client_id: client_id,
       client_secret: client_secret,
       authorize_url: authorize_url,
       token_url: token_url,
       user_info_url: user_info_url
     }}
  end

  def config_for_organization(_organization) do
    {:error, :oauth2_not_configured}
  end

  def okta_authorize_url(domain), do: "https://#{domain}#{@okta_authorize_path}"
  def okta_token_url(domain), do: "https://#{domain}#{@okta_token_path}"
  def okta_userinfo_url(domain), do: "https://#{domain}#{@okta_userinfo_path}"
end
