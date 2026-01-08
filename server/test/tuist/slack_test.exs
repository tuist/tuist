defmodule Tuist.SlackTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Environment
  alias Tuist.Slack
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

  describe "generate_channel_selection_token/2" do
    test "generates a signed token for the project and account ID" do
      # Given
      project_id = 123
      account_id = 456

      # When
      token = Slack.generate_channel_selection_token(project_id, account_id)

      # Then
      assert is_binary(token)
      assert String.length(token) > 0
    end
  end

  describe "verify_state_token/1" do
    test "verifies an account installation token and returns the payload" do
      # Given
      account_id = "test-account-id"
      token = Slack.generate_state_token(account_id)

      # When
      result = Slack.verify_state_token(token)

      # Then
      assert {:ok, %{type: :account_installation, account_id: ^account_id}} = result
    end

    test "verifies a channel selection token and returns the payload" do
      # Given
      project_id = 123
      account_id = 456
      token = Slack.generate_channel_selection_token(project_id, account_id)

      # When
      result = Slack.verify_state_token(token)

      # Then
      assert {:ok, %{type: :channel_selection, project_id: ^project_id, account_id: ^account_id}} = result
    end

    test "returns error for invalid token" do
      # When
      result = Slack.verify_state_token("invalid-token")

      # Then
      assert {:error, _reason} = result
    end
  end
end
