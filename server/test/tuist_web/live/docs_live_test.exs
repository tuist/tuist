defmodule TuistWeb.DocsLiveTest do
  use TuistTestSupport.Cases.ConnCase
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  describe "docs overview" do
    test "renders the install card as a clickable link target", %{conn: conn} do
      stub(Req, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: %{"data" => []}}}
      end)

      {:ok, lv, _html} = live(conn, ~p"/en/docs")

      assert has_element?(
               lv,
               ~s([data-part="hero-card"]#docs-install-card[phx-click][role="link"][tabindex="0"])
             )
    end
  end
end
