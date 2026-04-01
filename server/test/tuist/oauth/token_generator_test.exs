defmodule Tuist.OAuth.TokenGeneratorTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Boruta.Ecto.Token
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
    test "generates a user token without type claim", %{user: user} do
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      refute Map.has_key?(claims, "type")
      refute Map.has_key?(claims, "all_projects")
      refute Map.has_key?(claims, "scopes")
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

    test "resolves to User", %{user: user} do
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      {:ok, resource, _claims} = Tuist.Guardian.resource_from_token(jwt_token)
      assert %Tuist.Accounts.User{} = resource
      assert resource.id == user.id
    end

    test "resolves to User via Tuist.Authentication.authenticated_subject", %{user: user} do
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      subject = Tuist.Authentication.authenticated_subject(jwt_token)
      assert %Tuist.Accounts.User{} = subject
      assert subject.id == user.id
    end

    test "user can access all their organizations", %{user: user} do
      org = AccountsFixtures.organization_fixture(creator: user)

      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      subject = Tuist.Authentication.authenticated_subject(jwt_token)
      org_accounts = Tuist.Accounts.get_user_organization_accounts(subject)
      org_ids = Enum.map(org_accounts, & &1.organization.id)
      assert org.id in org_ids
    end

    test "user can list all accessible projects including org projects", %{user: user, project: project} do
      org = AccountsFixtures.organization_fixture(creator: user)
      org_project = ProjectsFixtures.project_fixture(account: org.account)
      CommandEventsFixtures.command_event_fixture(project_id: org_project.id)

      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      jwt_token = TokenGenerator.generate(:access_token, token)

      subject = Tuist.Authentication.authenticated_subject(jwt_token)
      projects = Tuist.Projects.list_accessible_projects(subject)
      project_ids = Enum.map(projects, & &1.id)
      assert project.id in project_ids
      assert org_project.id in project_ids
    end
  end
end
