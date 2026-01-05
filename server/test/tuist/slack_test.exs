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

  describe "list_project_alerts/1" do
    test "returns alerts for a project" do
      # Given
      project = TuistTestSupport.Fixtures.ProjectsFixtures.project_fixture()
      alert1 = SlackFixtures.slack_alert_fixture(project: project, category: :build_run_duration)
      alert2 = SlackFixtures.slack_alert_fixture(project: project, category: :test_run_duration)

      # When
      alerts = Slack.list_project_alerts(project.id)

      # Then
      assert length(alerts) == 2
      alert_ids = Enum.map(alerts, & &1.id)
      assert alert1.id in alert_ids
      assert alert2.id in alert_ids
    end

    test "returns empty list when project has no alerts" do
      # Given
      project = TuistTestSupport.Fixtures.ProjectsFixtures.project_fixture()

      # When
      alerts = Slack.list_project_alerts(project.id)

      # Then
      assert alerts == []
    end
  end

  describe "get_alert/1" do
    test "returns alert when it exists" do
      # Given
      alert = SlackFixtures.slack_alert_fixture()

      # When
      result = Slack.get_alert(alert.id)

      # Then
      assert {:ok, fetched_alert} = result
      assert fetched_alert.id == alert.id
    end

    test "returns error when alert does not exist" do
      # Given
      non_existent_id = Ecto.UUID.generate()

      # When
      result = Slack.get_alert(non_existent_id)

      # Then
      assert {:error, :not_found} = result
    end
  end

  describe "create_alert/1" do
    test "creates an alert with valid attributes" do
      # Given
      project = TuistTestSupport.Fixtures.ProjectsFixtures.project_fixture()

      attrs = %{
        project_id: project.id,
        category: :build_run_duration,
        metric: :p90,
        threshold_percentage: 20.0,
        sample_size: 100,
        slack_channel_id: "C123456",
        slack_channel_name: "test-channel"
      }

      # When
      result = Slack.create_alert(attrs)

      # Then
      assert {:ok, alert} = result
      assert alert.project_id == project.id
      assert alert.category == :build_run_duration
      assert alert.metric == :p90
      assert alert.threshold_percentage == 20.0
      assert alert.sample_size == 100
      assert alert.slack_channel_id == "C123456"
      assert alert.slack_channel_name == "test-channel"
      assert alert.enabled == true
    end

    test "returns error with invalid attributes" do
      # When
      result = Slack.create_alert(%{})

      # Then
      assert {:error, changeset} = result
      assert changeset.valid? == false
    end
  end

  describe "update_alert/2" do
    test "updates an alert" do
      # Given
      alert = SlackFixtures.slack_alert_fixture()

      # When
      result = Slack.update_alert(alert, %{threshold_percentage: 30.0, metric: :p99})

      # Then
      assert {:ok, updated} = result
      assert updated.threshold_percentage == 30.0
      assert updated.metric == :p99
      assert updated.category == alert.category
    end

    test "can disable an alert" do
      # Given
      alert = SlackFixtures.slack_alert_fixture(enabled: true)

      # When
      result = Slack.update_alert(alert, %{enabled: false})

      # Then
      assert {:ok, updated} = result
      assert updated.enabled == false
    end
  end

  describe "delete_alert/1" do
    test "deletes an alert" do
      # Given
      alert = SlackFixtures.slack_alert_fixture()

      # When
      result = Slack.delete_alert(alert)

      # Then
      assert {:ok, _deleted} = result
      assert Slack.get_alert(alert.id) == {:error, :not_found}
    end
  end

  describe "list_enabled_alerts/0" do
    test "returns only enabled alerts with preloaded associations" do
      # Given
      project = TuistTestSupport.Fixtures.ProjectsFixtures.project_fixture()
      enabled_alert = SlackFixtures.slack_alert_fixture(project: project, enabled: true)
      _disabled_alert = SlackFixtures.slack_alert_fixture(project: project, enabled: false)

      # When
      alerts = Slack.list_enabled_alerts()

      # Then
      alert_ids = Enum.map(alerts, & &1.id)
      assert enabled_alert.id in alert_ids
    end

    test "preloads project and account" do
      # Given
      project = TuistTestSupport.Fixtures.ProjectsFixtures.project_fixture()
      _alert = SlackFixtures.slack_alert_fixture(project: project, enabled: true)

      # When
      [fetched_alert] = Slack.list_enabled_alerts()

      # Then
      assert fetched_alert.project != nil
      assert fetched_alert.project.account != nil
    end
  end

  describe "cooldown_elapsed?/1" do
    test "returns true when last_triggered_at is nil" do
      # Given
      alert = SlackFixtures.slack_alert_fixture(last_triggered_at: nil)

      # When/Then
      assert Slack.cooldown_elapsed?(alert) == true
    end

    test "returns true when more than 24 hours have passed" do
      # Given
      twenty_five_hours_ago = DateTime.add(DateTime.utc_now(), -25, :hour)
      alert = SlackFixtures.slack_alert_fixture(last_triggered_at: twenty_five_hours_ago)

      # When/Then
      assert Slack.cooldown_elapsed?(alert) == true
    end

    test "returns false when less than 24 hours have passed" do
      # Given
      one_hour_ago = DateTime.add(DateTime.utc_now(), -1, :hour)
      alert = SlackFixtures.slack_alert_fixture(last_triggered_at: one_hour_ago)

      # When/Then
      assert Slack.cooldown_elapsed?(alert) == false
    end
  end

  describe "update_alert_triggered_at/1" do
    test "updates last_triggered_at to current time" do
      # Given
      alert = SlackFixtures.slack_alert_fixture(last_triggered_at: nil)

      # When
      {:ok, updated} = Slack.update_alert_triggered_at(alert)

      # Then
      assert updated.last_triggered_at != nil
      assert DateTime.diff(DateTime.utc_now(), updated.last_triggered_at, :second) < 5
    end
  end
end
