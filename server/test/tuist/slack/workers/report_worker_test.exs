defmodule Tuist.Slack.Workers.ReportWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Builds.Analytics, as: BuildsAnalytics
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Slack.Client
  alias Tuist.Slack.Installation
  alias Tuist.Slack.Workers.ReportWorker
  alias Tuist.Tests.Analytics, as: TestsAnalytics
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.SlackFixtures

  setup do
    unique_value = TuistTestSupport.Utilities.unique_integer(6)

    user =
      %{account: account} =
      AccountsFixtures.user_fixture(
        email: "#{unique_value}@tuist.io",
        handle: "account-#{unique_value}",
        preload: [:account]
      )

    slack_installation = SlackFixtures.slack_installation_fixture(account_id: account.id)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{user: user, project: project, account: account, slack_installation: slack_installation}
  end

  describe "perform/1" do
    test "deletes the slack installation when Slack returns account_inactive", %{
      project: project,
      slack_installation: slack_installation
    } do
      now = ~U[2025-01-15 09:00:00Z]

      {:ok, _project} =
        Projects.update_project(project, %{
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel",
          report_frequency: :daily,
          report_days_of_week: [Date.day_of_week(~D[2025-01-15])],
          report_schedule_time: now,
          report_timezone: "Etc/UTC"
        })

      stub_report_metrics(now)

      expect(Client, :post_message, fn access_token, channel_id, blocks ->
        assert access_token == slack_installation.access_token
        assert channel_id == "C123456"
        assert is_list(blocks)
        {:error, "account_inactive"}
      end)

      assert {:discard, :account_inactive} = ReportWorker.perform(%Oban.Job{args: %{"project_id" => project.id}})
      assert Repo.get(Installation, slack_installation.id) == nil

      updated_project = Projects.get_project_by_id(project.id)
      assert updated_project.slack_channel_id == nil
      assert updated_project.slack_channel_name == nil
    end

    test "marks account_inactive cleanup jobs as discarded", %{
      project: project,
      slack_installation: slack_installation
    } do
      now = ~U[2025-01-15 09:00:00Z]

      {:ok, _project} =
        Projects.update_project(project, %{
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel",
          report_frequency: :daily,
          report_days_of_week: [Date.day_of_week(~D[2025-01-15])],
          report_schedule_time: now,
          report_timezone: "Etc/UTC"
        })

      stub_report_metrics(now)

      expect(Client, :post_message, fn access_token, channel_id, blocks ->
        assert access_token == slack_installation.access_token
        assert channel_id == "C123456"
        assert is_list(blocks)
        {:error, "account_inactive"}
      end)

      {:ok, job} =
        %{project_id: project.id}
        |> ReportWorker.new()
        |> Oban.insert()

      Oban.drain_queue(queue: :default)

      persisted_job = Repo.get!(Oban.Job, job.id)

      assert persisted_job.state == "discarded"
      assert persisted_job.discarded_at
      assert persisted_job.completed_at == nil
    end

    test "does not advance the report window for discarded cleanup jobs", %{
      project: project,
      slack_installation: slack_installation
    } do
      previous_report_at = ~U[2025-01-14 09:00:00Z]
      discarded_at = ~U[2025-01-15 09:00:00Z]
      now = ~U[2025-01-16 09:00:00Z]

      {:ok, _project} =
        Projects.update_project(project, %{
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel",
          report_frequency: :daily,
          report_days_of_week: [Date.day_of_week(~D[2025-01-16])],
          report_schedule_time: now,
          report_timezone: "Etc/UTC"
        })

      insert_report_job(project.id,
        state: "completed",
        completed_at: previous_report_at,
        inserted_at: previous_report_at,
        scheduled_at: previous_report_at
      )

      insert_report_job(project.id,
        state: "discarded",
        discarded_at: discarded_at,
        inserted_at: discarded_at,
        scheduled_at: discarded_at
      )

      assert Repo.aggregate(Oban.Job, :count, :id) == 2

      stub_report_metrics(now)

      expect(Client, :post_message, fn access_token, channel_id, blocks ->
        assert access_token == slack_installation.access_token
        assert channel_id == "C123456"

        context_block = Enum.at(blocks, 1)

        assert hd(context_block.elements).text ==
                 report_period_text(previous_report_at, now)

        :ok
      end)

      assert :ok = ReportWorker.perform(%Oban.Job{args: %{"project_id" => project.id}})
    end

    test "returns an error when sending the report fails transiently", %{project: project} do
      now = ~U[2025-01-15 09:00:00Z]

      {:ok, _project} =
        Projects.update_project(project, %{
          slack_channel_id: "C123456",
          slack_channel_name: "test-channel",
          report_frequency: :daily,
          report_days_of_week: [Date.day_of_week(~D[2025-01-15])],
          report_schedule_time: now,
          report_timezone: "Etc/UTC"
        })

      stub_report_metrics(now)

      expect(Client, :post_message, fn _access_token, _channel_id, _blocks ->
        {:error, "timeout"}
      end)

      assert {:error, "timeout"} = ReportWorker.perform(%Oban.Job{args: %{"project_id" => project.id}})
    end

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

      stub_report_metrics(now)

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

  defp stub_report_metrics(now) do
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
  end

  defp insert_report_job(project_id, attrs) do
    Repo.insert!(%Oban.Job{
      state: Keyword.fetch!(attrs, :state),
      queue: "default",
      worker: to_string(Keyword.get(attrs, :worker, ReportWorker)),
      args: %{"project_id" => project_id},
      meta: %{},
      tags: [],
      errors: [],
      attempt: 0,
      max_attempts: 20,
      priority: 0,
      completed_at: truncate_datetime(Keyword.get(attrs, :completed_at)),
      discarded_at: truncate_datetime(Keyword.get(attrs, :discarded_at)),
      inserted_at: truncate_datetime(Keyword.fetch!(attrs, :inserted_at)),
      scheduled_at: truncate_datetime(Keyword.fetch!(attrs, :scheduled_at))
    })
  end

  defp truncate_datetime(nil), do: nil

  defp truncate_datetime(datetime) do
    %{DateTime.truncate(datetime, :microsecond) | microsecond: {elem(datetime.microsecond, 0), 6}}
  end

  defp report_period_text(current_period_start, current_period_end) do
    period_duration = DateTime.diff(current_period_end, current_period_start, :second)
    previous_period_start = DateTime.add(current_period_start, -period_duration, :second)

    "Report period: #{format_datetime(current_period_start)} - #{format_datetime(current_period_end)}\n" <>
      "Previous period: #{format_datetime(previous_period_start)} - #{format_datetime(current_period_start)}"
  end

  defp format_datetime(datetime) do
    timestamp = DateTime.to_unix(datetime)
    fallback = Calendar.strftime(datetime, "%b %d, %H:%M")
    "<!date^#{timestamp}^{date_short} {time}|#{fallback}>"
  end
end
