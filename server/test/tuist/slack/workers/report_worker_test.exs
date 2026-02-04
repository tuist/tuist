defmodule Tuist.Slack.Workers.ReportWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Builds.Analytics, as: BuildsAnalytics
  alias Tuist.Projects
  alias Tuist.Slack.Client
  alias Tuist.Slack.Workers.ReportWorker
  alias Tuist.Tests.Analytics, as: TestsAnalytics
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.SlackFixtures

  setup do
    user = %{account: account} = AccountsFixtures.user_fixture(preload: [:account])
    slack_installation = SlackFixtures.slack_installation_fixture(account_id: account.id)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{user: user, project: project, account: account, slack_installation: slack_installation}
  end

  describe "perform/1" do
    test "sends reports for projects with matching schedule", %{project: project, slack_installation: slack_installation} do
      now = ~U[2025-01-15 09:00:00Z]
      day_of_week = Date.day_of_week(~D[2025-01-15])

      {:ok, _project} =
        Projects.update_project(project, %{
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel",
          report_frequency: :daily,
          report_days_of_week: [day_of_week],
          report_schedule_time: now,
          report_timezone: "Etc/UTC"
        })

      stub(DateTime, :utc_now, fn -> now end)

      stub(BuildsAnalytics, :build_duration_analytics, fn _project_id, _opts ->
        %{total_average_duration: 1000, trend: nil}
      end)

      stub(TestsAnalytics, :test_run_duration_analytics, fn _project_id, _opts ->
        %{total_average_duration: 500, trend: nil}
      end)

      stub(Tuist.Cache.Analytics, :cache_hit_rate_analytics, fn _opts ->
        %{cache_hit_rate: 0.8, trend: nil}
      end)

      stub(BuildsAnalytics, :selective_testing_analytics, fn _opts ->
        %{hit_rate: 0, trend: nil}
      end)

      stub(Tuist.Bundles, :last_project_bundle, fn _project, _opts ->
        nil
      end)

      expect(Client, :post_message, fn access_token, channel_id, blocks ->
        assert access_token == slack_installation.access_token
        assert channel_id == "C123456"
        assert is_list(blocks)
        :ok
      end)

      Oban.Testing.with_testing_mode(:inline, fn ->
        assert :ok = ReportWorker.perform(%Oban.Job{args: %{}})
      end)
    end

    test "does not send reports for projects with the report disabled", %{project: project} do
      now = ~U[2025-01-15 09:00:00Z]

      {:ok, _project} =
        Projects.update_project(project, %{
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel",
          report_frequency: :never,
          report_days_of_week: [3],
          report_schedule_time: now,
          report_timezone: "Etc/UTC"
        })

      stub(DateTime, :utc_now, fn -> now end)

      reject(&Client.post_message/3)

      assert :ok = ReportWorker.perform(%Oban.Job{args: %{}})
    end

    test "does not send reports when day of week does not match", %{project: project} do
      now = ~U[2025-01-15 09:00:00Z]
      day_of_week = Date.day_of_week(~D[2025-01-15])
      different_day = rem(day_of_week, 7) + 1

      {:ok, _project} =
        Projects.update_project(project, %{
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel",
          report_frequency: :daily,
          report_days_of_week: [different_day],
          report_schedule_time: now,
          report_timezone: "Etc/UTC"
        })

      stub(DateTime, :utc_now, fn -> now end)

      reject(&Client.post_message/3)

      assert :ok = ReportWorker.perform(%Oban.Job{args: %{}})
    end

    test "does not send reports when hour does not match", %{project: project} do
      now = ~U[2025-01-15 09:00:00Z]
      day_of_week = Date.day_of_week(~D[2025-01-15])
      different_hour = DateTime.add(now, 1, :hour)

      {:ok, _project} =
        Projects.update_project(project, %{
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel",
          report_frequency: :daily,
          report_days_of_week: [day_of_week],
          report_schedule_time: different_hour,
          report_timezone: "Etc/UTC"
        })

      stub(DateTime, :utc_now, fn -> now end)

      reject(&Client.post_message/3)

      assert :ok = ReportWorker.perform(%Oban.Job{args: %{}})
    end

    test "does not send reports when no slack channel is configured", %{project: project} do
      now = ~U[2025-01-15 09:00:00Z]
      day_of_week = Date.day_of_week(~D[2025-01-15])

      {:ok, _project} =
        Projects.update_project(project, %{
          slack_channel_id: nil,
          report_frequency: :daily,
          report_days_of_week: [day_of_week],
          report_schedule_time: now,
          report_timezone: "Etc/UTC"
        })

      stub(DateTime, :utc_now, fn -> now end)

      reject(&Client.post_message/3)

      assert :ok = ReportWorker.perform(%Oban.Job{args: %{}})
    end

    test "does not send reports when project has a nil timezone", %{project: project} do
      now = ~U[2025-01-15 09:00:00Z]
      day_of_week = Date.day_of_week(~D[2025-01-15])

      {:ok, _project} =
        Projects.update_project(project, %{
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel",
          report_frequency: :daily,
          report_days_of_week: [day_of_week],
          report_schedule_time: now,
          report_timezone: nil
        })

      stub(DateTime, :utc_now, fn -> now end)

      reject(&Client.post_message/3)

      assert :ok = ReportWorker.perform(%Oban.Job{args: %{}})
    end
  end
end
