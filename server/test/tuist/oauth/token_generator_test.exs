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
    test "generates access token with projects claim", %{user: user, project: project} do
      # Given
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      # When
      jwt_token = TokenGenerator.generate(:access_token, token)

      # Then
      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      assert is_list(claims["projects"])
      assert "#{user.account.name}/#{project.name}" in claims["projects"]
    end

    test "generates refresh token with projects claim", %{user: user, project: project} do
      # Given
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      # When
      jwt_token = TokenGenerator.generate(:refresh_token, token)

      # Then
      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      assert is_list(claims["projects"])
      assert "#{user.account.name}/#{project.name}" in claims["projects"]
    end

    test "includes preferred_username claim", %{user: user} do
      # Given
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      # When
      jwt_token = TokenGenerator.generate(:access_token, token)

      # Then
      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      assert claims["preferred_username"] == user.account.name
    end

    test "includes email claim", %{user: user} do
      # Given
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      # When
      jwt_token = TokenGenerator.generate(:access_token, token)

      # Then
      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      assert claims["email"] == user.email
    end

    test "uses access_token_ttl from client for access tokens", %{user: user, client: client} do
      # Given
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      # When
      jwt_token = TokenGenerator.generate(:access_token, token)

      # Then
      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      exp = claims["exp"]
      iat = claims["iat"]
      assert exp - iat == client.access_token_ttl
    end

    test "uses refresh_token_ttl from client for refresh tokens", %{user: user, client: client} do
      # Given
      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "test-client-id"
      }

      # When
      jwt_token = TokenGenerator.generate(:refresh_token, token)

      # Then
      {:ok, claims} = Tuist.Guardian.decode_and_verify(jwt_token)
      exp = claims["exp"]
      iat = claims["iat"]
      assert exp - iat == client.refresh_token_ttl
    end

    test "returns nil when user not found" do
      # Given
      token = %Token{
        sub: "99999999",
        client_id: "test-client-id"
      }

      # When
      result = TokenGenerator.generate(:access_token, token)

      # Then
      assert is_nil(result)
    end

    test "returns nil when client not found", %{user: user} do
      # Given
      stub(Clients, :get_client, fn _ -> nil end)

      token = %Token{
        sub: Integer.to_string(user.id),
        client_id: "non-existent-client"
      }

      # When
      result = TokenGenerator.generate(:access_token, token)

      # Then
      assert is_nil(result)
    end
  end
end
