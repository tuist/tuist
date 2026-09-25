defmodule TuistWeb.TestRunsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runs.Analytics, as: RunsAnalytics
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "lists latest test runs" do
    setup do
      copy(RunsAnalytics)
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

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

    test "shows the run count chart for an analytics widget it does not know", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, _test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: organization.account.id,
          ran_at: ~N[2024-04-30 10:19:30]
        )

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-runs?analytics-selected-widget=coverage"
        )

      render_async(lv)

      assert has_element?(lv, "#test-runs-analytics-chart")
    end

    test "lists Bazel invocations using the shared test runs page", %{
      conn: conn,
      organization: organization
    } do
      project = ProjectsFixtures.project_fixture(account: organization.account, build_system: :bazel)

      {:ok, _test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: organization.account.id,
          build_system: "bazel",
          scheme: "//app:unit_tests",
          ran_at: ~N[2024-04-30 10:19:30]
        )

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs")

      assert has_element?(lv, "#test-runs-table", "Invocation")
      assert has_element?(lv, "#test-runs-table", "bazel test //app:unit_tests")
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

    test "loads with an unknown analytics-environment value", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, _test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: organization.account.id,
          scheme: "App",
          ran_at: ~N[2024-04-30 10:19:30]
        )

      # A request with an empty or unexpected analytics-environment value should
      # not crash analytics_environment_label/1 with a FunctionClauseError.
      assert {:ok, lv, _html} =
               live(
                 conn,
                 ~p"/#{organization.account.name}/#{project.name}/tests/test-runs?analytics-environment="
               )

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
  end

  describe "code coverage" do
    @render_async_timeout 1000

    defp coverage_run(project, organization, scheme, opts) do
      lines = Keyword.fetch!(opts, :lines)

      {:ok, test_run} =
        Tuist.Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: organization.account.id,
          duration: 1000,
          status: "success",
          scheme: scheme,
          git_branch: "main",
          git_commit_sha: "abc123",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60, :second),
          is_ci: true,
          test_modules: [],
          xcode_coverage: %{
            partial: Keyword.get(opts, :partial, false),
            files: [
              %{
                path: "Sources/Add.swift",
                git_blob_id: "abc",
                targets: ["Calculator"],
                covered_lines: Enum.count(lines, &(&1 > 0)),
                executable_lines: length(lines),
                line_numbers: Enum.to_list(1..length(lines)),
                execution_counts: lines,
                functions: []
              }
            ]
          }
        })

      test_run
    end

    test "leaves coverage out of the table", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      coverage_run(project, organization, "SchemeFull", lines: [1, 1, 1, 0])

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs")

      render_async(lv, @render_async_timeout)

      refute has_element?(lv, "#widget-coverage")
      table = lv |> element("#test-runs-table") |> render()
      assert table =~ "SchemeFull"
      refute table =~ "75.0%"
    end

    test "offers no coverage filter, and ignores one a bookmarked address still names", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      coverage_run(project, organization, "SchemeFull", lines: [1, 1, 1, 0])
      coverage_run(project, organization, "SchemePartial", lines: [1, 0, 0, 0], partial: true)

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs")

      render_async(lv, @render_async_timeout)
      refute render(lv) =~ "filter_coverage"

      table =
        conn
        |> live_table(organization, project, %{"filter_coverage_op" => "==", "filter_coverage_val" => "full"})
        |> render()

      assert table =~ "SchemeFull"
      assert table =~ "SchemePartial"
    end

    defp live_table(conn, organization, project, filters) do
      {:ok, lv, _html} =
        live(
          conn,
          "/#{organization.account.name}/#{project.name}/tests/test-runs?#{URI.encode_query(filters)}"
        )

      render_async(lv, @render_async_timeout)
      element(lv, "#test-runs-table")
    end
  end
end
