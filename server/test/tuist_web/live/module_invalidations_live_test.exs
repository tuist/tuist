defmodule TuistWeb.ModuleInvalidationsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures
  alias TuistWeb.ModuleInvalidationsLive

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
    assert has_element?(lv, "#module-invalidations > [data-part=\"filters\"] #module-invalidations-environment-dropdown")
    refute has_element?(lv, "#module-invalidations-branch-dropdown")
    assert has_element?(lv, "[data-part=\"modules-table-section\"] #module-invalidations-sort-dropdown")
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
      page = ModuleInvalidationsLive.page_of(modules, nil, nil)

      assert length(page.rows) == 25
      assert page.start_cursor == "Module01"
      assert page.end_cursor == "Module25"
      refute page.has_previous_page
      assert page.has_next_page
    end

    test "an after cursor takes the rows following it", %{modules: modules} do
      page = ModuleInvalidationsLive.page_of(modules, "Module25", nil)

      assert page.start_cursor == "Module26"
      assert page.end_cursor == "Module50"
      assert page.has_previous_page
      assert page.has_next_page
    end

    test "a before cursor takes the page preceding it", %{modules: modules} do
      page = ModuleInvalidationsLive.page_of(modules, nil, "Module26")

      assert page.start_cursor == "Module01"
      assert page.end_cursor == "Module25"
      refute page.has_previous_page
      assert page.has_next_page
    end

    test "the last page is short and has no next page", %{modules: modules} do
      page = ModuleInvalidationsLive.page_of(modules, "Module50", nil)

      assert length(page.rows) == 10
      assert page.end_cursor == "Module60"
      assert page.has_previous_page
      refute page.has_next_page
    end

    test "paging back from a partial last page lands on a full page", %{modules: modules} do
      page = ModuleInvalidationsLive.page_of(modules, nil, "Module51")

      assert length(page.rows) == 25
      assert page.start_cursor == "Module26"
      assert page.end_cursor == "Module50"
    end

    test "a cursor the search or sort removed falls back to the first page", %{modules: modules} do
      page = ModuleInvalidationsLive.page_of(modules, "Gone", nil)

      assert page.start_cursor == "Module01"
      refute page.has_previous_page
    end

    test "an empty list has neither a page nor cursors" do
      page = ModuleInvalidationsLive.page_of([], nil, nil)

      assert page.rows == []
      assert is_nil(page.start_cursor)
      assert is_nil(page.end_cursor)
      refute page.has_previous_page
      refute page.has_next_page
    end
  end
end
