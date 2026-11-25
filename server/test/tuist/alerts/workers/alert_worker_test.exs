defmodule Tuist.Alerts.Workers.AlertWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Alerts
  alias Tuist.Alerts.Workers.AlertWorker
  alias Tuist.Repo
  alias Tuist.Slack
  alias Tuist.Slack.Client
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AlertsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = %{account: account} = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{user: user, project: project, account: account}
  end

  describe "perform/1 with no args (cron mode)" do
    test "enqueues jobs for all alert rules", %{project: project} do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project)

      expect(Oban, :insert!, fn changeset ->
        assert changeset.changes.args == %{alert_rule_id: alert_rule.id}
        %Oban.Job{}
      end)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{}})

      # Then
      assert result == :ok
    end
  end

  describe "perform/1 with alert_rule_id (job mode)" do
    test "sends alert when threshold is exceeded", %{project: project} do
      # Given
      alert_rule =
        AlertsFixtures.alert_rule_fixture(
          project: project,
          slack_webhook_url: "https://hooks.slack.com/services/T0/B0/abc"
        )

      triggered_result = %{current: 1200.0, previous: 1000.0, deviation: 20.0}

      stub(Alerts, :cooldown_elapsed?, fn _alert_rule -> true end)
      expect(Alerts, :evaluate, fn _alert_rule -> {:triggered, triggered_result} end)

      expect(Slack, :send_alert, fn alert ->
        assert alert.current_value == 1200.0
        :ok
      end)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{"alert_rule_id" => alert_rule.id}})

      # Then
      assert result == :ok
    end

    test "retries an alert whose Slack delivery failed instead of starting its cooldown", %{project: project} do
      # Given
      alert_rule =
        AlertsFixtures.alert_rule_fixture(
          project: project,
          slack_webhook_url: "https://hooks.slack.com/services/T0/B0/abc"
        )

      stub(Alerts, :evaluate, fn _alert_rule -> {:triggered, %{current: 1200.0, previous: 1000.0, deviation: 20.0}} end)
      expect(Client, :post_to_webhook, fn _url, _blocks -> {:error, "Unexpected status code: 503"} end)
      expect(Client, :post_to_webhook, fn _url, _blocks -> :ok end)
      job = %Oban.Job{args: %{"alert_rule_id" => alert_rule.id}}

      # When
      assert {:error, _reason} = AlertWorker.perform(job)
      assert Repo.all(Alerts.Alert) == []
      result = AlertWorker.perform(job)

      # Then
      assert result == :ok
      assert [_delivered] = Repo.all(Alerts.Alert)
    end

    test "starts the cooldown when the last attempt fails, so an unknown failure isn't retried every tick", %{
      project: project
    } do
      # Given
      alert_rule =
        AlertsFixtures.alert_rule_fixture(
          project: project,
          slack_webhook_url: "https://hooks.slack.com/services/T0/B0/abc"
        )

      stub(Alerts, :evaluate, fn _alert_rule -> {:triggered, %{current: 1200.0, previous: 1000.0, deviation: 20.0}} end)
      expect(Client, :post_to_webhook, fn _url, _blocks -> {:error, "Unexpected status code: 503"} end)

      # When
      result =
        AlertWorker.perform(%Oban.Job{args: %{"alert_rule_id" => alert_rule.id}, attempt: 3, max_attempts: 3})

      # Then
      assert {:discard, _reason} = result
      assert [_cooldown] = Repo.all(Alerts.Alert)
    end

    test "starts the cooldown when Slack rejects the alert for good, so a dead webhook isn't retried", %{
      project: project
    } do
      # Given
      alert_rule =
        AlertsFixtures.alert_rule_fixture(
          project: project,
          slack_webhook_url: "https://hooks.slack.com/services/T0/B0/abc"
        )

      stub(Alerts, :evaluate, fn _alert_rule -> {:triggered, %{current: 1200.0, previous: 1000.0, deviation: 20.0}} end)
      expect(Client, :post_to_webhook, fn _url, _blocks -> {:error, :webhook_revoked} end)
      job = %Oban.Job{args: %{"alert_rule_id" => alert_rule.id}}

      # When
      assert {:discard, _reason} = AlertWorker.perform(job)
      assert :ok = AlertWorker.perform(job)

      # Then
      assert [_cooldown] = Repo.all(Alerts.Alert)
    end

    test "does not send alert when threshold is not exceeded", %{project: project} do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project)

      stub(Alerts, :cooldown_elapsed?, fn _alert_rule -> true end)
      expect(Alerts, :evaluate, fn _alert_rule -> :ok end)

      reject(&Client.post_to_webhook/2)

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
      reject(&Client.post_to_webhook/2)

      # When
      result = AlertWorker.perform(%Oban.Job{args: %{"alert_rule_id" => alert_rule.id}})

      # Then
      assert result == :ok
    end

    test "returns :ok when alert rule has no webhook url" do
      other_user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(account_id: other_user.account.id)
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project, slack_webhook_url: nil)

      reject(&Alerts.evaluate/1)
      reject(&Client.post_to_webhook/2)

      result = AlertWorker.perform(%Oban.Job{args: %{"alert_rule_id" => alert_rule.id}})

      assert result == :ok
    end
  end
end
