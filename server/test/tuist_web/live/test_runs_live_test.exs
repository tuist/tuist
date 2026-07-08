defmodule TuistWeb.TestRunsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runners.Jobs
  alias Tuist.Runs.Analytics, as: RunsAnalytics
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "lists latest test runs" do
    setup do
      copy(RunsAnalytics)
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30.000000Z] end)

      stub(RunsAnalytics, :runs_analytics, fn _, _, _ ->
        %{runs_per_period: %{}, dates: [], values: [], count: 0, trend: 0}
      end)

      stub(RunsAnalytics, :runs_duration_analytics, fn _, _ ->
        %{dates: [], values: [], total_average_duration: 0, trend: 0}
      end)

      :ok
    end

    test "lists latest test runs", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      ran_at = ~N[2024-04-30 10:19:30]

      {:ok, _test_run1} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: organization.account.id,
          scheme: "App",
          ran_at: ran_at
        )

      {:ok, _test_run2} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: organization.account.id,
          scheme: "AppTwo",
          ran_at: ran_at
        )

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs")

      # Then
      assert has_element?(lv, "[data-part='test-runs-table']")
    end

    test "handles cursor from another page with different sort fields", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      ran_at = ~N[2024-04-30 10:20:00]

      for i <- 1..25 do
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: organization.account.id,
          scheme: "App-#{i}",
          duration: i * 1000,
          ran_at: ran_at
        )
      end

      # Generate a cursor with duration sorting (simulating a cursor from another page like bundles)
      {_test_runs, %{end_cursor: cursor}} =
        Tuist.Tests.list_test_runs(%{
          filters: [
            %{field: :project_id, op: :==, value: project.id}
          ],
          order_by: [:duration],
          order_directions: [:desc],
          first: 20
        })

      # Navigate to test runs with a cursor that encodes duration field
      # Test runs always sorts by created_at, so this cursor is incompatible
      # Before the fix, this would raise Flop.InvalidParamsError
      assert {:ok, lv, _html} =
               live(
                 conn,
                 ~p"/#{organization.account.name}/#{project.name}/tests/test-runs?after=#{cursor}"
               )

      # The cursor is cleared on initial load, so the page should load without error
      assert has_element?(lv, "[data-part='test-runs-table']")
    end

    test "filters runs whose branch does not contain a substring", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      ran_at = ~N[2024-04-30 10:19:30]

      {:ok, _queue_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: organization.account.id,
          scheme: "Queued",
          git_branch: "feature/gh-readonly-queue/main",
          ran_at: ran_at
        )

      {:ok, _regular_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: organization.account.id,
          scheme: "Regular",
          git_branch: "feature/main",
          ran_at: ran_at
        )

      query =
        URI.encode_query(%{
          "filter_git_branch_op" => "!=~",
          "filter_git_branch_val" => "gh-readonly-queue"
        })

      {:ok, lv, html} =
        live(
          conn,
          "/#{organization.account.name}/#{project.name}/tests/test-runs?#{query}"
        )

      assert has_element?(lv, "[data-part='test-runs-table']")
      assert html =~ "does not contain"
      assert html =~ "Regular"
      refute html =~ "Queued"
    end

    test "filters test runs by runner platform", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      ran_at = ~N[2024-04-30 10:19:30]
      enqueued_at = ~U[2024-04-30 10:20:30.000000Z]

      :ok =
        Jobs.enqueue(%{
          workflow_job_id: 41_101,
          account_id: organization.account.id,
          fleet_name: "macos-xcode-26.4",
          repository: "tuist/tuist",
          workflow_run_id: 411_010,
          workflow_name: "Server",
          run_attempt: 1,
          job_name: "Test",
          head_branch: "main",
          head_sha: "abc",
          enqueued_at: enqueued_at
        })

      :ok =
        Jobs.enqueue(%{
          workflow_job_id: 41_102,
          account_id: organization.account.id,
          fleet_name: "linux-amd64",
          repository: "tuist/tuist",
          workflow_run_id: 411_020,
          workflow_name: "Server",
          run_attempt: 1,
          job_name: "Test",
          head_branch: "main",
          head_sha: "def",
          enqueued_at: enqueued_at
        })

      {:ok, _mac_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: organization.account.id,
          scheme: "RunnerMacTests",
          ran_at: ran_at,
          ci_provider: "github",
          ci_project_handle: "tuist/tuist",
          ci_run_id: "411010"
        )

      {:ok, _linux_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: organization.account.id,
          scheme: "RunnerLinuxTests",
          ran_at: ran_at,
          ci_provider: "github",
          ci_project_handle: "tuist/tuist",
          ci_run_id: "411020"
        )

      query =
        URI.encode_query(%{
          "filter_runner_platform_op" => "==",
          "filter_runner_platform_val" => "macos"
        })

      {:ok, lv, _html} =
        live(conn, "/#{organization.account.name}/#{project.name}/tests/test-runs?#{query}")

      assert has_element?(lv, "[data-part='test-runs-table']", "RunnerMacTests")
      refute has_element?(lv, "[data-part='test-runs-table']", "RunnerLinuxTests")
    end
  end
end
