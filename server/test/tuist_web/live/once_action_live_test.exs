defmodule TuistWeb.OnceActionLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Action
  alias Tuist.OnceEvents.ActionHistory
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{project: project, organization: organization} do
    project = project |> Ecto.Changeset.change(build_system: :once) |> Repo.update!()
    now = DateTime.utc_now()
    actions = for index <- 1..24, do: occurrence(project, DateTime.add(now, -index, :day), index)
    action = hd(actions)

    %{
      action: action,
      actions: actions,
      project: project,
      path: "/#{organization.account.name}/#{project.name}/once/runs/#{action.run_id}/actions/#{action.id}"
    }
  end

  test "overview follows test-case analytics, selected occurrence and recent executions", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path)
    render_async(view)
    assert has_element?(view, "#once-action h1", "Compile library 1")
    assert has_element?(view, "#once-action-history-chart")
    assert has_element?(view, "#once-action", "native-target")
    assert has_element?(view, "[data-part=history-note]", "retained")

    assert view |> render() |> Floki.parse_fragment!() |> Floki.find("#once-action-history-table tbody tr") |> length() ==
             6
  end

  test "history paginates and shows each occurrence's own display name and package version", %{
    conn: conn,
    path: path,
    actions: actions
  } do
    {:ok, view, _} = live(conn, path <> "?tab=history")
    render_async(view)
    assert has_element?(view, "#once-action-history-table", "library 1.0.1")

    assert view |> render() |> Floki.parse_fragment!() |> Floki.find("#once-action-history-table tbody tr") |> length() ==
             20

    last = List.last(actions)
    {:ok, second, _} = live(conn, path <> "?tab=history&page=2")
    render_async(second)
    assert has_element?(second, "#once-action-history-table", last.display_name)

    assert second |> render() |> Floki.parse_fragment!() |> Floki.find("#once-action-history-table tbody tr") |> length() ==
             4
  end

  test "branch and date-window filters survive navigation and constrain history", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path <> "?tab=history&branch=main&days=7&metric=failures")
    render_async(view)

    assert (view |> render() |> Floki.parse_fragment!() |> Floki.find("#once-action-history-table tbody tr") |> length()) in 3..4

    view |> element("#once-action a", "Overview") |> render_click()
    render_async(view)
    assert has_element?(view, "#once-action-history-chart")
    assert render(view) =~ "branch=main"
  end

  test "legacy and ambiguous identities explain missing history without label matching", %{
    conn: conn,
    path: path,
    action: action
  } do
    action |> Ecto.Changeset.change(history_id: nil, history_key: nil, history_namespace: nil) |> Repo.update!()
    {:ok, view, _} = live(conn, path)
    render_async(view)
    assert render(view) =~ "did not report a stable logical identity"
    refute has_element?(view, "#once-action-history-chart")
    action |> Ecto.Changeset.change(history_ambiguous: true) |> Repo.update!()
    {:ok, view, _} = live(conn, path)
    assert render(view) =~ "multiple actions"
  end

  test "live ingestion refreshes statistics and newly colliding keys disable history", %{
    conn: conn,
    path: path,
    action: action,
    project: project
  } do
    {:ok, view, _} = live(conn, path <> "?tab=history")
    render_async(view)
    new = occurrence(project, DateTime.utc_now(), 30)
    ActionHistory.broadcast(new)
    send(view.pid, :refresh_history)
    render_async(view)
    assert has_element?(view, "#once-action-history-table", "Compile library 30")
    run = Repo.get!(Tuist.OnceEvents.Run, action.once_run_id)

    {:ok, _collision} =
      OnceEvents.ingest_action(run, %{
        target_execution_id: "different",
        capability: "build",
        action_index: 2,
        result: "succeeded",
        started_at: action.started_at,
        finished_at: action.finished_at,
        history: %{namespace: "test.v1", key: "library.compile"}
      })

    send(view.pid, :refresh_history)
    render_async(view)
    assert render(view) =~ "multiple actions"
    refute has_element?(view, "#once-action-history-table")
  end

  test "foreign, mismatched-run and invalid occurrence IDs are not found", %{
    conn: conn,
    path: path,
    project: project,
    action: action
  } do
    foreign = occurrence(ProjectsFixtures.project_fixture(build_system: :once), DateTime.utc_now(), 1)
    assert ActionHistory.get_occurrence(project.id, foreign.run_id, foreign.id) == {:error, :not_found}

    for bad_path <- [String.replace(path, action.id, foreign.id), String.replace(path, action.id, "invalid")] do
      assert_raise NotFoundError, fn -> live(conn, bad_path) end
    end
  end

  defp occurrence(project, started_at, index) do
    {:ok, run} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: UUIDv7.generate(),
        git_branch: if(rem(index, 2) == 0, do: "main", else: "feature"),
        git_rev: String.duplicate("a", 40)
      })

    {:ok, action} =
      OnceEvents.ingest_action(run, %{
        target_execution_id: "target",
        capability: "build",
        action_index: index,
        identifier: "compile",
        display_name: "Compile library #{index}",
        source_files: ["src/lib.rs"],
        source_file_statuses: [2],
        presentation: %{
          "package" => %{"ecosystem" => "cargo", "name" => "library", "version" => "1.0.#{index}"},
          "platforms" => [
            %{"scheme" => "rust", "id" => "native-target", "label" => "Linux · arm64", "usage" => "product"}
          ]
        },
        result: if(rem(index, 7) == 0, do: "failed", else: "succeeded"),
        was_cached: rem(index, 3) == 0,
        cache_key: "digest-#{index}",
        duration_ms: index * 100,
        started_at: started_at,
        finished_at: DateTime.add(started_at, index * 100, :millisecond),
        history: %{namespace: "test.v1", key: "library.compile"}
      })

    Repo.get!(Action, action.id)
  end
end
