defmodule Tuist.SSOInsightsReproductionTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Environment
  alias Tuist.SCIM
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.Authorization.AuthorizationPlug
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit

  setup do
    stub(Environment, :tuist_hosted?, fn -> true end)

    domain = "sso-insights-#{System.unique_integer([:positive])}.example.com"

    organization =
      AccountsFixtures.organization_fixture(
        sso_login_domain: domain,
        sso_login_domain_verification_token: "verification-token",
        sso_login_domain_verified_at: DateTime.truncate(DateTime.utc_now(), :second)
      )

    user = AccountsFixtures.user_fixture(email: "developer-#{System.unique_integer([:positive])}@#{domain}")
    project = ProjectsFixtures.project_fixture(account: organization.account)

    identity =
      AccountsFixtures.oauth2_identity_fixture(
        user: user,
        provider: :okta,
        provider_organization_id: domain
      )

    %{organization: organization, user: user, project: project, identity: identity, domain: domain}
  end

  for role <- [:user, :admin] do
    @role role

    test "enabling SSO with a viewer default preserves an existing #{@role} role", context do
      %{organization: organization, user: user, project: project, domain: domain} = context
      :ok = Accounts.add_user_to_organization(user, organization, role: @role)
      assert_can_publish(user, project)

      organization = enable_sso(organization, domain)

      assert %{name: role} = Accounts.get_user_role_in_organization(user, organization)
      assert role == Atom.to_string(@role)
      assert_can_publish(user, project)
    end
  end

  test "signing in through SSO preserves an existing user role", context do
    %{organization: organization, user: user, project: project, identity: identity, domain: domain} = context
    :ok = Accounts.add_user_to_organization(user, organization, role: :user)
    organization = enable_sso(organization, domain)

    signed_in_user =
      Accounts.find_or_create_user_from_oauth2(%{
        provider: :okta,
        uid: identity.id_in_provider,
        info: %{email: user.email},
        extra: %{raw_info: %{provider_organization_id: domain}}
      })

    assert signed_in_user.id == user.id
    assert %{name: "user"} = Accounts.get_user_role_in_organization(user, organization)
    assert_can_publish(signed_in_user, project)
  end

  test "enabling SSO enrolls an existing identity without membership as a viewer", context do
    %{organization: organization, user: user, project: project, domain: domain} = context
    assert is_nil(Accounts.get_user_role_in_organization(user, organization))

    organization = enable_sso(organization, domain)

    assert %{name: "viewer"} = Accounts.get_user_role_in_organization(user, organization)
    assert_cannot_publish(user, project)
  end

  for role <- [:user, :admin] do
    @role role

    test "SCIM reprovisioning without a role downgrades an existing #{@role} to the viewer default", context do
      %{organization: organization, user: user, project: project, domain: domain} = context
      :ok = Accounts.add_user_to_organization(user, organization, role: @role)
      organization = enable_sso(organization, domain)
      assert_can_publish(user, project)

      assert {:ok, provisioned_user} = SCIM.provision_user(organization, %{user_name: user.email})

      assert provisioned_user.id == user.id
      assert %{name: "viewer"} = Accounts.get_user_role_in_organization(user, organization)
      assert_cannot_publish(provisioned_user, project)
    end
  end

  test "SCIM reprovisioning with an explicit user role preserves insight publication", context do
    %{organization: organization, user: user, project: project, domain: domain} = context
    :ok = Accounts.add_user_to_organization(user, organization, role: :user)
    organization = enable_sso(organization, domain)

    assert {:ok, provisioned_user} = SCIM.provision_user(organization, %{user_name: user.email, role: :user})

    assert %{name: "user"} = Accounts.get_user_role_in_organization(user, organization)
    assert_can_publish(provisioned_user, project)
  end

  defp enable_sso(organization, domain) do
    {:ok, organization} =
      Accounts.update_organization(organization, %{
        sso_provider: :okta,
        sso_organization_id: domain,
        sso_login_domain: domain,
        sso_automatic_enrollment: true,
        sso_default_role: "viewer",
        oauth2_client_id: "client-id",
        oauth2_encrypted_client_secret: "client-secret",
        oauth2_authorize_url: "https://#{domain}/oauth2/v1/authorize",
        oauth2_token_url: "https://#{domain}/oauth2/v1/token",
        oauth2_user_info_url: "https://#{domain}/oauth2/v1/userinfo"
      })

    organization
  end

  defp assert_can_publish(user, project) do
    assert Authorization.authorize(:run_create, user, project) == :ok
    assert Authorization.authorize(:build_create, user, project) == :ok
  end

  defp assert_cannot_publish(user, project) do
    assert Authorization.authorize(:run_create, user, project) == {:error, :forbidden}
    assert Authorization.authorize(:build_create, user, project) == {:error, :forbidden}
    assert Authorization.authorize(:run_read, user, project) == :ok

    stub(RateLimit.Authorization, :hit, fn _conn -> {:allow, 1} end)

    for {category, path} <- [
          {:run, "/api/analytics"},
          {:build, "/api/projects/#{project.account.name}/#{project.name}/builds/upload/start"}
        ] do
      conn =
        :post
        |> Plug.Test.conn(path)
        |> Authentication.put_current_user(user)
        |> Plug.Conn.assign(:selected_project, project)
        |> AuthorizationPlug.call(category)

      assert conn.status == 403
      assert conn.halted
    end
  end
end
