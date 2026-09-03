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

  describe "invalidated by sorting and pagination" do
    alias TuistWeb.ModuleCacheModuleLive

    defp deps(count) do
      for i <- 1..count, do: %{name: "Dep#{i}", invalidations: i}
    end

    test "sorts by invalidations caused in both directions" do
      given = deps(3)

      assert given
             |> ModuleCacheModuleLive.sort_dependencies("invalidations", "desc")
             |> Enum.map(& &1.invalidations) == [3, 2, 1]

      assert given
             |> ModuleCacheModuleLive.sort_dependencies("invalidations", "asc")
             |> Enum.map(& &1.invalidations) == [1, 2, 3]
    end

    test "sorts by name" do
      given = [%{name: "Zed", invalidations: 1}, %{name: "Alpha", invalidations: 9}]

      assert given
             |> ModuleCacheModuleLive.sort_dependencies("name", "asc")
             |> Enum.map(& &1.name) == ["Alpha", "Zed"]
    end

    test "pages the list" do
      per_page = ModuleCacheModuleLive.invalidated_by_per_page()
      given = deps(per_page * 2 + 3)

      assert length(ModuleCacheModuleLive.page_of(given, 1)) == per_page
      assert length(ModuleCacheModuleLive.page_of(given, 3)) == 3
      assert ModuleCacheModuleLive.page_count(given) == 3

      # pages do not overlap and cover the whole list
      paged =
        1..3
        |> Enum.flat_map(&ModuleCacheModuleLive.page_of(given, &1))
        |> Enum.map(& &1.name)

      assert paged == Enum.map(given, & &1.name)
    end

    test "a short list is a single page and an empty list still reports one" do
      assert ModuleCacheModuleLive.page_count(deps(1)) == 1
      assert ModuleCacheModuleLive.page_count([]) == 1
      assert ModuleCacheModuleLive.page_of([], 1) == []
    end
  end
end
