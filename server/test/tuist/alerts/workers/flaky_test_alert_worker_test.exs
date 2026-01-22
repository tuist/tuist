defmodule Tuist.Alerts.Workers.FlakyTestAlertWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Alerts.Workers.FlakyTestAlertWorker
  alias Tuist.Runs
  alias Tuist.Slack
  alias TuistTestSupport.Fixtures.AccountsFixtures
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
    test "sends alert when flaky_test_alerts_enabled and channel configured", %{project: project} do
      # Given
      {:ok, project} =
        Tuist.Projects.update_project(project, %{
          flaky_test_alerts_enabled: true,
          flaky_test_alerts_slack_channel_id: "C12345",
          flaky_test_alerts_slack_channel_name: "alerts"
        })

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)

      expect(Slack, :send_flaky_test_alert, fn p, tc, count, auto_quarantined ->
        assert p.id == project.id
        assert tc.id == test_case.id
        assert count == 3
        assert auto_quarantined == false
        :ok
      end)

      # When
      result =
        FlakyTestAlertWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id, "flaky_runs_count" => 3}
        })

      # Then
      assert result == :ok
    end

    test "passes auto_quarantined flag to alert", %{project: project} do
      # Given
      {:ok, project} =
        Tuist.Projects.update_project(project, %{
          flaky_test_alerts_enabled: true,
          flaky_test_alerts_slack_channel_id: "C12345",
          flaky_test_alerts_slack_channel_name: "alerts"
        })

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)

      expect(Slack, :send_flaky_test_alert, fn _p, _tc, _count, auto_quarantined ->
        assert auto_quarantined == true
        :ok
      end)

      # When
      result =
        FlakyTestAlertWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id, "auto_quarantined" => true, "flaky_runs_count" => 3}
        })

      # Then
      assert result == :ok
    end

    test "does not send alert when flaky_test_alerts_enabled is false", %{project: project} do
      # Given
      {:ok, project} =
        Tuist.Projects.update_project(project, %{
          flaky_test_alerts_enabled: false,
          flaky_test_alerts_slack_channel_id: "C12345",
          flaky_test_alerts_slack_channel_name: "alerts"
        })

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)

      reject(&Slack.send_flaky_test_alert/4)

      # When
      result =
        FlakyTestAlertWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id, "flaky_runs_count" => 3}
        })

      # Then
      assert result == :ok
    end

    test "does not send alert when channel is not configured", %{project: project} do
      # Given
      {:ok, project} =
        Tuist.Projects.update_project(project, %{
          flaky_test_alerts_enabled: true,
          flaky_test_alerts_slack_channel_id: nil,
          flaky_test_alerts_slack_channel_name: nil
        })

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)

      reject(&Slack.send_flaky_test_alert/4)

      # When
      result =
        FlakyTestAlertWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id, "flaky_runs_count" => 3}
        })

      # Then
      assert result == :ok
    end

    test "does not send alert when no slack installation" do
      # Given - create a project without slack installation
      other_user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(account_id: other_user.account.id)

      {:ok, project} =
        Tuist.Projects.update_project(project, %{
          flaky_test_alerts_enabled: true,
          flaky_test_alerts_slack_channel_id: "C12345",
          flaky_test_alerts_slack_channel_name: "alerts"
        })

      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true)

      stub(Runs, :get_test_case_by_id, fn _id -> {:ok, test_case} end)

      reject(&Slack.send_flaky_test_alert/4)

      # When
      result =
        FlakyTestAlertWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case.id, "project_id" => project.id, "flaky_runs_count" => 3}
        })

      # Then
      assert result == :ok
    end

    test "returns error tuple when test case is not found", %{project: project} do
      # Given
      test_case_id = Ecto.UUID.generate()

      stub(Runs, :get_test_case_by_id, fn _id -> {:error, :not_found} end)

      reject(&Slack.send_flaky_test_alert/4)

      # When
      result =
        FlakyTestAlertWorker.perform(%Oban.Job{
          args: %{"test_case_id" => test_case_id, "project_id" => project.id, "flaky_runs_count" => 3}
        })

      # Then
      assert result == {:error, :not_found}
    end
  end
end
