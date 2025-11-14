defmodule TuistWeb.ModuleCacheLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.CommandEvents

  describe "module cache page" do
    test "displays analytics widgets", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      stub(CommandEvents, :cache_hit_rate, fn _, _, _, _ ->
        %{
          cacheable_targets_count: 100,
          local_cache_hits_count: 50,
          remote_cache_hits_count: 30
        }
      end)

      stub(CommandEvents, :cache_hit_rates, fn _, _, _, _, _, _ ->
        [
          %{date: "2024-01-01", cacheable_targets: 100, local_cache_target_hits: 50, remote_cache_target_hits: 30}
        ]
      end)

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/module-cache")

      # Then
      assert has_element?(lv, "#widget-cache-hit-rate")
      assert has_element?(lv, "#widget-cache-hits")
      assert has_element?(lv, "#widget-cache-misses")
    end
  end
end
