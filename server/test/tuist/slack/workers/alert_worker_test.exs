defmodule Tuist.Slack.Workers.AlertWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Alerts
  alias Tuist.Alerts.Alert
  alias Tuist.Slack
  alias Tuist.Slack.Client
  alias Tuist.Slack.Workers.AlertWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AlertsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.SlackFixtures

  setup do
    user = %{account: account} = AccountsFixtures.user_fixture(preload: [:account])
    slack_installation = SlackFixtures.slack_installation_fixture(account_id: account.id)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{user: user, project: project, account: account, slack_installation: slack_installation}
  end

  describe "perform/1 with no args (cron mode)" do
    test "enqueues jobs for enabled alert rules", %{project: project} do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project, enabled: true)

      expect(Oban, :insert, fn changeset ->
        assert changeset.changes.args == %{alert_rule_id: alert_rule.id}
        {:ok, %Oban.Job{}}
      end)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{}})

      # Then
      assert result == :ok
    end

    test "does not enqueue jobs for disabled alert rules", %{project: project} do
      # Given
      _disabled_alert_rule = AlertsFixtures.alert_rule_fixture(project: project, enabled: false)

      reject(&Oban.insert/1)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{}})

      # Then
      assert result == :ok
    end
  end

  describe "perform/1 with alert_rule_id (job mode)" do
    test "sends alert when threshold is exceeded", %{project: project, slack_installation: slack_installation} do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project, enabled: true, last_triggered_at: nil)

      triggered_alert = %Alert{
        alert_rule_id: alert_rule.id,
        project_id: project.id,
        account_id: project.account_id,
        account_name: "test-account",
        project_name: project.name,
        category: :build_run_duration,
        metric: :p90,
        threshold_percentage: 20.0,
        current_value: 1200,
        previous_value: 1000,
        change_percentage: 20.0,
        slack_channel_id: alert_rule.slack_channel_id,
        slack_channel_name: alert_rule.slack_channel_name,
        triggered_at: DateTime.utc_now()
      }

      stub(Alerts, :cooldown_elapsed?, fn _alert_rule -> true end)
      expect(Alerts, :evaluate, fn _alert_rule -> {:triggered, triggered_alert} end)

      expect(Slack, :send_alert, fn alert, installation ->
        assert alert.current_value == 1200
        assert installation.access_token == slack_installation.access_token
        :ok
      end)

      stub(Alerts, :update_alert_rule_triggered_at, fn _alert_rule -> {:ok, alert_rule} end)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{"alert_rule_id" => alert_rule.id}})

      # Then
      assert result == :ok
    end

    test "does not send alert when threshold is not exceeded", %{project: project} do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project, enabled: true)

      stub(Alerts, :cooldown_elapsed?, fn _alert_rule -> true end)
      expect(Alerts, :evaluate, fn _alert_rule -> :ok end)

      reject(&Client.post_message/3)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{"alert_rule_id" => alert_rule.id}})

      # Then
      assert result == :ok
    end

    test "does not send alert when cooldown has not elapsed", %{project: project} do
      # Given
      one_hour_ago = DateTime.add(DateTime.utc_now(), -1, :hour)
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project, enabled: true, last_triggered_at: one_hour_ago)

      stub(Alerts, :cooldown_elapsed?, fn _alert_rule -> false end)

      reject(&Alerts.evaluate/1)
      reject(&Client.post_message/3)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{"alert_rule_id" => alert_rule.id}})

      # Then
      assert result == :ok
    end

    test "does not send alert when alert rule is disabled", %{project: project} do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project, enabled: false)

      reject(&Alerts.cooldown_elapsed?/1)
      reject(&Alerts.evaluate/1)
      reject(&Client.post_message/3)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{"alert_rule_id" => alert_rule.id}})

      # Then
      assert result == :ok
    end

    test "returns :ok when alert rule does not exist" do
      # Given
      non_existent_id = Ecto.UUID.generate()

      reject(&Client.post_message/3)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{"alert_rule_id" => non_existent_id}})

      # Then
      assert result == :ok
    end

    test "returns :ok when slack installation does not exist" do
      # Given - create a project for an account without slack installation
      other_user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(account_id: other_user.account.id)
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project, enabled: true)

      # No slack installation for this account, so early return before evaluate is called
      reject(&Alerts.evaluate/1)
      reject(&Client.post_message/3)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{"alert_rule_id" => alert_rule.id}})

      # Then
      assert result == :ok
    end
  end
end
