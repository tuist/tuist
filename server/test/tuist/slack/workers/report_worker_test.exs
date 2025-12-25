defmodule Tuist.Slack.Workers.ReportWorkerTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Projects
  alias Tuist.Slack.Client
  alias Tuist.Slack.Workers.ReportWorker
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
          slack_report_frequency: :daily,
          slack_report_days_of_week: [day_of_week],
          slack_report_schedule_time: now,
          slack_report_timezone: "Etc/UTC"
        })

      stub(DateTime, :utc_now, fn -> now end)

      stub(Tuist.CommandEvents, :run_average_duration, fn _project_id, _start, _end, _opts ->
        1000
      end)

      stub(Tuist.CommandEvents, :cache_hit_rate, fn _project_id, _start, _end, _opts ->
        %{cacheable_targets_count: 100, local_cache_hits_count: 40, remote_cache_hits_count: 40}
      end)

      stub(Tuist.CommandEvents, :selective_testing_hit_rate, fn _project_id, _start, _end, _opts ->
        nil
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

      assert :ok = ReportWorker.perform(%Oban.Job{args: %{}})
    end

    test "does not send reports for disabled projects", %{project: project} do
      now = ~U[2025-01-15 09:00:00Z]

      {:ok, _project} =
        Projects.update_project(project, %{
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel",
          slack_report_frequency: :never,
          slack_report_days_of_week: [3],
          slack_report_schedule_time: now,
          slack_report_timezone: "Etc/UTC"
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
          slack_report_frequency: :daily,
          slack_report_days_of_week: [different_day],
          slack_report_schedule_time: now,
          slack_report_timezone: "Etc/UTC"
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
          slack_report_frequency: :daily,
          slack_report_days_of_week: [day_of_week],
          slack_report_schedule_time: different_hour,
          slack_report_timezone: "Etc/UTC"
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
          slack_report_frequency: :daily,
          slack_report_days_of_week: [day_of_week],
          slack_report_schedule_time: now,
          slack_report_timezone: "Etc/UTC"
        })

      stub(DateTime, :utc_now, fn -> now end)

      reject(&Client.post_message/3)

      assert :ok = ReportWorker.perform(%Oban.Job{args: %{}})
    end
  end
end
