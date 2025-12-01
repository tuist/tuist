defmodule Tuist.OAuth.OktaTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Accounts.Organization
  alias Tuist.OAuth.Okta

  describe "config_for_organization/1" do
    test "returns config for Okta organization with database fields" do
      organization = %Organization{
        id: 123,
        sso_provider: :okta,
        sso_organization_id: "dev-example.okta.com",
        okta_client_id: "test_client_id",
        okta_encrypted_client_secret: "test_client_secret"
      }

      assert {:ok, config} = Okta.config_for_organization(organization)

      assert config.domain == "dev-example.okta.com"
      assert config.client_id == "test_client_id"
      assert config.client_secret == "test_client_secret"
      assert config.authorize_url == "/oauth2/v1/authorize"
      assert config.token_url == "/oauth2/v1/token"
      assert config.user_info_url == "/oauth2/v1/userinfo"
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

    test "returns error for Okta organization with missing client_id" do
      organization = %Organization{
        sso_provider: :okta,
        sso_organization_id: "dev-example.okta.com",
        okta_client_id: nil,
        okta_encrypted_client_secret: "test_client_secret"
      }

      assert {:error, :okta_not_configured} = Okta.config_for_organization(organization)
    end

    test "returns error for Okta organization with missing client_secret" do
      organization = %Organization{
        sso_provider: :okta,
        sso_organization_id: "dev-example.okta.com",
        okta_client_id: "test_client_id",
        okta_encrypted_client_secret: nil
      }

      assert {:error, :okta_not_configured} = Okta.config_for_organization(organization)
    end

    test "returns error for Okta organization with missing sso_organization_id" do
      organization = %Organization{
        sso_provider: :okta,
        sso_organization_id: nil,
        okta_client_id: "test_client_id",
        okta_encrypted_client_secret: "test_client_secret"
      }

      assert {:error, :okta_not_configured} = Okta.config_for_organization(organization)
    end
  end
end
