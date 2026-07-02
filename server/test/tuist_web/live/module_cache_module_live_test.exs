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

    html = render_async(lv)

    assert has_element?(lv, "#widget-module-invalidations")
    assert has_element?(lv, "#module-invalidations-timeline-chart")
    assert html =~ "Invalidates downstream"
    # Core's downstream blast radius includes Networking.
    assert html =~ "Networking"
  end
end
