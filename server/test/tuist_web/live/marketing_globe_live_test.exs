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
    assert has_element?(view, "#marketing-globe[data-demo=false][data-illustrative-arcs=true]")
    assert has_element?(view, "#globe-status [data-status=live]", "Cache activity")
    assert html =~ "Cache downloads served today, including repeated and partial requests."
    refute html =~ "Arcs estimate request origins and replay reported activity"
    assert has_element?(view, "#marketing-globe-canvas[phx-hook=DitherGlobe]")
    assert has_element?(view, "#marketing-globe [data-part=navbar] a[href='/']")
    assert has_element?(view, "#globe-flaps[phx-hook=SplitFlap]")
    assert has_element?(view, "#marketing-globe [data-part=regions][hidden] [data-region=eu-west][hidden]")
    refute html =~ "marketing-navbar"
    refute html =~ "marketing-footer"
    refute html =~ "support/chat.js"
    assert html =~ "fonts.googleapis.com/css2?family=Geist+Pixel"

    send(view.pid, {:cache_globe_updated, %{CacheGlobe.empty() | downloads: 321, breakdown: %{"all" => 75.0}}})

    assert render(view) =~ "&quot;downloads&quot;:321"
    assert render(view) =~ "&quot;breakdown&quot;:{&quot;all&quot;:75.0}"
  end

  test "only regions with measured daily downloads are initially visible", %{conn: conn} do
    snapshot = CacheGlobe.empty()

    snapshot = %{
      snapshot
      | downloads: 10,
        regions:
          Enum.map(snapshot.regions, fn region ->
            if region.id == "eu-west", do: %{region | downloads: 10}, else: region
          end)
    }

    stub(Stats, :get_globe, fn -> snapshot end)
    {:ok, view, _html} = live(conn, ~p"/globe")

    assert has_element?(view, "#marketing-globe [data-part=regions]:not([hidden])")
    assert has_element?(view, "#globe-region-eu-west:not([hidden])")
    assert has_element?(view, "#globe-region-sa-west[hidden]")
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
    assert has_element?(view, "#marketing-globe [data-part=regions]:not([hidden])")
    assert has_element?(view, "#globe-region-sa-west:not([hidden])")
    assert html =~ "Demo · illustrative data"
    assert has_element?(view, "a[href='/globe']", "View live activity")
  end
end
