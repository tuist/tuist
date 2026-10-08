defmodule TuistWeb.OnceRunLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Once.Events.V1.ActionCompleted
  alias Once.Events.V1.RunEvent
  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Projector
  alias TuistTestSupport.Fixtures.ProjectsFixtures

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

  test "display names and source files appear in both action views with legacy fallbacks", %{
    conn: conn,
    path: path,
    run: run
  } do
    Projector.project(
      %RunEvent{
        epoch_ms: 1_789_405_000_000,
        payload:
          {:action_completed,
           %ActionCompleted{
             target_execution_id: "named-target",
             capability: "build",
             identifier: "diagnostic-identifier",
             presentation: %Once.Events.V1.ActionPresentation{
               package: %Once.Events.V1.ActionPackage{ecosystem: "custom", name: "library", version: "1.2"},
               platforms: [
                 %Once.Events.V1.ActionPlatform{
                   scheme: "custom",
                   id: "native-target",
                   label: "Target",
                   usage: "build-tool"
                 }
               ],
               context: [%Once.Events.V1.ActionContext{key: "custom.mode", value: "release", label: "<b>Release</b>"}]
             },
             display_name: "Compile main.c",
             source_files: ["src/main.c", "include/api.h"],
             result: :TARGET_RESULT_SUCCEEDED
           }}
      },
      run.project_id,
      run.run_id
    )

    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#once-actions-table", "Compile main.c")
    assert has_element?(view, "#once-actions-table", "compiler-0")
    assert has_element?(view, "#once-actions-table", "src/main.c")
    assert has_element?(view, "#once-actions-table", "include/api.h")

    {:ok, cache_view, _} = live(conn, path <> "/cache?cache_search=Compile+main.c")
    assert has_element?(cache_view, "#once-cache-table", "Compile main.c")
    assert has_element?(cache_view, "#once-cache-table", "src/main.c")

    for {action_view, table} <- [{view, "#once-actions-table"}, {cache_view, "#once-cache-table"}] do
      refute has_element?(action_view, "#{table} th", "Source files")
      assert has_element?(action_view, "#{table} [data-action-badges]", "1.2")
      assert has_element?(action_view, "#{table} [data-action-badges]", "Build tool · Target")
      assert has_element?(action_view, "#{table} summary", "+1")
      assert has_element?(action_view, "#{table} details[phx-mounted]", "native-target")
      assert has_element?(action_view, "#{table} [data-action-badges]", "library 1.2")
      assert has_element?(action_view, "#{table} [data-once-action] > [data-source-files]", "src/main.c")
      refute has_element?(action_view, "#{table} [data-source-files][data-part=cell]")
      assert has_element?(action_view, "#{table} details", "custom.mode: release")
      refute has_element?(action_view, "#{table} [data-once-action] b")
    end
  end

  test "source links use the connected repository at the recorded revision", %{
    conn: conn,
    organization: organization
  } do
    project =
      ProjectsFixtures.project_fixture(
        account_id: organization.account.id,
        build_system: :once,
        vcs_connection: [repository_full_handle: "org/repository"]
      )

    {:ok, run} =
      OnceEvents.upsert_run(%{project_id: project.id, run_id: UUIDv7.generate(), git_rev: "abc123"})

    {:ok, _} =
      OnceEvents.ingest_action(run, %{
        target_execution_id: "app",
        capability: "build",
        action_index: 0,
        display_name: "Compile main.c",
        source_files: ["src/main.c", "../outside.c", "/tmp/host.c"],
        result: "succeeded",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now()
      })

    conn = Plug.Conn.assign(conn, :selected_project, project)
    path = "/#{organization.account.name}/#{project.name}/once/runs/#{run.run_id}"
    {:ok, view, _} = live(conn, path)

    assert has_element?(view, ~s(#once-actions-table a[href="https://github.com/org/repository/blob/abc123/src/main.c"]))
    refute has_element?(view, ~s(#once-actions-table a[href*="outside.c"]))
    refute has_element?(view, ~s(#once-actions-table a[href*="/tmp/host.c"]))

    {:ok, cache_view, _} = live(conn, path <> "/cache")

    assert has_element?(
             cache_view,
             ~s(#once-cache-table a[href="https://github.com/org/repository/blob/abc123/src/main.c"])
           )

    run |> Ecto.Changeset.change(git_rev: nil) |> Tuist.Repo.update!()
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#once-actions-table", "src/main.c")
    refute has_element?(view, ~s(#once-actions-table a[href*="/blob/"]))
  end

  test "source classification controls links identically in actions and cache views", %{
    conn: conn,
    organization: organization
  } do
    project =
      ProjectsFixtures.project_fixture(
        account_id: organization.account.id,
        build_system: :once,
        vcs_connection: [repository_full_handle: "org/repository"]
      )

    {:ok, run} =
      OnceEvents.upsert_run(%{project_id: project.id, run_id: UUIDv7.generate(), git_rev: "abc123"})

    files = ["src/main.c", "third_party/rust/vendor/input.rs", "generated/input.c"]

    {:ok, action} =
      OnceEvents.ingest_action(run, %{
        target_execution_id: "classified",
        capability: "build",
        action_index: 0,
        source_files: files,
        source_file_statuses: [1, 2, 3],
        result: "succeeded",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now()
      })

    conn = Plug.Conn.assign(conn, :selected_project, project)
    path = "/#{organization.account.name}/#{project.name}/once/runs/#{run.run_id}"

    cases = [
      {[1, 2, 3], ["src/main.c"]},
      {[1, 0, 65_536], ["src/main.c"]},
      {[1], []},
      {[1, 1, 1, 1], []},
      {[3, 3, 3], []},
      {[0, 0, 0], []},
      {[65_536, 65_536, 65_536], []},
      {[-1, -1, -1], []},
      {nil, files},
      {[], files}
    ]

    for {statuses, linked} <- cases do
      action = Tuist.Repo.get!(Tuist.OnceEvents.Action, action.id)
      action |> Ecto.Changeset.change(source_file_statuses: statuses) |> Tuist.Repo.update!()

      for suffix <- ["", "/cache"] do
        {:ok, view, _} = live(conn, path <> suffix)

        for file <- files do
          assert has_element?(view, "[data-source-files]", file)
          selector = ~s([data-source-files] a[href="https://github.com/org/repository/blob/abc123/#{file}"])
          assert has_element?(view, selector) == file in linked
        end
      end
    end
  end

  test "large source lists have a bounded preview and all recorded paths remain searchable", %{
    conn: conn,
    path: path,
    run: run
  } do
    files = Enum.map(1..3000, &"src/file-#{&1}.c")

    Projector.project(
      %RunEvent{
        epoch_ms: 1_789_405_000_000,
        payload:
          {:action_completed,
           %ActionCompleted{
             target_execution_id: "large-source-target",
             capability: "build",
             display_name: "Compile large module",
             source_files: files,
             result: :TARGET_RESULT_SUCCEEDED
           }}
      },
      run.project_id,
      run.run_id
    )

    assert [%{source_files: ^files}] = OnceEvents.list_actions(run, search: "src/file-3000.c")

    for suffix <- ["?search=src%2Ffile-3000.c", "/cache?cache_search=src%2Ffile-3000.c"] do
      {:ok, view, _} = live(conn, path <> suffix)
      assert has_element?(view, "[data-source-files]", "2,997 more files")
      assert has_element?(view, "[data-source-files]", "src/file-1.c")
      refute has_element?(view, "[data-source-files]", "src/file-3000.c")
      labels = view |> render() |> Floki.parse_fragment!() |> Floki.find("[data-source-files] [title]")
      assert Enum.count(labels, &(Floki.text(&1) != "—")) == 3
    end

    [action] = OnceEvents.list_actions(run, search: "src/file-3000.c")
    action |> Ecto.Changeset.change(source_files: Enum.take(files, 4)) |> Tuist.Repo.update!()

    for suffix <- ["?search=src%2Ffile-4.c", "/cache?cache_search=src%2Ffile-4.c"] do
      {:ok, view, _} = live(conn, path <> suffix)
      assert has_element?(view, "[data-source-files]", "1 more file")
      refute has_element?(view, "[data-source-files]", "1 more files")
    end
  end

  test "actions without presentation metadata retain the original table", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#once-actions-table", "compiler-0")
    refute has_element?(view, "#once-actions-table th", "Source files")

    {:ok, cache_view, _} = live(conn, path <> "/cache")
    assert has_element?(cache_view, "#once-cache-table", "Compiler")
    refute has_element?(cache_view, "#once-cache-table th", "Source files")
  end

  test "an expired run reads as interrupted rather than running", %{conn: conn, path: path, run: run} do
    run |> Ecto.Changeset.change(finalization: "lost") |> Tuist.Repo.update!()

    {:ok, view, _} = live(conn, path)

    assert has_element?(view, "[data-part=badge-warning]")
    refute has_element?(view, "[data-part=badge-processing]")
    assert render(view) =~ "Interrupted"
    refute render(view) =~ "Running"
  end

  test "a cancelled run reads as cancelled rather than failed", %{conn: conn, path: path, run: run} do
    run
    |> Ecto.Changeset.change(finalization: "finalized", exit_status: 1, cancellation_reason: "SIGTERM")
    |> Tuist.Repo.update!()

    {:ok, view, _} = live(conn, path)

    assert has_element?(view, "[data-part=badge-warning]")
    refute has_element?(view, "[data-part=badge-failure]")
    assert render(view) =~ "Cancelled"
  end

  test "a passed run that carries a cancellation reason still reads as passed", %{conn: conn, path: path, run: run} do
    run
    |> Ecto.Changeset.change(finalization: "finalized", exit_status: 0, cancellation_reason: "SIGTERM")
    |> Tuist.Repo.update!()

    {:ok, view, _} = live(conn, path)

    assert has_element?(view, "[data-part=badge-success]")
    refute has_element?(view, "[data-part=badge-warning]")
    refute render(view) =~ "Cancelled"
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

    # A cache search that matches nothing must keep the input on screen,
    # otherwise there is no way to clear the query that emptied the list.
    {:ok, cache_view, _} = live(conn, path <> "/cache")
    assert has_element?(cache_view, "#once-cache-search")

    {:ok, cache_view, _} = live(conn, path <> "/cache?cache_search=nothingmatchesthis")
    assert has_element?(cache_view, "#once-cache-search")
    refute has_element?(cache_view, "#once-cache-table")

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

  test "the Overview tab does not query the Cache tab", %{conn: conn, path: path} do
    reject(&OnceEvents.cache_detail_metrics/1)
    reject(&OnceEvents.count_cache_events/2)
    reject(&OnceEvents.list_cache_events/2)

    {:ok, view, _} = live(conn, path)
    assert row_count(view) == 50

    send(view.pid, :refresh)
    assert row_count(view) == 50
  end

  test "switching to the Cache tab loads it and stops querying the actions", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path)
    assert row_count(view) == 50

    reject(&OnceEvents.count_actions/2)
    reject(&OnceEvents.list_actions/2)

    render_patch(view, path <> "/cache")
    assert has_element?(view, "#once-cache-search")
    assert has_element?(view, "#once-cache-table")

    send(view.pid, :refresh)
    assert has_element?(view, "#once-cache-table")
  end

  defp row_count(view),
    do: view |> render() |> Floki.parse_fragment!() |> Floki.find("#once-actions-table tbody tr") |> length()

  defp action(run, index) do
    Projector.project(
      %RunEvent{
        epoch_ms: 1_789_405_000_000,
        payload:
          {:action_completed,
           %ActionCompleted{
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
