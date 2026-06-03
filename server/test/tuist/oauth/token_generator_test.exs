defmodule Tuist.OAuth.TokenGeneratorTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.AuthenticatedService
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    project = ProjectsFixtures.project_fixture(account: user.account)
    CommandEventsFixtures.command_event_fixture(project_id: project.id)

    client = %{
      id: "test-client-id",
      access_token_ttl: 3600,
      refresh_token_ttl: 86_400
    }

    stub(Clients, :get_client, fn _ -> client end)

    {:ok, user: user, project: project, client: client}
  end

  describe "generate/2" do
    test "generates an account token with type claim", %{user: user} do
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      assert claims["type"] == "account"
      assert claims["all_projects"] == true
      assert is_map(claims["cache_grants"])
    end

    test "does not embed account-scoped cache grants for user-issued OAuth tokens", %{
      user: user,
      project: project
    } do
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      project_handle = "#{user.account.name}/#{project.name}"

      refute Map.has_key?(claims, "accounts")
      assert claims["cache_grants"]["account"]["read"] == []
      assert claims["cache_grants"]["account"]["write"] == []
      assert project_handle in claims["cache_grants"]["project"]["read"]
      assert project_handle in claims["cache_grants"]["project"]["write"]
    end

    test "keeps OAuth token size independent from accessible account count", %{user: user} do
      for _ <- 1..20 do
        organization = AccountsFixtures.organization_fixture()
        Accounts.add_user_to_organization(user, organization, role: :admin)
      end

      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)

      refute Map.has_key?(claims, "accounts")
      assert claims["cache_grants"]["account"]["read"] == []
      assert claims["cache_grants"]["account"]["write"] == []
      assert byte_size(jwt_token) < 5_000
    end

    test "includes user_id claim", %{user: user} do
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      assert claims["user_id"] == user.id
    end

    test "includes preferred_username claim", %{user: user} do
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      assert claims["preferred_username"] == user.account.name
    end

    test "includes email claim", %{user: user} do
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      assert claims["email"] == user.email
    end

    test "uses access_token_ttl from client for access tokens", %{user: user, client: client} do
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      assert claims["exp"] - claims["iat"] == client.access_token_ttl
    end

    test "uses refresh_token_ttl from client for refresh tokens", %{user: user, client: client} do
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      jwt_token = TokenGenerator.generate(:refresh_token, token)

      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      assert claims["exp"] - claims["iat"] == client.refresh_token_ttl
    end

    test "returns nil when user not found" do
      token = %Token{
        sub: "99999999",
        client_id: "test-client-id"
      }

      assert is_nil(TokenGenerator.generate(:access_token, token))
    end

    test "returns nil when client not found", %{user: user} do
      stub(Clients, :get_client, fn _ -> nil end)

      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "non-existent-client"
      }

      assert is_nil(TokenGenerator.generate(:access_token, token))
    end

    test "includes mcp in scopes when scope is mcp", %{user: user} do
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id",
        scope: "mcp"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      assert claims["scopes"] == ["mcp"]
    end

    test "sets default user scopes when no scope is provided", %{user: user} do
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id",
        scope: ""
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)

      assert claims["scopes"] == [
               "account:cache:read",
               "account:cache:write",
               "project:admin:read",
               "project:cache:read",
               "project:cache:write",
               "project:previews:read",
               "project:previews:write",
               "project:bundles:read",
               "project:bundles:write",
               "project:tests:read",
               "project:tests:write",
               "project:builds:read",
               "project:builds:write",
               "project:runs:read",
               "project:runs:write"
             ]
    end

    test "sets default user scopes when scope is nil", %{user: user} do
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id",
        scope: nil
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)

      assert claims["scopes"] == [
               "account:cache:read",
               "account:cache:write",
               "project:admin:read",
               "project:cache:read",
               "project:cache:write",
               "project:previews:read",
               "project:previews:write",
               "project:bundles:read",
               "project:bundles:write",
               "project:tests:read",
               "project:tests:write",
               "project:builds:read",
               "project:builds:write",
               "project:runs:read",
               "project:runs:write"
             ]
    end

    test "resolves to AuthenticatedAccount with correct fields", %{user: user} do
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id",
        scope: "mcp"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, resource, _claims} = Tuist.Guardian.resource_from_token(jwt_token)
      assert %AuthenticatedAccount{} = resource
      assert resource.scopes == ["mcp"]
      assert resource.all_projects == true
      assert resource.account.id == user.account.id
      assert resource.issued_by.id == user.id
    end

    test "can list all accessible projects including org projects", %{user: user, project: project} do
      org = AccountsFixtures.organization_fixture(creator: user)
      org_project = ProjectsFixtures.project_fixture(account: org.account)
      CommandEventsFixtures.command_event_fixture(project_id: org_project.id)

      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, subject, _claims} = Tuist.Guardian.resource_from_token(jwt_token)
      projects = Tuist.Projects.list_accessible_projects(subject)
      project_ids = Enum.map(projects, & &1.id)
      assert project.id in project_ids
      assert org_project.id in project_ids
    end

    test "generates a service token when the OAuth token has no user subject" do
      stub(Clients, :service_client?, fn "service-client" -> true end)

      token = %Token{
        sub: nil,
        client_id: "service-client",
        scope: "account:service:read:any"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      assert claims["type"] == "service"
      assert claims["client_id"] == "service-client"
      assert claims["scopes"] == ["account:service:read:any"]
    end

    test "resolves service tokens to an AuthenticatedService" do
      stub(Clients, :service_client?, fn "service-client" -> true end)

      token = %Token{
        sub: nil,
        client_id: "service-client",
        scope: "account:service:read:any"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, resource, _claims} = Tuist.Guardian.resource_from_token(jwt_token)
      assert %AuthenticatedService{client_id: "service-client", scopes: ["account:service:read:any"]} = resource
    end

    test "does not generate a service token for non-service clients" do
      stub(Clients, :service_client?, fn "test-client-id" -> false end)

      token = %Token{
        sub: nil,
        client_id: "test-client-id",
        scope: "account:service:read:any"
      }

      assert TokenGenerator.generate(:access_token, token) == nil
    end

    test "routes a numeric service client id to a service token, not a user token" do
      stub(Clients, :service_client?, fn "123456" -> true end)

      token = %Token{
        sub: "123456",
        client_id: "123456",
        scope: "account:service:read:any"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      assert claims["type"] == "service"
      assert claims["client_id"] == "123456"
      refute Map.has_key?(claims, "user_id")
    end
  end
end
