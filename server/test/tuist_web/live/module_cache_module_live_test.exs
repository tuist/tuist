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

    assert headers == ["Ran at", "Branch", "Commit", "Result", "Why"]

    # Three builds, newest first: its sources changed, then a remote hit, then
    # the first build on the branch with nothing to compare against.
    reasons =
      document
      |> Floki.find("#module-build-history-table tbody tr")
      |> Enum.map(fn row ->
        row |> Floki.find("td") |> List.last() |> Floki.text() |> String.trim()
      end)

    assert reasons == ["Changed", "-", "Cold"]

    # The short commit sha is what identifies the build to a reader.
    assert html =~ "abcdef1"
  end
end
