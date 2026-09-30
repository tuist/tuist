defmodule TuistWeb.OnceTestRunLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Projector

  @case_count 45

  setup %{project: project, organization: organization} do
    project = project |> Ecto.Changeset.change(build_system: :once) |> Tuist.Repo.update!()

    {:ok, run} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: UUIDv7.generate(),
        kind: "test",
        command_display: "once test"
      })

    suite(run)
    for index <- 1..@case_count, do: test_case(run, index)

    %{
      run: run,
      path: "/#{organization.account.name}/#{project.name}/once/test-runs/#{run.run_id}"
    }
  end

  test "the test case table is paged and failures lead", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path)

    assert row_count(view) == 20
    # Failures sort ahead of passes, so the first page leads with them.
    assert has_element?(view, "#once-test-cases-table tbody tr:first-child", "case-15")
    refute has_element?(view, "#once-test-cases-table", "case-9")

    render_patch(view, path <> "?test-cases-page=3")

    assert row_count(view) == 5
  end

  test "the test targets tab lists the suite", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path <> "?tab=test-targets")

    assert has_element?(view, "#once-test-targets-table", "unit")
  end

  defp row_count(view),
    do: view |> render() |> Floki.parse_fragment!() |> Floki.find("#once-test-cases-table tbody tr") |> length()

  defp suite(run) do
    project_event(
      run,
      {:test_suite_started, %Once.Events.V1.TestSuiteStarted{target_execution_id: "mise", suite_id: "unit"}}
    )
  end

  defp test_case(run, index) do
    result = if rem(index, 15) == 0, do: :TEST_CASE_RESULT_FAILED, else: :TEST_CASE_RESULT_PASSED

    project_event(
      run,
      {:test_case_completed,
       %Once.Events.V1.TestCaseCompleted{
         case_id: "tests::case-#{index}",
         name: "case-#{index}",
         suite_id: "unit",
         result: result,
         duration_ms: index
       }}
    )
  end

  defp project_event(run, payload) do
    Projector.project(
      %Once.Events.V1.RunEvent{epoch_ms: 1_789_405_000_000, payload: payload},
      run.project_id,
      run.run_id
    )
  end
end
