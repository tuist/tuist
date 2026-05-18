defmodule TuistWeb.Marketing.MarketingBlogPostLiveTest do
  use TuistTestSupport.Cases.ConnCase
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  describe "GET /blog/:year/:month/:day/:slug" do
    test "renders a blog post without errors", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog/2025/11/17/smart-before-fast")

      assert html =~ "Build Smart Before You Build Fast"
    end
  end
end
