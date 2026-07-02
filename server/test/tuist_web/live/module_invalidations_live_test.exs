defmodule TuistWeb.ModuleInvalidationsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

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

    html = render_async(lv)

    assert has_element?(lv, "#all-modules-table")
    assert html =~ "Core"
  end
end
