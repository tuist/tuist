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
  alias TuistWeb.OnceActionLive

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
    render_async(view, 5_000)
    assert has_element?(view, "#once-action h1", "Compile library 1")
    assert has_element?(view, "#once-action-history-chart")
    assert has_element?(view, "#once-action", "native-target")
    refute has_element?(view, "[data-history-note]")
    refute has_element?(view, "#once-action-history-scope")

    for metric <- ["duration", "executions", "cache", "failures"] do
      assert has_element?(view, "#once-action-#{metric}-tooltip [data-part=trigger]")
    end

    refute has_element?(view, "[data-part=observation-summary], [data-first-observed], [data-first-failure]")
    refute has_element?(view, "p[data-part=history-note]")

    assert view |> render() |> Floki.parse_fragment!() |> Floki.find("#once-action-history-table tbody tr") |> length() ==
             6
  end

  test "rates and durations use sampled aggregates while counts use bars", %{conn: conn, path: path} do
    for {metric, type} <- [{"duration", "scatter"}, {"cache", "scatter"}, {"executions", "bar"}, {"failures", "bar"}] do
      assert OnceActionLive.chart_type(metric) == type
      {:ok, view, _} = live(conn, path <> "?metric=#{metric}")
      render_async(view, 5_000)
      [chart] = view |> render() |> Floki.parse_fragment!() |> Floki.find("#once-action-history-chart")
      options = chart |> Floki.find("[data-part=data]") |> Floki.text() |> Jason.decode!()
      assert [%{"type" => ^type}] = Enum.map(options["series"], &Map.take(&1, ["type"]))
    end
  end

  test "unavailable metric measurements show an empty state instead of bare scatter axes", %{
    conn: conn,
    path: path,
    actions: actions
  } do
    for {metric, attrs} <- [
          {"duration", %{was_cached: true, result: "succeeded"}},
          {"cache", %{was_cached: false, cache_key: ""}}
        ] do
      Enum.each(actions, fn action -> Action |> Repo.get!(action.id) |> Ecto.Changeset.change(attrs) |> Repo.update!() end)

      {:ok, view, _} = live(conn, path <> "?metric=#{metric}")
      render_async(view, 5_000)
      refute has_element?(view, "#once-action-history-chart")
      assert has_element?(view, "[data-part=analytics-chart] [data-part=empty]", "No measurements for this metric")
    end
  end

  test "scatter points omit missing measurements without dropping genuine zero values" do
    stats = %{
      series: [
        %{day: ~N[2026-10-01 00:00:00], duration: nil, hits: 0, cache_observations: 0},
        %{day: ~N[2026-10-02 00:00:00], duration: Decimal.new(0), hits: 0, cache_observations: 1},
        %{day: ~N[2026-10-03 00:00:00], duration: Decimal.new(10), hits: 1, cache_observations: 2}
      ]
    }

    [duration] = OnceActionLive.chart_series(stats, "duration")
    assert duration.data == [["2026-10-02T00:00:00Z", 0.0], ["2026-10-03T00:00:00Z", 10.0]]

    [cache] = OnceActionLive.chart_series(stats, "cache")
    assert cache.data == [["2026-10-02T00:00:00Z", 0.0], ["2026-10-03T00:00:00Z", 50.0]]
  end

  test "source search uses the shared compact toolbar without an unsupported shortcut", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path)
    render_async(view, 5_000)
    assert has_element?(view, "[data-part=source-files] [data-part=table-toolbar] #once-action-source-search")
    assert has_element?(view, "#once-action-sources-search[placeholder='Search...']")
    refute has_element?(view, "#once-action-source-search [data-part=suffix]")
    view |> form("#once-action-source-search", %{"source-search" => "missing"}) |> render_change()
    assert has_element?(view, "#once-action-sources-table", "No source files match your search.")
  end

  test "metadata uses aligned fields and neutral badges without renaming actions to invocations", %{
    conn: conn,
    path: path,
    action: action
  } do
    metadata = %{
      "package" => %{"ecosystem" => "bazel", "name" => "library", "version" => "1.0.0", "origin" => "workspace"},
      "platforms" => [
        %{
          "scheme" => "vendor.platform",
          "id" => "native-output-variant",
          "label" => "Output variant",
          "usage" => "build-tool"
        }
      ],
      "context" => [%{"key" => "vendor.mode", "value" => "custom", "label" => "Producer-owned mode"}]
    }

    action |> Ecto.Changeset.change(presentation: metadata) |> Repo.update!()
    {:ok, view, _} = live(conn, path)
    render_async(view, 5_000)
    assert has_element?(view, "[data-action-package] .noora-badge[data-color=neutral]", "bazel")
    assert has_element?(view, "[data-action-platform][data-part=metadata-grid]", "native-output-variant")
    assert has_element?(view, "[data-action-platform] .noora-badge[data-color=neutral]", "Build tool")
    assert has_element?(view, "[data-action-context] .noora-badge[data-color=neutral]", "custom")
    assert has_element?(view, "[data-action-context]", "vendor.mode")
    assert has_element?(view, "[data-action-context]", "Producer-owned mode")
    assert has_element?(view, "[data-part=execution-details] .noora-badge[data-color=neutral]", "Local")
    assert has_element?(view, "[data-part=action-history]", "Recent action executions")
    refute has_element?(view, "[data-part=action-history]", "invocations")
  end

  test "long producer-owned badge values and labels remain intact", %{conn: conn, path: path, action: action} do
    label = String.duplicate("P", 128)
    value = String.duplicate("V", 256)

    metadata = %{
      "platforms" => [
        %{"scheme" => "future.platform", "id" => "native-output", "label" => label, "usage" => "future-role"}
      ],
      "context" => [%{"key" => "future.value", "value" => value}]
    }

    action |> Ecto.Changeset.change(presentation: metadata) |> Repo.update!()
    {:ok, view, _} = live(conn, path)
    render_async(view, 5_000)
    assert has_element?(view, "[data-action-platform] .noora-badge", label)
    assert has_element?(view, "[data-action-platform] .noora-badge", "future-role")
    assert has_element?(view, "[data-action-context] .noora-badge", value)
  end

  test "history paginates and shows each occurrence's own display name and package version", %{
    conn: conn,
    path: path,
    actions: actions
  } do
    {:ok, view, _} = live(conn, path <> "?tab=history")
    render_async(view, 5_000)
    assert has_element?(view, "#once-action-history-table", "library 1.0.1")

    assert view |> render() |> Floki.parse_fragment!() |> Floki.find("#once-action-history-table tbody tr") |> length() ==
             20

    last = List.last(actions)
    {:ok, second, _} = live(conn, path <> "?tab=history&page=2")
    render_async(second, 5_000)
    assert has_element?(second, "#once-action-history-table", last.display_name)

    assert second |> render() |> Floki.parse_fragment!() |> Floki.find("#once-action-history-table tbody tr") |> length() ==
             4
  end

  test "branch and date-window filters survive navigation and constrain history", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path <> "?tab=history&branch=main&days=7&metric=failures")
    render_async(view, 5_000)

    assert (view |> render() |> Floki.parse_fragment!() |> Floki.find("#once-action-history-table tbody tr") |> length()) in 3..4

    view |> element("#once-action a", "Overview") |> render_click()
    render_async(view, 5_000)
    assert has_element?(view, "#once-action-history-chart")
    assert render(view) =~ "branch=main"
  end

  test "history exposes its window and older observations become visible when expanded", %{
    conn: conn,
    path: path,
    project: project
  } do
    old = occurrence(project, DateTime.add(DateTime.utc_now(), -45, :day), 45)
    {:ok, view, _} = live(conn, path <> "?tab=history&days=30")
    render_async(view, 5_000)
    assert has_element?(view, "#once-action-history-period")
    assert has_element?(view, "#once-action-history-period-label-portal", "Last 30 days")
    refute has_element?(view, "#once-action-history-table", old.display_name)
    refute has_element?(view, "#once-action-history-chart")

    render_patch(view, path <> "?tab=history&days=90&page=2")
    render_async(view, 5_000)
    assert has_element?(view, "#once-action-history-period-label-portal", "Last 90 days")
    assert has_element?(view, "#once-action-history-table", old.display_name)
  end

  test "malformed query values fall back to defaults", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path <> "?branch[]=x&page[a]=1&source-search[]=x&source-page[a]=1")
    render_async(view, 5_000)
    assert has_element?(view, "#once-action-branch[value='']")
    assert has_element?(view, "#once-action-source-search input[value='']")
    assert has_element?(view, "#once-action-history-table", "Compile library 1")
  end

  @tag timeout: 15_000
  test "large classified source lists render and search with original alignment", %{
    conn: conn,
    path: path,
    action: action
  } do
    files = Enum.map(1..50_000, &"src/#{&1}.rs")
    statuses = Enum.map(1..50_000, &if(rem(&1, 2) == 0, do: 1, else: 2))
    action |> Ecto.Changeset.change(source_files: files, source_file_statuses: statuses) |> Repo.update!()
    {:ok, view, _} = live(conn, path)
    render_async(view, 5_000)
    assert has_element?(view, "[data-source-file]", "src/1.rs")
    refute has_element?(view, "[data-source-file]", "src/50000.rs")
    view |> form("#once-action-source-search", %{"source-search" => "src/50000.rs"}) |> render_change()
    assert has_element?(view, "[data-source-file]", "src/50000.rs")
  end

  test "anonymous public readers can open occurrences but private non-members cannot", %{conn: conn} do
    public = ProjectsFixtures.project_fixture(visibility: :public, build_system: :once)
    public = Repo.preload(public, :account)
    action = occurrence(public, DateTime.utc_now(), 1)
    path = "/#{public.account.name}/#{public.name}/once/runs/#{action.run_id}/actions/#{action.id}"
    {:ok, view, _} = live(build_conn(), path)
    render_async(view, 5_000)
    assert has_element?(view, "#once-action", action.display_name)

    private = ProjectsFixtures.project_fixture(build_system: :once)
    private = Repo.preload(private, :account)
    hidden = occurrence(private, DateTime.utc_now(), 1)
    hidden_path = "/#{private.account.name}/#{private.name}/once/runs/#{hidden.run_id}/actions/#{hidden.id}"
    assert_raise NotFoundError, fn -> live(conn, hidden_path) end
  end

  test "legacy and ambiguous identities explain missing history without label matching", %{
    conn: conn,
    path: path,
    action: action
  } do
    action |> Ecto.Changeset.change(history_id: nil, history_key: nil, history_namespace: nil) |> Repo.update!()
    {:ok, view, _} = live(conn, path)
    render_async(view, 5_000)
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
    render_async(view, 5_000)
    new = occurrence(project, DateTime.utc_now(), 30)
    ActionHistory.broadcast(new)
    send(view.pid, :refresh_history)
    render_async(view, 5_000)
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
    render_async(view, 5_000)
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
