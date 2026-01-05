defmodule Tuist.Slack.Workers.AlertWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Slack
  alias Tuist.Slack.Alerts
  alias Tuist.Slack.Client
  alias Tuist.Slack.Workers.AlertWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.SlackFixtures

  setup do
    user = %{account: account} = AccountsFixtures.user_fixture(preload: [:account])
    slack_installation = SlackFixtures.slack_installation_fixture(account_id: account.id)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{user: user, project: project, account: account, slack_installation: slack_installation}
  end

  describe "perform/1 with no args (cron mode)" do
    test "enqueues jobs for enabled alerts", %{project: project} do
      # Given
      alert = SlackFixtures.slack_alert_fixture(project: project, enabled: true)

      expect(Oban, :insert, fn changeset ->
        assert changeset.changes.args == %{alert_id: alert.id}
        {:ok, %Oban.Job{}}
      end)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{}})

      # Then
      assert result == :ok
    end

    test "does not enqueue jobs for disabled alerts", %{project: project} do
      # Given
      _disabled_alert = SlackFixtures.slack_alert_fixture(project: project, enabled: false)

      reject(&Oban.insert/1)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{}})

      # Then
      assert result == :ok
    end
  end

  describe "perform/1 with alert_id (job mode)" do
    test "sends alert when threshold is exceeded", %{project: project, slack_installation: slack_installation} do
      # Given
      alert = SlackFixtures.slack_alert_fixture(project: project, enabled: true, last_triggered_at: nil)

      triggered_result = %{current: 1200, previous: 1000, change_pct: 20.0}

      stub(Slack, :cooldown_elapsed?, fn _alert -> true end)
      expect(Alerts, :evaluate, fn _alert -> {:triggered, triggered_result} end)
      expect(Alerts, :build_alert_blocks, fn _alert, _result -> [%{type: "section"}] end)

      expect(Client, :post_message, fn access_token, channel_id, blocks ->
        assert access_token == slack_installation.access_token
        assert channel_id == alert.slack_channel_id
        assert is_list(blocks)
        :ok
      end)

      stub(Slack, :update_alert_triggered_at, fn _alert -> {:ok, alert} end)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{"alert_id" => alert.id}})

      # Then
      assert result == :ok
    end

    test "does not send alert when threshold is not exceeded", %{project: project} do
      # Given
      alert = SlackFixtures.slack_alert_fixture(project: project, enabled: true)

      stub(Slack, :cooldown_elapsed?, fn _alert -> true end)
      expect(Alerts, :evaluate, fn _alert -> :ok end)

      reject(&Client.post_message/3)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{"alert_id" => alert.id}})

      # Then
      assert result == :ok
    end

    test "does not send alert when cooldown has not elapsed", %{project: project} do
      # Given
      one_hour_ago = DateTime.add(DateTime.utc_now(), -1, :hour)
      alert = SlackFixtures.slack_alert_fixture(project: project, enabled: true, last_triggered_at: one_hour_ago)

      stub(Slack, :cooldown_elapsed?, fn _alert -> false end)

      reject(&Alerts.evaluate/1)
      reject(&Client.post_message/3)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{"alert_id" => alert.id}})

      # Then
      assert result == :ok
    end

    test "does not send alert when alert is disabled", %{project: project} do
      # Given
      alert = SlackFixtures.slack_alert_fixture(project: project, enabled: false)

      reject(&Slack.cooldown_elapsed?/1)
      reject(&Alerts.evaluate/1)
      reject(&Client.post_message/3)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{"alert_id" => alert.id}})

      # Then
      assert result == :ok
    end

    test "returns :ok when alert does not exist" do
      # Given
      non_existent_id = Ecto.UUID.generate()

      reject(&Client.post_message/3)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{"alert_id" => non_existent_id}})

      # Then
      assert result == :ok
    end

    test "returns :ok when slack installation does not exist" do
      # Given - create a project for an account without slack installation
      other_user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(account_id: other_user.account.id)
      alert = SlackFixtures.slack_alert_fixture(project: project, enabled: true)

      # No slack installation for this account, so early return before evaluate is called
      reject(&Alerts.evaluate/1)
      reject(&Client.post_message/3)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{"alert_id" => alert.id}})

      # Then
      assert result == :ok
    end
  end
end
