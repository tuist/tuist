defmodule Tuist.Slack.ReportsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Cache.Analytics
  alias Tuist.Slack.Reports
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    user = %{account: account} = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{user: user, project: project, account: account}
  end

  describe "report/1" do
    test "returns report with all metric blocks", %{project: project, account: account} do
      now = ~U[2025-01-15 10:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      {:ok, _build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: account.id,
          duration: 1500,
          is_ci: false,
          inserted_at: DateTime.add(now, -12, :hour)
        )

      {:ok, _test} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: account.id,
          duration: 2000,
          is_ci: false,
          ran_at: DateTime.add(now, -12, :hour)
        )

      _event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "cache",
          cacheable_targets: ["Target1", "Target2", "Target3"],
          local_cache_target_hits: ["Target1"],
          remote_cache_target_hits: ["Target2"],
          created_at: DateTime.add(now, -12, :hour)
        )

      assert [
               %{type: "header", text: %{type: "plain_text", text: "Daily " <> _}},
               %{type: "context", elements: [%{type: "mrkdwn", text: period}]},
               %{type: "divider"},
               %{type: "section", text: %{type: "mrkdwn", text: ":hammer_and_wrench: *Build Duration*\n" <> _}},
               %{type: "section", text: %{type: "mrkdwn", text: ":test_tube: *Test Duration*\n" <> _}},
               %{type: "section", text: %{type: "mrkdwn", text: ":zap: *Cache Hit Rate*\n" <> _}},
               %{type: "context", elements: [%{type: "mrkdwn", text: "<" <> _}]}
             ] = Reports.report(project)

      assert String.contains?(period, "<!date^")
    end

    test "returns no data block when no metrics available", %{project: project} do
      now = ~U[2025-01-15 10:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      assert [
               %{type: "header", text: %{type: "plain_text", text: "Daily " <> _}},
               %{type: "context", elements: [%{type: "mrkdwn"}]},
               %{type: "divider"},
               %{type: "section", text: %{type: "mrkdwn", text: "No analytics data available for this period."}},
               %{type: "context", elements: [%{type: "mrkdwn"}]}
             ] = Reports.report(project)
    end

    test "uses last_report_at for date range", %{project: project, account: account} do
      now = ~U[2025-01-15 10:00:00Z]
      last_report_at = ~U[2025-01-14 10:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      {:ok, _build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: account.id,
          duration: 2000,
          is_ci: true,
          inserted_at: DateTime.add(now, -12, :hour)
        )

      assert [
               %{type: "header"},
               %{type: "context", elements: [%{type: "mrkdwn", text: period}]},
               %{type: "divider"},
               %{type: "section", text: %{type: "mrkdwn", text: ":hammer_and_wrench: *Build Duration*\n" <> _}},
               %{type: "context"}
             ] = Reports.report(project, last_report_at: last_report_at)

      assert String.contains?(period, "<!date^#{DateTime.to_unix(last_report_at)}^")
    end

    test "shows bundle size comparison with previous period and includes links", %{project: project} do
      now = ~U[2025-01-15 10:00:00Z]
      period_start = DateTime.add(now, -1, :day)
      stub(DateTime, :utc_now, fn -> now end)

      current_bundle = %{id: "current-bundle-id", install_size: 50_000_000, inserted_at: ~U[2025-01-15 08:00:00Z]}
      previous_bundle = %{id: "previous-bundle-id", install_size: 48_000_000, inserted_at: ~U[2025-01-13 12:00:00Z]}

      stub(Analytics, :cache_hit_rate_analytics, fn _opts ->
        %{cache_hit_rate: 0, trend: nil}
      end)

      stub(Tuist.Runs.Analytics, :selective_testing_analytics, fn _opts ->
        %{hit_rate: 0, trend: nil}
      end)

      stub(Tuist.Runs.Analytics, :build_duration_analytics, fn _project_id, _opts ->
        %{total_average_duration: 0, trend: nil}
      end)

      stub(Tuist.Runs.Analytics, :test_run_duration_analytics, fn _project_id, _opts ->
        %{total_average_duration: 0, trend: nil}
      end)

      stub(Tuist.Bundles, :last_project_bundle, fn _project, opts ->
        inserted_before = Keyword.get(opts, :inserted_before)

        if is_nil(inserted_before) do
          current_bundle
        else
          if DateTime.compare(inserted_before, period_start) == :eq do
            previous_bundle
          end
        end
      end)

      stub(Tuist.Bundles, :install_size_deviation, fn _bundle -> 0.05 end)

      report = Reports.report(project)

      bundle_section =
        Enum.find(report, fn block ->
          match?(%{type: "section", text: %{text: ":package: *Bundle Size*" <> _}}, block)
        end)

      assert bundle_section
      %{text: %{text: bundle_text}} = bundle_section

      assert String.contains?(bundle_text, "50.0 MB")
      assert String.contains?(bundle_text, "+2.0 MB")
      assert String.contains?(bundle_text, "current-bundle-id|")
      assert String.contains?(bundle_text, "previous-bundle-id|previous period>")

      # Check that context block shows both current and previous periods
      context_block = Enum.at(report, 1)
      assert context_block.type == "context"
      [%{text: context_text}] = context_block.elements

      current_start_ts = DateTime.to_unix(period_start)
      current_end_ts = DateTime.to_unix(now)
      # Previous period: Jan 13 10:00 - Jan 14 10:00
      previous_start_ts = DateTime.to_unix(DateTime.add(period_start, -1, :day))
      previous_end_ts = DateTime.to_unix(period_start)

      assert String.contains?(context_text, "<!date^#{current_start_ts}^")
      assert String.contains?(context_text, "<!date^#{current_end_ts}^")
      assert String.contains?(context_text, "<!date^#{previous_start_ts}^")
      assert String.contains?(context_text, "<!date^#{previous_end_ts}^")
    end

    test "hides Overall duration when only CI or Local data exists", %{project: project} do
      now = ~U[2025-01-15 10:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      stub(Analytics, :cache_hit_rate_analytics, fn _opts ->
        %{cache_hit_rate: 0, trend: nil}
      end)

      stub(Tuist.Runs.Analytics, :selective_testing_analytics, fn _opts ->
        %{hit_rate: 0, trend: nil}
      end)

      stub(Tuist.Runs.Analytics, :build_duration_analytics, fn _project_id, opts ->
        case Keyword.get(opts, :is_ci) do
          true -> %{total_average_duration: 5000, trend: nil}
          false -> %{total_average_duration: 0, trend: nil}
          nil -> %{total_average_duration: 5000, trend: nil}
        end
      end)

      stub(Tuist.Runs.Analytics, :test_run_duration_analytics, fn _project_id, opts ->
        case Keyword.get(opts, :is_ci) do
          true -> %{total_average_duration: 210_000, trend: nil}
          false -> %{total_average_duration: 0, trend: nil}
          nil -> %{total_average_duration: 210_000, trend: nil}
        end
      end)

      stub(Tuist.Bundles, :last_project_bundle, fn _project, _opts -> nil end)

      report = Reports.report(project)

      build_section =
        Enum.find(report, fn block ->
          match?(%{type: "section", text: %{text: ":hammer_and_wrench: *Build Duration*" <> _}}, block)
        end)

      test_section =
        Enum.find(report, fn block ->
          match?(%{type: "section", text: %{text: ":test_tube: *Test Duration*" <> _}}, block)
        end)

      assert build_section
      assert test_section

      %{text: %{text: build_text}} = build_section
      %{text: %{text: test_text}} = test_section

      refute String.contains?(build_text, "Overall")
      assert String.contains?(build_text, "CI:")

      refute String.contains?(test_text, "Overall")
      assert String.contains?(test_text, "CI:")
    end

    test "rounds trend percentage values to avoid floating-point precision issues", %{project: project} do
      now = ~U[2025-01-15 10:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      stub(Analytics, :cache_hit_rate_analytics, fn _opts ->
        %{cache_hit_rate: 0.996, trend: -0.4000000000000057}
      end)

      stub(Tuist.Runs.Analytics, :selective_testing_analytics, fn _opts ->
        %{hit_rate: 0, trend: nil}
      end)

      stub(Tuist.Runs.Analytics, :build_duration_analytics, fn _project_id, _opts ->
        %{total_average_duration: 0, trend: nil}
      end)

      stub(Tuist.Runs.Analytics, :test_run_duration_analytics, fn _project_id, _opts ->
        %{total_average_duration: 0, trend: nil}
      end)

      stub(Tuist.Bundles, :last_project_bundle, fn _project, _opts -> nil end)

      report = Reports.report(project)

      cache_section =
        Enum.find(report, fn block ->
          match?(%{type: "section", text: %{text: ":zap: *Cache Hit Rate*" <> _}}, block)
        end)

      assert cache_section
      %{text: %{text: cache_text}} = cache_section
      assert cache_text == ":zap: *Cache Hit Rate*\n99.6% (-0.4% :chart_with_downwards_trend:)"
    end
  end
end
