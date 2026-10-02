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

    assert html =~ "Cache download requests today"
    assert has_element?(view, "#marketing-globe[data-demo=false]")
    assert has_element?(view, "#marketing-globe-canvas[phx-hook=DitherGlobe]")
    assert has_element?(view, "#marketing-globe [data-part=navbar] a[href='/']")
    assert has_element?(view, "#globe-flaps[phx-hook=SplitFlap]")
    assert has_element?(view, "#marketing-globe [data-part=regions] [data-region=eu-west]")
    refute html =~ "marketing-navbar"
    refute html =~ "marketing-footer"
    refute html =~ "support/chat.js"
    assert html =~ "fonts.googleapis.com/css2?family=Geist+Pixel"

    send(view.pid, {:cache_globe_updated, %{CacheGlobe.empty() | downloads: 321}})

    assert render(view) =~ "&quot;downloads&quot;:321"
  end

  test "live and demo requests are counted by the Cloudflare public-page limits", %{conn: conn} do
    stub(Stats, :get_globe, fn -> CacheGlobe.empty() end)

    for path <- [~p"/globe", ~p"/globe?demo=true"] do
      response = get(conn, path)
      assert response.status == 200
      assert get_resp_header(response, "x-tuist-public") == ["1"]
    end
  end

  test "demo mode is explicit and offers a return to live activity", %{conn: conn} do
    stub(Stats, :get_globe, fn -> CacheGlobe.empty() end)
    {:ok, view, html} = live(conn, ~p"/globe?demo=true")

    assert has_element?(view, "#marketing-globe[data-demo=true]")
    assert html =~ "Demo · illustrative data"
    assert has_element?(view, "a[href='/globe']", "View live activity")
  end
end
