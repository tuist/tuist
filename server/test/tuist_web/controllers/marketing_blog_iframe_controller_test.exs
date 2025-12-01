defmodule TuistWeb.Marketing.MarketingBlogIframeControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  describe "GET /blog/:year/:month/:day/:slug/iframe.html" do
    test "returns empty page when id parameter is missing", %{conn: conn} do
      # When
      conn = get(conn, "/blog/2025/11/17/smart-before-fast/iframe.html")

      # Then
      assert response(conn, 200) == ""
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    end

    test "renders template when id parameter is provided", %{conn: conn} do
      # When
      conn = get(conn, "/blog/2025/11/17/smart-before-fast/iframe.html?id=lone_wolf")

      # Then
      assert response(conn, 200) =~ "viz-container"
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    end
  end
end
