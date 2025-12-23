defmodule Tuist.Slack.ReportsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Slack.Reports
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = %{account: account} = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{user: user, project: project, account: account}
  end

  describe "generate_report/2" do
    test "generates a daily report with correct structure", %{project: project} do
      now = ~U[2025-01-15 10:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      stub(Tuist.CommandEvents, :run_average_duration, fn _project_id, _start, _end, _opts ->
        1500
      end)

      stub(Tuist.CommandEvents, :cache_hit_rate, fn _project_id, _start, _end, _opts ->
        0.85
      end)

      stub(Tuist.Bundles, :last_project_bundle, fn _project, _opts ->
        nil
      end)

      report = Reports.generate_report(project, :daily)

      assert report.project_name == project.name
      assert report.frequency == :daily
      assert is_binary(report.period)
      assert is_map(report.build_duration)
      assert is_map(report.test_duration)
      assert is_map(report.cache_hit_rate)
    end

    test "generates a weekly report with correct structure", %{project: project} do
      now = ~U[2025-01-15 10:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      stub(Tuist.CommandEvents, :run_average_duration, fn _project_id, _start, _end, _opts ->
        2000
      end)

      stub(Tuist.CommandEvents, :cache_hit_rate, fn _project_id, _start, _end, _opts ->
        0.75
      end)

      stub(Tuist.Bundles, :last_project_bundle, fn _project, _opts ->
        nil
      end)

      report = Reports.generate_report(project, :weekly)

      assert report.project_name == project.name
      assert report.frequency == :weekly
      assert is_binary(report.period)
    end
  end

  describe "format_report_blocks/1" do
    test "formats report as Slack Block Kit blocks", %{project: project} do
      report = %{
        project_name: project.name,
        frequency: :daily,
        period: "Jan 14 - Jan 15, 2025",
        build_duration: %{
          ci: %{current: 120_000, previous: 100_000, change_pct: 20.0},
          local: %{current: 60_000, previous: 65_000, change_pct: -7.7}
        },
        test_duration: %{
          ci: %{current: 240_000, previous: 220_000, change_pct: 9.1},
          local: %{current: 120_000, previous: 120_000, change_pct: 0.0}
        },
        cache_hit_rate: %{
          current: 0.85,
          previous: 0.80,
          change_pct: 6.25
        },
        bundle_size: nil
      }

      blocks = Reports.format_report_blocks(report)

      assert is_list(blocks)
      assert length(blocks) > 0

      header_block = Enum.find(blocks, fn block -> block.type == "header" end)
      assert header_block
      assert String.contains?(header_block.text.text, project.name)
      assert String.contains?(header_block.text.text, "Daily")
    end

    test "includes bundle size block when bundle data is present", %{project: project} do
      report = %{
        project_name: project.name,
        frequency: :weekly,
        period: "Jan 8 - Jan 15, 2025",
        build_duration: %{
          ci: %{current: nil, previous: nil, change_pct: nil},
          local: %{current: nil, previous: nil, change_pct: nil}
        },
        test_duration: %{
          ci: %{current: nil, previous: nil, change_pct: nil},
          local: %{current: nil, previous: nil, change_pct: nil}
        },
        cache_hit_rate: %{
          current: nil,
          previous: nil,
          change_pct: nil
        },
        bundle_size: %{
          current_size: 50_000_000,
          difference: 2_000_000,
          comparison_branch: "main",
          deviation_pct: 4.0
        }
      }

      blocks = Reports.format_report_blocks(report)

      bundle_block =
        Enum.find(blocks, fn block ->
          block.type == "section" and String.contains?(block.text.text, "Bundle Size")
        end)

      assert bundle_block
      assert String.contains?(bundle_block.text.text, "50.0 MB")
      assert String.contains?(bundle_block.text.text, "+2.0 MB")
    end
  end
end
