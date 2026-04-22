defmodule Tuist.OAuth.TokenGeneratorTest do
  use TuistTestSupport.Cases.DataCase, clickhouse: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Accounts.AuthenticatedAccount
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
  end
end
