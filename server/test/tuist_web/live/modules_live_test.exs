defmodule TuistWeb.ModulesLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest
  import TuistWeb.CldrHelpers

  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures
  alias TuistWeb.ModulesLive

  test "lists all modules with invalidations", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    stub(DateTime, :utc_now, fn -> ~U[2024-01-31 10:20:30Z] end)

    for {created_at, sources} <- [{~N[2024-01-30 10:00:00], "s1"}, {~N[2024-01-31 09:00:00], "s2"}] do
      event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          git_branch: "main",
          created_at: created_at
        )

      XcodeFixtures.xcode_target_fixture(
        command_event_id: event.id,
        name: "Core",
        product: "framework",
        binary_cache_hash: "h-#{sources}",
        binary_cache_hit: :miss,
        sources_hash: sources
      )
    end

    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/module-cache/modules")

    html = render_async(lv, 2000)

    assert has_element?(lv, "#all-modules-table")
    assert html =~ "Core"

    # Environment and date range filter the page; search and sort are table
    # controls and stay with the table.
    assert has_element?(lv, "#module-cache-modules > [data-part=\"filters\"] #modules-environment-dropdown")
    refute has_element?(lv, "#modules-branch-dropdown")
    assert has_element?(lv, "[data-part=\"modules-table-section\"] #modules-sort-dropdown")
    assert has_element?(lv, "[data-part=\"modules-table-section\"] #module-search")

    headers =
      html
      |> Floki.parse_document!()
      |> Floki.find("#all-modules-table thead th")
      |> Enum.map(&(&1 |> Floki.text() |> String.trim()))

    assert headers == ["Module", "Misses", "Cache hit rate", "Dependents"]

    # Core missed both of the two builds it took part in.
    assert html =~ "0.0%"
  end

  test "renders the analytics widgets and swaps the chart with the selection", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    stub(DateTime, :utc_now, fn -> ~U[2024-01-31 10:20:30Z] end)

    event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        git_branch: "main",
        created_at: ~N[2024-01-31 09:00:00]
      )

    XcodeFixtures.xcode_target_fixture(
      command_event_id: event.id,
      name: "Core",
      product: "framework",
      binary_cache_hash: "h-core",
      binary_cache_hit: :miss,
      sources_hash: "s1"
    )

    XcodeFixtures.xcode_target_fixture(
      command_event_id: event.id,
      name: "Networking",
      product: "framework",
      binary_cache_hash: "h-net",
      binary_cache_hit: :remote,
      sources_hash: "n1"
    )

    base = ~p"/#{organization.account.name}/#{project.name}/module-cache/modules"

    {:ok, lv, _html} = live(conn, base)
    render_async(lv, 2000)

    for id <- ~w(widget-modules widget-hits widget-misses) do
      assert has_element?(lv, "##{id}")
    end

    # The cache hit rate is on the table and the dashboard already, so it is
    # deliberately not a widget here.
    refute has_element?(lv, "#widget-hit-rate")

    # Misses is the default selection, so the reason breakdown is the chart.
    assert has_element?(lv, "#modules-miss-reasons-chart")

    # Two modules built once each: Core missed, Networking came from cache.
    assert has_element?(lv, "#widget-modules", "2")
    assert has_element?(lv, "#widget-hits", "1")
    assert has_element?(lv, "#widget-misses", "1")

    # Large counts are grouped rather than printed raw.
    assert format_number(1615) == "1,615"

    # The misses widget opens on the total rather than on one reason.
    assert has_element?(lv, "#widget-misses", "Misses")

    # Clicking a widget swaps in its chart. Driving the click rather than
    # loading the URL is what catches a patch target the client rejects.
    click_widget(lv, "hits")
    render_async(lv, 2000)

    assert has_element?(lv, "#modules-hits-chart")
    refute has_element?(lv, "#modules-miss-reasons-chart")

    click_widget(lv, "modules")
    render_async(lv, 2000)

    assert has_element?(lv, "#modules-chart")

    # The selection survives in the URL, so a chart can be linked to.
    assert_patched(lv, base <> "?analytics-selected-widget=modules")
  end

  test "the misses widget switches between the individual reasons", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    stub(DateTime, :utc_now, fn -> ~U[2024-01-31 10:20:30Z] end)

    build = fn created_at, sources ->
      event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          git_branch: "main",
          created_at: created_at
        )

      XcodeFixtures.xcode_target_fixture(
        command_event_id: event.id,
        name: "Core",
        product: "framework",
        binary_cache_hash: "h-#{sources}",
        binary_cache_hit: :miss,
        sources_hash: sources
      )
    end

    # One cold miss with nothing before it, then one where the sources changed.
    build.(~N[2024-01-30 10:00:00], "s1")
    build.(~N[2024-01-31 09:00:00], "s2")

    base = ~p"/#{organization.account.name}/#{project.name}/module-cache/modules"

    {:ok, lv, _html} = live(conn, base)
    render_async(lv, 2000)

    # Defaults to the total across every reason.
    assert has_element?(lv, "#widget-misses", "Misses")
    assert has_element?(lv, "#widget-misses", "2")

    # Every reason is wired to the event. The items render into a portal
    # template, which element/2 cannot reach, so the event goes straight to the
    # view and the markup is checked separately.
    html = render(lv)

    for reason <- ~w(all changed upstream cold) do
      assert html =~ ~s(phx-click="select_miss_reason" phx-value-type="#{reason}")
    end

    render_click(lv, "select_miss_reason", %{"type" => "changed"})
    render_async(lv, 2000)

    assert has_element?(lv, "#widget-misses", "Changed misses")
    assert has_element?(lv, "#widget-misses", "1")
    assert_patched(lv, base <> "?miss-reason=changed")

    render_click(lv, "select_miss_reason", %{"type" => "cold"})
    render_async(lv, 2000)

    assert has_element?(lv, "#widget-misses", "Cold misses")
    assert has_element?(lv, "#widget-misses", "1")
  end

  test "pages through the modules table", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    stub(DateTime, :utc_now, fn -> ~U[2024-01-31 10:20:30Z] end)

    event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        git_branch: "main",
        created_at: ~N[2024-01-31 09:00:00]
      )

    # 30 modules, every one of them a miss, so all 30 make the table.
    for i <- 1..30 do
      name = "Module#{String.pad_leading("#{i}", 2, "0")}"

      XcodeFixtures.xcode_target_fixture(
        command_event_id: event.id,
        name: name,
        product: "framework",
        binary_cache_hash: "h-#{name}",
        binary_cache_hit: :miss,
        sources_hash: "s-#{name}"
      )
    end

    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/module-cache/modules")

    assert lv |> render_async(2000) |> table_rows() == 25

    # Paging forward leaves the remaining five on the last page.
    html = render_patch(lv, "?after=Module25")

    assert table_rows(html) == 5
  end

  test "only the sorted column header is clickable, and it flips direction", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    stub(DateTime, :utc_now, fn -> ~U[2024-01-31 10:20:30Z] end)

    event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        git_branch: "main",
        created_at: ~N[2024-01-31 09:00:00]
      )

    for name <- ["Core", "Networking"] do
      XcodeFixtures.xcode_target_fixture(
        command_event_id: event.id,
        name: name,
        product: "framework",
        binary_cache_hash: "h-#{name}",
        binary_cache_hit: :miss,
        sources_hash: "s-#{name}"
      )
    end

    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/module-cache/modules?after=Core")

    links =
      lv
      |> render_async(2000)
      |> Floki.parse_document!()
      |> Floki.find(~s(#all-modules-table thead [data-part="sort-link"]))

    # Misses is the default sort, so it is the only sortable header. The other
    # columns are reached through the sort dropdown.
    assert length(links) == 1

    href = links |> List.first() |> Floki.attribute("href") |> List.first()

    # Misses opens descending, so the header offers the opposite.
    assert href =~ "sort-by=invalidations"
    assert href =~ "sort-order=asc"

    # A cursor points at a position in the old order, so re-sorting drops it.
    refute href =~ "after="
  end

  test "picking a column from the dropdown opens it worst first", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    stub(DateTime, :utc_now, fn -> ~U[2024-01-31 10:20:30Z] end)

    event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        git_branch: "main",
        created_at: ~N[2024-01-31 09:00:00]
      )

    XcodeFixtures.xcode_target_fixture(
      command_event_id: event.id,
      name: "Core",
      product: "framework",
      binary_cache_hash: "h-Core",
      binary_cache_hit: :miss,
      sources_hash: "s-Core"
    )

    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/module-cache/modules")

    render_async(lv, 2000)

    # The lowest hit rate is the worst, so that column opens ascending while the
    # count columns open descending.
    assert ModulesLive.sort_dropdown_patch(%URI{query: ""}, "hit_rate") =~ "sort-order=asc"
    assert ModulesLive.sort_dropdown_patch(%URI{query: ""}, "invalidations") =~ "sort-order=desc"
    assert ModulesLive.sort_dropdown_patch(%URI{query: ""}, "blast_radius") =~ "sort-order=desc"
  end

  # phx-click sits on the wrapper the widget component renders, not on the
  # element carrying the widget id.
  defp click_widget(lv, widget) do
    lv
    |> element(~s([phx-click="select_widget"][phx-value-widget="#{widget}"]))
    |> render_click()
  end

  defp table_rows(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("#all-modules-table tbody tr")
    |> length()
  end

  describe "page_of/3" do
    # 60 modules over a page size of 25: three pages of 25, 25 and 10.
    setup do
      %{modules: Enum.map(1..60, &%{name: "Module#{String.pad_leading("#{&1}", 2, "0")}"})}
    end

    test "starts on the first page when no cursor is given", %{modules: modules} do
      page = ModulesLive.page_of(modules, nil, nil)

      assert length(page.rows) == 25
      assert page.start_cursor == "Module01"
      assert page.end_cursor == "Module25"
      refute page.has_previous_page
      assert page.has_next_page
    end

    test "an after cursor takes the rows following it", %{modules: modules} do
      page = ModulesLive.page_of(modules, "Module25", nil)

      assert page.start_cursor == "Module26"
      assert page.end_cursor == "Module50"
      assert page.has_previous_page
      assert page.has_next_page
    end

    test "a before cursor takes the page preceding it", %{modules: modules} do
      page = ModulesLive.page_of(modules, nil, "Module26")

      assert page.start_cursor == "Module01"
      assert page.end_cursor == "Module25"
      refute page.has_previous_page
      assert page.has_next_page
    end

    test "the last page is short and has no next page", %{modules: modules} do
      page = ModulesLive.page_of(modules, "Module50", nil)

      assert length(page.rows) == 10
      assert page.end_cursor == "Module60"
      assert page.has_previous_page
      refute page.has_next_page
    end

    test "paging back from a partial last page lands on a full page", %{modules: modules} do
      page = ModulesLive.page_of(modules, nil, "Module51")

      assert length(page.rows) == 25
      assert page.start_cursor == "Module26"
      assert page.end_cursor == "Module50"
    end

    test "a cursor the search or sort removed falls back to the first page", %{modules: modules} do
      page = ModulesLive.page_of(modules, "Gone", nil)

      assert page.start_cursor == "Module01"
      refute page.has_previous_page
    end

    test "an empty list has neither a page nor cursors" do
      page = ModulesLive.page_of([], nil, nil)

      assert page.rows == []
      assert is_nil(page.start_cursor)
      assert is_nil(page.end_cursor)
      refute page.has_previous_page
      refute page.has_next_page
    end
  end
end
