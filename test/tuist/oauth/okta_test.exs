defmodule Tuist.OAuth.OktaTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Accounts.Organization
  alias Tuist.OAuth.Okta

  describe "config_for_organization/1" do
    test "returns config for Okta organization" do
      organization = %Organization{
        id: 123,
        sso_provider: :okta,
        sso_organization_id: "dev-123456"
      }

      expect(Tuist.Environment, :okta_client_id_for_organization_id, fn 123 -> "test_client_id" end)
      expect(Tuist.Environment, :okta_client_secret_for_organization_id, fn 123 -> "test_client_secret" end)

      assert {:ok, config} = Okta.config_for_organization(organization)

      assert config.domain == "dev-123456"
      assert config.client_id == "test_client_id"
      assert config.client_secret == "test_client_secret"
      assert config.authorize_url == "/oauth2/default/v1/authorize"
      assert config.token_url == "/oauth2/default/v1/token"
      assert config.user_info_url == "/oauth2/default/v1/userinfo"
    end

    test "returns error for non-Okta organization" do
      organization = %Organization{
        sso_provider: :google,
        sso_organization_id: "example.com"
      }

      assert {:error, :okta_not_configured} = Okta.config_for_organization(organization)
    end

    test "returns error for organization without SSO provider" do
      organization = %Organization{
        sso_provider: nil,
        sso_organization_id: nil
      }

      assert {:error, :okta_not_configured} = Okta.config_for_organization(organization)
    end
  end
end
