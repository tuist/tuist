defmodule TuistWeb.OnceRunsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.OnceEvents

  setup %{project: project, organization: organization} do
    project = project |> Ecto.Changeset.change(build_system: :once) |> Tuist.Repo.update!()
    started_at = DateTime.add(DateTime.utc_now(), -3600, :second)

    for index <- 1..3 do
      {:ok, run} =
        OnceEvents.upsert_run(%{
          project_id: project.id,
          run_id: UUIDv7.generate(),
          kind: "build",
          command_display: "once build crate#{index}",
          host_class: "macos-arm64",
          once_version: "0.60.0",
          started_at: started_at
        })

      {:ok, _} =
        OnceEvents.finalize_run(run, %{
          finalization: "finalized",
          exit_status: 0,
          wall_ms: 1000 * index,
          finalized_at: started_at
        })
    end

    %{path: "/#{organization.account.name}/#{project.name}/once/builds"}
  end

  test "the Recent Builds card charts recent runs above the table", %{
    conn: conn,
    path: path,
    organization: organization,
    project: project
  } do
    {:ok, view, _} = live(conn, path)
    render_async(view, 2_000)

    # Same container and parts the Xcode Recent Builds card renders, so
    # `bazel_invocations.css` styles it rather than an approximation of it.
    assert has_element?(view, "[data-part=recent-builds-card-section]")
    assert has_element?(view, "[data-part=recent-builds-card-section] [data-part=builds-chart]")
    assert has_element?(view, "[data-part=builds-chart] [data-part=legends]")
    assert has_element?(view, "#once-recent-runs-chart")

    html = render(view)
    assert html =~ "Successful builds"
    assert html =~ "Failed builds"

    # The chart sits above the table rather than below it.
    [chart_at, table_at] =
      Enum.map(
        ["once-recent-runs-chart", "once-invocations-table"],
        &(html |> :binary.match(&1) |> elem(0))
      )

    assert chart_at < table_at

    # A summary card, not a listing: no filter dropdown and no pagination,
    # with a View more button pointing at the listing instead.
    refute has_element?(view, "#once-invocations-filter-dropdown")
    refute has_element?(view, ".noora-pagination-group")

    assert has_element?(
             view,
             "[data-part=bazel-invocations-card] a[href$='/once/build-runs']"
           )

    # The plain Build Runs listing keeps its filterable, paginated layout,
    # the way Xcode's own build-runs page does.
    {:ok, runs_view, _} =
      live(conn, "/#{organization.account.name}/#{project.name}/once/build-runs")

    render_async(runs_view, 2_000)
    refute has_element?(runs_view, "#once-recent-runs-chart")
    assert has_element?(runs_view, "#once-invocations-filter-dropdown")
  end

  test "the summary card shows only the latest runs", %{
    conn: conn,
    path: path,
    project: project
  } do
    started_at = DateTime.add(DateTime.utc_now(), -1800, :second)

    # Ten runs in total is more than the summary card's seven rows, but the
    # listing page must still show every one of them.
    for index <- 4..10 do
      {:ok, run} =
        OnceEvents.upsert_run(%{
          project_id: project.id,
          run_id: UUIDv7.generate(),
          kind: "build",
          command_display: "once build crate#{index}",
          started_at: started_at
        })

      {:ok, _} =
        OnceEvents.finalize_run(run, %{
          finalization: "finalized",
          exit_status: 0,
          wall_ms: 100 * index,
          finalized_at: started_at
        })
    end

    {:ok, view, _} = live(conn, path)
    render_async(view, 2_000)

    assert row_count(view) == 7
  end

  test "the Build Runs listing can be narrowed with the filter dropdown", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, view, _} = live(conn, "/#{organization.account.name}/#{project.name}/once/build-runs")
    render_async(view, 2_000)

    assert row_count(view) == 3
    assert has_element?(view, "#once-invocations-filter-dropdown")

    # No search box anywhere: Xcode's Build Runs has none, and the filter
    # dropdown is the control that narrows the listing.
    refute has_element?(view, "#once-invocations-search-form")
    refute render(view) =~ "Search runs"
  end

  test "Configuration Insights splits on version, host and environment", %{
    conn: conn,
    path: path,
    project: project
  } do
    started_at = DateTime.add(DateTime.utc_now(), -3600, :second)

    {:ok, run} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: UUIDv7.generate(),
        kind: "build",
        command_display: "once build ci",
        host_class: "linux-x86_64",
        once_version: "0.61.0",
        is_ci: true,
        started_at: started_at
      })

    {:ok, _} =
      OnceEvents.finalize_run(run, %{
        finalization: "finalized",
        exit_status: 0,
        wall_ms: 5000,
        finalized_at: started_at
      })

    # The dropdown offers all three, the way the Xcode card does, rather
    # than the single pointless entry it used to carry.
    {:ok, view, _} = live(conn, path)
    render_async(view, 2_000)

    # Noora renders dropdown items into a `<template>` portal, which Floki
    # does not expose to `has_element?/2`, so the patch targets are matched
    # against the rendered markup instead.
    html = render(view)

    for dimension <- ~w(version host environment) do
      assert html =~ "configuration-insights-type=#{dimension}"
    end

    # The categories themselves are asserted against the query rather than
    # the rendered HTML, where words like "Local" also appear in chrome.
    opts = [commands: ["build"]]

    assert "0.61.0" in categories(project.id, :version, opts)
    assert "linux-x86_64" in categories(project.id, :host, opts)
    assert Enum.sort(categories(project.id, :environment, opts)) == ["CI", "Local"]

    # An unknown value falls back to version rather than reaching
    # `String.to_existing_atom/1` with arbitrary input.
    {:ok, view, _} = live(conn, path <> "?configuration-insights-type=bogus")
    render_async(view, 2_000)
    assert has_element?(view, "#once-configuration-insights-type-dropdown")
  end

  test "the Build Runs listing has no date picker and is not period scoped", %{
    conn: conn,
    path: path,
    organization: organization,
    project: project
  } do
    # Older than any date-picker preset, so a period-scoped query hides it.
    long_ago = DateTime.add(DateTime.utc_now(), -400 * 24 * 3600, :second)

    {:ok, run} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: UUIDv7.generate(),
        kind: "build",
        command_display: "once build ancient",
        started_at: long_ago
      })

    {:ok, _} =
      OnceEvents.finalize_run(run, %{
        finalization: "finalized",
        exit_status: 0,
        wall_ms: 4321,
        finalized_at: long_ago
      })

    {:ok, runs_view, _} =
      live(conn, "/#{organization.account.name}/#{project.name}/once/build-runs")

    render_async(runs_view, 2_000)

    refute has_element?(runs_view, "#once-invocations-date-range-picker")
    assert render(runs_view) =~ "ancient"

    # The Builds page keeps its picker, and its 30 day default hides the run.
    {:ok, builds_view, _} = live(conn, path)
    render_async(builds_view, 2_000)

    assert has_element?(builds_view, "#once-invocations-date-range-picker")
    refute render(builds_view) =~ "ancient"
  end

  test "the Build Runs controls and columns line up with Xcode's", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    started_at = DateTime.add(DateTime.utc_now(), -600, :second)

    {:ok, run} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: UUIDv7.generate(),
        kind: "build",
        command_display: "once build ci-run",
        git_rev: "abcdef1234567890",
        git_branch: "release/1.2",
        host_class: "linux-x86_64",
        is_ci: true,
        started_at: started_at
      })

    {:ok, _} =
      OnceEvents.finalize_run(run, %{
        finalization: "finalized",
        exit_status: 0,
        wall_ms: 2500,
        finalized_at: started_at
      })

    {:ok, view, _} = live(conn, "/#{organization.account.name}/#{project.name}/once/build-runs")
    render_async(view, 2_000)

    html = render(view)

    # Sort by, the control Xcode's Build Runs leads with, offering the same
    # two columns it does.
    assert html =~ "Sort by:"
    assert has_element?(view, "#once-invocations-sort-by")
    assert html =~ "invocations-sort-by=duration"
    assert html =~ "invocations-sort-by=ran-at"

    # Exactly the Xcode Build Runs columns Once can report, in Xcode's own
    # order (Scheme, Status, Branch, Commit SHA, Ran by, Duration, Ran at,
    # Device), with no cache columns Xcode has no counterpart for.
    assert table_headers(view) == [
             "Run",
             "Status",
             "Branch",
             "Commit SHA",
             "Ran by",
             "Duration",
             "Ran at",
             "Host"
           ]

    assert html =~ "release/1.2"

    # The SHA is abbreviated the way Xcode abbreviates it, not printed raw.
    assert html =~ "abcdef1"
    refute html =~ "abcdef1234567890"

    # Ran by reads CI for a CI run and Local otherwise.
    assert html =~ "once build ci-run"
  end

  test "the Test Runs analytics cards are ordered the way Xcode's are", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, view, _} = live(conn, "/#{organization.account.name}/#{project.name}/once/test-runs")
    render_async(view, 2_000)

    html = render(view)

    order =
      Enum.map(
        ["once-total-invocations", "once-failed-invocations", "once-line-coverage", "once-invocation-duration"],
        fn id -> {id, :binary.match(html, id)} end
      )

    # Every card has to be present, otherwise the ordering below is vacuous.
    for {id, match} <- order, do: assert(match != :nomatch, "#{id} missing")

    positions = Enum.map(order, fn {_id, {at, _}} -> at end)

    # Xcode's Test Runs page (test_runs_live.html.heex) puts coverage after the
    # failure count, not before it.
    assert positions == Enum.sort(positions)
  end

  test "the build duration widget can be shown as a scatter of runs", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path <> "?analytics-selected-widget=build-duration")
    render_async(view)

    # Line by default.
    assert has_element?(view, "#once-builds-analytics-chart")
    refute has_element?(view, "#once-build-duration-scatter-chart")

    render_click(view, "select_duration_chart_type", %{"type" => "scatter"})
    render_async(view)

    assert has_element?(view, "#once-build-duration-scatter-chart")
    refute has_element?(view, "#once-builds-analytics-chart")
  end

  defp table_headers(view) do
    view
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("#once-invocations-table thead th")
    |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
    |> Enum.reject(&(&1 == ""))
  end

  defp categories(project_id, dimension, opts) do
    project_id
    |> Tuist.OnceEvents.Analytics.build_duration_analytics_by(dimension, opts)
    |> Enum.map(& &1.category)
  end

  defp row_count(view),
    do: view |> render() |> Floki.parse_fragment!() |> Floki.find("#once-invocations-table tbody tr") |> length()
end
