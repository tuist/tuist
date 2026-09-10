defmodule TuistWeb.Marketing.MarketingPreviewsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /previews" do
    test "renders the page with the marketing stylesheet", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/previews")

      assert html =~ "/marketing/assets/bundle-new.css"
      assert html =~ "Every change, ready to try"
      assert html =~ "Everything you need to share what you build"
      assert html =~ ~s(<a href="/download" data-part="link">Tuist companion apps</a>)
    end
  end
end
