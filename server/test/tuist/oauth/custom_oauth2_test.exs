defmodule Tuist.OAuth.CustomOAuth2Test do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Accounts.Organization
  alias Tuist.OAuth.CustomOAuth2

  describe "config_for_organization/1" do
    test "returns config for custom OAuth2 organization with database fields" do
      organization = %Organization{
        sso_provider: :custom_oauth2,
        sso_organization_id: "https://auth.example.com/",
        custom_oauth2_client_id: "test_client_id",
        custom_oauth2_encrypted_client_secret: "test_client_secret",
        custom_oauth2_authorize_url: "/oauth2/authorize",
        custom_oauth2_token_url: "/oauth2/token",
        custom_oauth2_user_info_url: "/oauth2/userinfo"
      }

      assert {:ok, config} = CustomOAuth2.config_for_organization(organization)

      assert config.site == "https://auth.example.com"
      assert config.provider_organization_id == "https://auth.example.com"
      assert config.client_id == "test_client_id"
      assert config.client_secret == "test_client_secret"
      assert config.authorize_url == "/oauth2/authorize"
      assert config.token_url == "/oauth2/token"
      assert config.user_info_url == "/oauth2/userinfo"
    end

    test "returns error for non-custom organization" do
      organization = %Organization{
        sso_provider: :okta,
        sso_organization_id: "dev-example.okta.com"
      }

      assert {:error, :custom_oauth2_not_configured} =
               CustomOAuth2.config_for_organization(organization)
    end
  end
end
