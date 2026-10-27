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

    test "renders the English template when accessed via a localized route", %{conn: conn} do
      # When
      conn =
        get(conn, "/zh_Hans/blog/2025/11/17/smart-before-fast/iframe.html?id=complexity_wall")

      # Then
      assert response(conn, 200) =~ "viz-container"
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    end

    test "returns 404 when the requested visualization does not exist", %{conn: conn} do
      # When
      conn = get(conn, "/blog/2025/11/17/smart-before-fast/iframe.html?id=does_not_exist")

      # Then
      assert response(conn, 404) == ""
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    end

    test "returns 404 for malformed visualization ids", %{conn: conn} do
      # When
      conn =
        get(conn, "/blog/2025/11/17/smart-before-fast/iframe.html", %{
          "id" => "5712' ORDER BY 1#"
        })

      # Then
      assert response(conn, 404) == ""
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    end
  end
end
