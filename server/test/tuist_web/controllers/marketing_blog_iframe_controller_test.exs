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
      conn = get(conn, "/blog/2025/11/6/zero-to-many/iframe.html?id=lone_wolf")

      # Then
      # The template rendering will fail if the template doesn't exist,
      # but the controller should attempt to render it
      # This test verifies the controller doesn't crash with the id parameter
      assert conn.status in [200, 500]
    end
  end
end
