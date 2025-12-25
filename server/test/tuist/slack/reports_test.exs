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
    test "generates Slack blocks with correct structure", %{project: project, account: account} do
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

      blocks = Reports.report(project)

      assert is_list(blocks)
      assert length(blocks) > 0

      header_block = Enum.find(blocks, fn block -> block.type == "header" end)
      assert header_block
      assert String.contains?(header_block.text.text, project.name)
      assert String.contains?(header_block.text.text, "Daily")
    end

    test "uses last_report_at when provided", %{project: project, account: account} do
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

      blocks = Reports.report(project, last_report_at: last_report_at)

      assert is_list(blocks)
      header_block = Enum.find(blocks, fn block -> block.type == "header" end)
      assert header_block
      assert String.contains?(header_block.text.text, project.name)
    end
  end
end
