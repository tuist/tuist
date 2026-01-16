defmodule Tuist.Alerts.Workers.FlakyTestAlertWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Alerts
  alias Tuist.Alerts.Workers.FlakyTestAlertWorker
  alias Tuist.Runs
  alias Tuist.Slack
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AlertsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.SlackFixtures

  setup do
    user = %{account: account} = AccountsFixtures.user_fixture(preload: [:account])
    slack_installation = SlackFixtures.slack_installation_fixture(account_id: account.id)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{user: user, project: project, account: account, slack_installation: slack_installation}
  end

  describe "perform/1" do
    test "sends alert when flaky runs count exceeds threshold", %{project: project} do
      # Given
      rule =
        AlertsFixtures.flaky_test_alert_rule_fixture(
          project: project,
          trigger_threshold: 3,
          slack_channel_id: "C12345",
          slack_channel_name: "flaky-alerts"
        )

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)
      stub(Runs, :get_flaky_runs_groups_count_for_test_case, fn _id -> 5 end)

      expect(Slack, :send_flaky_test_alert, fn alert ->
        assert alert.flaky_runs_count == 5
        assert alert.test_case_id == test_case.id
        assert alert.test_case_name == test_case.name
        assert alert.test_case_module_name == test_case.module_name
        assert alert.test_case_suite_name == test_case.suite_name
        assert alert.flaky_test_alert_rule_id == rule.id
        :ok
      end)

      # When
      result =
        FlakyTestAlertWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id}
        })

      # Then
      assert result == :ok
    end

    test "does not send alert when flaky runs count is below threshold", %{project: project} do
      # Given
      _rule =
        AlertsFixtures.flaky_test_alert_rule_fixture(
          project: project,
          trigger_threshold: 10,
          slack_channel_id: "C12345",
          slack_channel_name: "flaky-alerts"
        )

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)
      stub(Runs, :get_flaky_runs_groups_count_for_test_case, fn _id -> 5 end)

      reject(&Slack.send_flaky_test_alert/1)

      # When
      result =
        FlakyTestAlertWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id}
        })

      # Then
      assert result == :ok
    end

    test "does not send alert when slack_channel_id is nil", %{project: project} do
      # Given - create a mock rule struct without slack_channel_id
      mock_rule = %Tuist.Alerts.FlakyTestAlertRule{
        id: Ecto.UUID.generate(),
        project_id: project.id,
        name: "Flaky Test Alert",
        trigger_threshold: 3,
        slack_channel_id: nil,
        slack_channel_name: nil
      }

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)
      stub(Runs, :get_flaky_runs_groups_count_for_test_case, fn _id -> 5 end)
      stub(Alerts, :get_project_flaky_test_alert_rules, fn _project_id -> [mock_rule] end)

      reject(&Slack.send_flaky_test_alert/1)

      # When
      result =
        FlakyTestAlertWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id}
        })

      # Then
      assert result == :ok
    end

    test "does not send alert when slack installation does not exist" do
      # Given - create a project for an account without slack installation
      other_user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(account_id: other_user.account.id)

      _rule =
        AlertsFixtures.flaky_test_alert_rule_fixture(
          project: project,
          trigger_threshold: 3,
          slack_channel_id: "C12345",
          slack_channel_name: "flaky-alerts"
        )

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)
      stub(Runs, :get_flaky_runs_groups_count_for_test_case, fn _id -> 5 end)

      reject(&Slack.send_flaky_test_alert/1)

      # When
      result =
        FlakyTestAlertWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id}
        })

      # Then
      assert result == :ok
    end

    test "processes multiple rules and sends alert for each matching rule", %{project: project} do
      # Given
      rule1 =
        AlertsFixtures.flaky_test_alert_rule_fixture(
          project: project,
          trigger_threshold: 3,
          slack_channel_id: "C12345",
          slack_channel_name: "flaky-alerts-1"
        )

      rule2 =
        AlertsFixtures.flaky_test_alert_rule_fixture(
          project: project,
          trigger_threshold: 5,
          slack_channel_id: "C67890",
          slack_channel_name: "flaky-alerts-2"
        )

      rule1_id = rule1.id
      rule2_id = rule2.id

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)
      stub(Runs, :get_flaky_runs_groups_count_for_test_case, fn _id -> 10 end)

      expect(Slack, :send_flaky_test_alert, 2, fn alert ->
        send(self(), {:alert_sent, alert.flaky_test_alert_rule_id})
        :ok
      end)

      # When
      result =
        FlakyTestAlertWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id}
        })

      # Then
      assert result == :ok
      assert_received {:alert_sent, ^rule1_id}
      assert_received {:alert_sent, ^rule2_id}
    end

    test "returns :ok when test case is not found", %{project: project} do
      # Given
      test_case_id = Ecto.UUID.generate()

      stub(Runs, :get_test_case_by_id, fn _id -> {:error, :not_found} end)

      reject(&Slack.send_flaky_test_alert/1)

      # When
      result =
        FlakyTestAlertWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case_id, "project_id" => project.id}
        })

      # Then
      assert result == {:error, :not_found}
    end

    test "returns :ok when project has no alert rules", %{project: project} do
      # Given
      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)
      stub(Runs, :get_flaky_runs_groups_count_for_test_case, fn _id -> 5 end)

      reject(&Slack.send_flaky_test_alert/1)

      # When
      result =
        FlakyTestAlertWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id}
        })

      # Then
      assert result == :ok
    end
  end
end
