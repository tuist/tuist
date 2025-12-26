defmodule Tuist.Slack.ReportsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

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
  end
end
