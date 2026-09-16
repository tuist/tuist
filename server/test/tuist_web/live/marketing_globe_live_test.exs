defmodule TuistWeb.Marketing.MarketingGlobeLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Marketing.CacheGlobe
  alias Tuist.Marketing.Stats

  test "public page renders without authentication and receives aggregate updates", %{conn: conn} do
    stub(Stats, :get_globe, fn -> CacheGlobe.empty() end)
    {:ok, view, html} = live(conn, ~p"/globe")

    assert html =~ "Built once."
    assert has_element?(view, "#cache-globe[data-demo=false]")
    assert has_element?(view, "a[href='/cache']")
    refute html =~ "marketing-footer"

    send(view.pid, {:cache_globe_updated, %{CacheGlobe.empty() | downloads: 321}})

    assert render(view) =~ "&quot;downloads&quot;:321"
  end

  test "demo mode is explicit and offers a return to live activity", %{conn: conn} do
    stub(Stats, :get_globe, fn -> CacheGlobe.empty() end)
    {:ok, view, html} = live(conn, ~p"/globe?demo=true")

    assert has_element?(view, "#cache-globe[data-demo=true]")
    assert html =~ "Demo · illustrative data"
    assert has_element?(view, "a[href='/globe']", "View live activity")
  end
end
