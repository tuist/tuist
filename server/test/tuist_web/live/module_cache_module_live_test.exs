defmodule TuistWeb.ModuleCacheModuleLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

  test "renders the module detail page with chart and downstream impact", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    stub(DateTime, :utc_now, fn -> ~U[2024-01-31 10:20:30Z] end)

    target = fn event_id, name, hit, sources, deps ->
      XcodeFixtures.xcode_target_fixture(
        command_event_id: event_id,
        name: name,
        product: "framework",
        binary_cache_hash: "h-#{name}-#{sources}",
        binary_cache_hit: hit,
        sources_hash: sources,
        dependencies: deps
      )
    end

    event = fn created_at ->
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        git_branch: "main",
        created_at: created_at
      ).id
    end

    # An earlier Core build for the time series.
    target.(event.(~N[2024-01-28 10:00:00]), "Core", :miss, "c1", [])

    # The latest build carries the whole graph in one event (as a real build does),
    # so the dependency edges are complete: Networking depends on Core, meaning Core
    # invalidates Networking downstream.
    latest = event.(~N[2024-01-31 09:00:00])
    target.(latest, "Core", :miss, "c2", [])
    target.(latest, "Networking", :remote, "n1", ["Core"])

    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/module-cache/modules/Core")

    html = render_async(lv, 2000)

    assert has_element?(lv, "#widget-cache-activity")
    assert has_element?(lv, "#module-cache-activity-chart")

    # Networking depends on Core, so Core has exactly one dependent.
    assert html
           |> Floki.parse_document!()
           |> Floki.find(~s(#widget-blast-radius [data-part="value"]))
           |> Floki.text()
           |> String.trim() == "1"
  end

  test "lists the builds the module took part in", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    stub(DateTime, :utc_now, fn -> ~U[2024-01-31 10:20:30Z] end)

    build = fn created_at, hit, sources ->
      event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          git_branch: "main",
          git_commit_sha: "abcdef1234567890",
          created_at: created_at
        )

      XcodeFixtures.xcode_target_fixture(
        command_event_id: event.id,
        name: "Core",
        product: "framework",
        binary_cache_hash: "h-#{sources}",
        binary_cache_hit: hit,
        sources_hash: sources
      )

      event
    end

    build.(~N[2024-01-29 10:00:00], :miss, "s1")
    build.(~N[2024-01-30 10:00:00], :remote, "s1")
    build.(~N[2024-01-31 09:00:00], :miss, "s2")

    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/module-cache/modules/Core")

    html = render_async(lv, 2000)

    assert has_element?(lv, "#module-build-history-table")

    document = Floki.parse_document!(html)

    headers =
      document
      |> Floki.find("#module-build-history-table thead th")
      |> Enum.map(&(&1 |> Floki.text() |> String.trim()))

    assert headers == ["Scheme", "Result", "Branch", "Commit SHA", "Why", "Ran at"]

    # Three builds, newest first: its sources changed, then a remote hit, then
    # the first build on the branch with nothing to compare against.
    reasons =
      document
      |> Floki.find("#module-build-history-table tbody tr")
      |> Enum.map(fn row ->
        row |> Floki.find("td") |> Enum.at(4) |> Floki.text() |> String.trim()
      end)

    assert reasons == ["Changed", "Cached", "Cold"]

    results =
      document
      |> Floki.find("#module-build-history-table tbody tr")
      |> Enum.map(fn row ->
        row |> Floki.find("td") |> Enum.at(1) |> Floki.text() |> String.trim()
      end)

    assert results == ["Miss", "Remote hit", "Miss"]

    # The short commit sha is what identifies the build to a reader.
    assert html =~ "abcdef1"
  end

  test "filters the builds table and flips the ran at order", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    stub(DateTime, :utc_now, fn -> ~U[2024-01-31 10:20:30Z] end)

    build = fn branch, sha, created_at, hit, sources ->
      event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          git_branch: branch,
          git_commit_sha: sha,
          created_at: created_at
        )

      XcodeFixtures.xcode_target_fixture(
        command_event_id: event.id,
        name: "Core",
        product: "framework",
        binary_cache_hash: "h-#{sources}",
        binary_cache_hit: hit,
        sources_hash: sources
      )
    end

    build.("main", "aaa111", ~N[2024-01-29 10:00:00], :miss, "s1")
    build.("main", "aaa222", ~N[2024-01-30 10:00:00], :remote, "s1")
    build.("feature/x", "bbb333", ~N[2024-01-31 09:00:00], :miss, "s9")

    base = ~p"/#{organization.account.name}/#{project.name}/module-cache/modules/Core"

    {:ok, lv, _html} = live(conn, base)
    render_async(lv, 2000)
    assert build_rows(lv) == 3

    # Branch narrows to the two builds on main.
    {:ok, lv, _html} = live(conn, base <> "?builds-branch=main")
    render_async(lv, 2000)
    assert build_rows(lv) == 2

    # A commit sha prefix narrows further.
    {:ok, lv, _html} = live(conn, base <> "?builds-commit=aaa2")
    render_async(lv, 2000)
    assert build_rows(lv) == 1

    # Why keeps only the cache hits.
    {:ok, lv, _html} = live(conn, base <> "?builds-reason=hit")
    html = render_async(lv, 2000)
    assert build_rows(lv) == 1
    assert html =~ "Remote hit"

    # Ran at is sortable, and its header offers the opposite direction.
    href =
      html
      |> Floki.parse_document!()
      |> Floki.find(~s(#module-build-history-table thead [data-part="sort-link"]))
      |> Floki.attribute("href")
      |> List.first()

    assert href =~ "builds-order=asc"

    {:ok, lv, _html} = live(conn, base <> "?builds-order=asc")
    html = render_async(lv, 2000)

    # Oldest first now, so the first row is the earliest build.
    first_sha =
      html
      |> Floki.parse_document!()
      |> Floki.find("#module-build-history-table tbody tr")
      |> List.first()
      |> Floki.find("td")
      |> Enum.at(3)
      |> Floki.text()
      |> String.trim()

    assert first_sha =~ "aaa111"
  end

  defp build_rows(lv) do
    lv
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("#module-build-history-table tbody tr")
    |> length()
  end
end
