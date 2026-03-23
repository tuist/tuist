defmodule Tuist.OAuth.CustomOAuth2 do
  @moduledoc """
  Custom OAuth2 configuration handler for customer-managed SSO integrations.
  """

  alias Tuist.Accounts.Organization

  def config_for_organization(%Organization{
        sso_provider: :custom_oauth2,
        sso_organization_id: site,
        custom_oauth2_client_id: client_id,
        custom_oauth2_encrypted_client_secret: client_secret,
        custom_oauth2_authorize_url: authorize_url,
        custom_oauth2_token_url: token_url,
        custom_oauth2_user_info_url: user_info_url
      })
      when not is_nil(site) and not is_nil(client_id) and not is_nil(client_secret) and not is_nil(authorize_url) and
             not is_nil(token_url) and not is_nil(user_info_url) do
    {:ok,
     %{
       site: normalize_site(site),
       provider_organization_id: normalize_site(site),
       client_id: client_id,
       client_secret: client_secret,
       authorize_url: authorize_url,
       token_url: token_url,
       user_info_url: user_info_url
     }}
  end

  def config_for_organization(_organization) do
    {:error, :custom_oauth2_not_configured}
  end

  def normalize_site(site) when is_binary(site) do
    site
    |> String.trim()
    |> String.trim_trailing("/")
  end
end
