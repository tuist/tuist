defmodule Tuist.SlackTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Environment
  alias Tuist.Slack
  alias Tuist.Slack.Client
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.SlackFixtures

  describe "send_message/2" do
    setup do
      stub(Environment, :prod?, fn -> true end)
      stub(Environment, :tuist_hosted?, fn -> true end)
      :ok
    end

    test "when the response is successful" do
      # Given
      token = "token"
      stub(Environment, :slack_tuist_token, fn -> token end)

      stub(Req, :post, fn _, [headers: _, body: _] ->
        {:ok, %Req.Response{status: 200, body: %{}}}
      end)

      # When
      response = Slack.send_message(%{})

      # Then
      assert response == :ok
    end

    test "when the response is not successful" do
      # Given
      token = "token"
      stub(Environment, :slack_tuist_token, fn -> token end)

      stub(Req, :post, fn _, [headers: _, body: _] ->
        {:ok, %Req.Response{status: 400, body: %{}}}
      end)

      # When
      response = Slack.send_message(%{})

      # Then
      assert response == {:error, "Unexpected status code: 400. Body: {}"}
    end

    test "when the request fails" do
      # Given
      token = "token"
      stub(Environment, :slack_tuist_token, fn -> token end)
      stub(Req, :post, fn _, [headers: _, body: _] -> {:error, "error"} end)

      # When
      response = Slack.send_message(%{})

      # Then
      assert response == {:error, "Request failed: \"error\""}
    end
  end

  describe "create_installation/1" do
    test "creates a Slack installation with valid attributes" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account

      attrs = %{
        account_id: account.id,
        team_id: "T12345",
        team_name: "Test Workspace",
        access_token: "xoxb-test-token",
        bot_user_id: "U12345"
      }

      # When
      result = Slack.create_installation(attrs)

      # Then
      assert {:ok, installation} = result
      assert installation.account_id == account.id
      assert installation.team_id == "T12345"
      assert installation.team_name == "Test Workspace"
      assert installation.bot_user_id == "U12345"
    end

    test "returns error with invalid attributes" do
      # When
      result = Slack.create_installation(%{})

      # Then
      assert {:error, changeset} = result
      assert changeset.valid? == false
    end
  end

  describe "update_installation/2" do
    test "updates a Slack installation" do
      # Given
      user = AccountsFixtures.user_fixture()
      installation = SlackFixtures.slack_installation_fixture(account_id: user.account.id)

      # When
      result = Slack.update_installation(installation, %{team_name: "Updated Workspace"})

      # Then
      assert {:ok, updated} = result
      assert updated.team_name == "Updated Workspace"
      assert updated.team_id == installation.team_id
    end
  end

  describe "delete_installation/1" do
    test "deletes a Slack installation" do
      # Given
      user = AccountsFixtures.user_fixture()
      installation = SlackFixtures.slack_installation_fixture(account_id: user.account.id)

      # When
      result = Slack.delete_installation(installation)

      # Then
      assert {:ok, _deleted} = result
      assert Repo.get(Tuist.Slack.Installation, installation.id) == nil
    end
  end

  describe "get_installation_channels/1" do
    test "returns channels from the Slack API" do
      # Given
      user = AccountsFixtures.user_fixture()
      installation = SlackFixtures.slack_installation_fixture(account_id: user.account.id, team_id: "T-test-channels")

      channels = [
        %{id: "C123", name: "general", is_private: false},
        %{id: "C456", name: "random", is_private: false}
      ]

      # Stub KeyValueStore to bypass cache and call the function directly
      stub(Tuist.KeyValueStore, :get_or_update, fn _key, _opts, func ->
        func.()
      end)

      expect(Client, :list_all_channels, fn _access_token ->
        {:ok, channels}
      end)

      # When
      result = Slack.get_installation_channels(installation)

      # Then
      assert {:ok, ^channels} = result
    end

    test "returns error when Slack API fails" do
      # Given
      user = AccountsFixtures.user_fixture()
      installation = SlackFixtures.slack_installation_fixture(account_id: user.account.id, team_id: "T-error-team")

      # Stub KeyValueStore to bypass cache and call the function directly
      stub(Tuist.KeyValueStore, :get_or_update, fn _key, _opts, func ->
        func.()
      end)

      expect(Client, :list_all_channels, fn _access_token ->
        {:error, "API error"}
      end)

      # When
      result = Slack.get_installation_channels(installation)

      # Then
      assert {:error, "API error"} = result
    end
  end

  describe "generate_state_token/1" do
    test "generates a signed token for the account ID" do
      # Given
      account_id = "test-account-id"

      # When
      token = Slack.generate_state_token(account_id)

      # Then
      assert is_binary(token)
      assert String.length(token) > 0
    end
  end

  describe "verify_state_token/1" do
    test "verifies a valid token and returns the account ID" do
      # Given
      account_id = "test-account-id"
      token = Slack.generate_state_token(account_id)

      # When
      result = Slack.verify_state_token(token)

      # Then
      assert {:ok, ^account_id} = result
    end

    test "returns error for invalid token" do
      # When
      result = Slack.verify_state_token("invalid-token")

      # Then
      assert {:error, _reason} = result
    end
  end
end
