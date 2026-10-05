defmodule TuistWeb.OnceTestsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.OnceEvents

  setup %{project: project, organization: organization} do
    project = project |> Ecto.Changeset.change(build_system: :once) |> Tuist.Repo.update!()

    # Two finished test runs, one of them failing. Backdated because the
    # default analytics window ends on a whole second, so a run started in
    # the current second sorts after it.
    started_at = DateTime.add(DateTime.utc_now(), -3600, :second)

    run(project, started_at, 0)
    run(project, started_at, 1)

    %{path: "/#{organization.account.name}/#{project.name}/once/tests"}
  end

  test "switching the metric recomputes the chart instead of relabelling the old series", %{
    conn: conn,
    path: path
  } do
    {:ok, view, _} = live(conn, path)
    render_async(view, 2_000)

    # Default widget counts every run: two.
    assert series_total(view, "test-run-count-chart") == 2

    render_click(view, "select_widget", %{"widget" => "failed_test_run_count"})

    # Only one run failed. Before the fix this still totalled 2, because the
    # run-count series stayed in `analytics_chart_data` under the failure
    # label: only `handle_params/3` rebuilt it, and selecting a widget
    # replaces the URL without re-running it.
    assert series_total(view, "failed-test-run-count-chart") == 1
  end

  defp run(project, started_at, exit_status) do
    {:ok, run} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: UUIDv7.generate(),
        kind: "test",
        command_display: "once test",
        started_at: started_at
      })

    {:ok, _} =
      OnceEvents.finalize_run(run, %{
        finalization: "finalized",
        exit_status: exit_status,
        wall_ms: 1000,
        finalized_at: started_at
      })
  end

  # Noora renders the ECharts option as JSON in a hidden `[data-part=data]`
  # child of the chart container. Each series holds `[[date, value], ...]`.
  defp series_total(view, chart_id) do
    view
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("##{chart_id} [data-part=data]")
    |> Floki.text()
    |> case do
      "" -> flunk("no chart payload on ##{chart_id}")
      json -> json |> JSON.decode!() |> chart_values() |> Enum.sum()
    end
  end

  defp chart_values(%{"series" => series}) do
    Enum.flat_map(series, fn %{"data" => data} -> Enum.map(data, fn [_date, value] -> value end) end)
  end
end
