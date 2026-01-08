defmodule Tuist.Slack.Workers.AlertWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Alerts
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
    test "enqueues jobs for all alert rules", %{project: project} do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project)

      expect(Oban, :insert, fn changeset ->
        assert changeset.changes.args == %{alert_rule_id: alert_rule.id}
        {:ok, %Oban.Job{}}
      end)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{}})

      # Then
      assert result == :ok
    end
  end

  describe "perform/1 with alert_rule_id (job mode)" do
    test "sends alert when threshold is exceeded", %{project: project, slack_installation: slack_installation} do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project)

      triggered_result = %{current: 1200.0, previous: 1000.0, deviation: 20.0}

      stub(Alerts, :cooldown_elapsed?, fn _alert_rule -> true end)
      expect(Alerts, :evaluate, fn _alert_rule -> {:triggered, triggered_result} end)

      expect(Slack, :send_alert, fn alert ->
        assert alert.current_value == 1200.0
        assert alert.alert_rule.project.account.slack_installation.access_token == slack_installation.access_token
        :ok
      end)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{"alert_rule_id" => alert_rule.id}})

      # Then
      assert result == :ok
    end

    test "does not send alert when threshold is not exceeded", %{project: project} do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project)

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
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project)

      stub(Alerts, :cooldown_elapsed?, fn _alert_rule -> false end)

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
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project)

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
