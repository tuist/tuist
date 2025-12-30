defmodule TuistWeb.ModuleCacheLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.CommandEventsFixtures

  describe "module cache page" do
    test "displays analytics widgets", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-01-01 10:20:30Z] end)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A", "B"],
        remote_cache_target_hits: ["C"],
        created_at: ~N[2024-01-01 03:00:00]
      )

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/module-cache")

      # Then
      assert has_element?(lv, "#widget-cache-hit-rate")
      assert has_element?(lv, "#widget-cache-hits")
      assert has_element?(lv, "#widget-cache-misses")
    end
  end
end
