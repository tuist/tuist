defmodule TuistWeb.Marketing.MarketingCacheLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /cache" do
    test "renders the page with the marketing stylesheet", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/cache")

      assert html =~ "/marketing/assets/bundle.css"
      assert html =~ "Never build the"
      assert html =~ "Everything you&#39;d want from a cache"
    end
  end
end
