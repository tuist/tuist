defmodule TuistWeb.OnceRunLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Projector

  setup %{project: project, organization: organization} do
    project = project |> Ecto.Changeset.change(build_system: :once) |> Tuist.Repo.update!()

    {:ok, run} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: UUIDv7.generate(),
        kind: "build",
        command_display: "once -C ⟨opaque⟩ --format ⟨opaque⟩ build ⟨opaque⟩"
      })

    for index <- 0..59 do
      action(run, index)
    end

    %{run: run, path: "/#{organization.account.name}/#{project.name}/once/runs/#{run.run_id}"}
  end

  test "search, filters and sorting preserve each other across pages and live updates", %{
    conn: conn,
    path: path,
    run: run
  } do
    {:ok, view, _} = live(conn, path <> "?page=2&sort_by=duration&sort_order=desc")
    assert has_element?(view, "h1", "Once build")
    refute has_element?(view, "h1", "opaque")
    assert has_element?(view, "[data-part=command-note]", "redacted by Once")
    assert row_count(view) == 10

    view |> form("#once-actions-search-form", %{search: "compiler"}) |> render_change()
    assert has_element?(view, "#once-actions-table tbody tr:first-child", "compiler-59")
    assert row_count(view) == 50

    view |> element("#once-actions-table th a", "Duration") |> render_click()
    assert has_element?(view, "#once-actions-table tbody tr:first-child", "compiler-0")

    render_click(view, "add_filter", %{"value" => "cache"})
    render_click(view, "update_filter", %{"type" => "change_value", "payload_filter_id" => "cache", "value" => "miss"})
    assert row_count(view) == 30
    assert has_element?(view, "#once-actions-table tbody tr:first-child", "compiler-1")

    action(run, 61)

    # Broadcasts coalesce to one refresh a second, so the update is driven
    # here rather than waiting on the timer.
    send(view.pid, :refresh)
    assert row_count(view) == 31

    view |> form("#once-actions-search-form", %{search: "missing"}) |> render_change()
    assert has_element?(view, "#once-run", "No actions match your search or filters")
    assert has_element?(view, "#once-actions-search")
  end

  test "page links retain table settings and excessive pages clamp to the filtered count", %{conn: conn, path: path} do
    {:ok, view, _} =
      live(
        conn,
        path <> "?search=compiler&sort_by=duration&sort_order=desc&filter_result_op=%3D%3D&filter_result_val=succeeded"
      )

    link =
      view
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("[data-part=once-actions-table] .noora-pagination-group a")
      |> Enum.map(&Floki.attribute(&1, "href"))
      |> List.flatten()
      |> Enum.find(&String.contains?(&1, "page=2"))

    assert link
    query = link |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["search"] == "compiler"
    assert query["sort_order"] == "desc"
    assert query["filter_result_val"] == "succeeded"
    render_patch(view, path <> link)
    assert row_count(view) == 10
    assert has_element?(view, "#once-actions-table tbody tr:first-child", "compiler-9")
    render_patch(view, path <> "?page=999&search=compiler-59")
    assert row_count(view) == 1
  end

  defp row_count(view),
    do: view |> render() |> Floki.parse_fragment!() |> Floki.find("#once-actions-table tbody tr") |> length()

  defp action(run, index) do
    Projector.project(
      %Once.Events.V1.RunEvent{
        epoch_ms: 1_789_405_000_000,
        payload:
          {:action_completed,
           %Once.Events.V1.ActionCompleted{
             target_execution_id: "target-#{index}",
             capability: "build",
             action_index: 0,
             identifier: "compiler-#{index}",
             result: :TARGET_RESULT_SUCCEEDED,
             duration_ms: index,
             was_cached: rem(index, 2) == 0
           }}
      },
      run.project_id,
      run.run_id
    )
  end
end
