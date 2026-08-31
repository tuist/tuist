defmodule TuistWeb.RobotsTxtControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  describe "GET /robots.txt" do
    test "returns runtime content signals for public marketing and docs routes", %{conn: conn} do
      conn = get(conn, "/robots.txt")
      body = response(conn, 200)

      assert body =~ "Content-Signal: ai-train=no, search=no, ai-input=no"
      assert body =~ "Content-Usage: /$ train-ai=y, search=y, ai-input=y"
      assert body =~ "Content-Usage: /blog train-ai=y, search=y, ai-input=y"
      assert body =~ "Content-Usage: /customers train-ai=y, search=y, ai-input=y"
      assert body =~ "Content-Usage: /en/docs train-ai=y, search=y, ai-input=y"
      assert body =~ "Content-Usage: /en/docs-markdown train-ai=y, search=y, ai-input=y"
      assert body =~ "Disallow: /api/"
      assert body =~ "Disallow: /docs"
      assert body =~ "Disallow: /*/module-cache"

      refute body =~ "Content-Usage: /docs/login"
      refute body =~ "Content-Usage: /marketing"
      refute body =~ "Disallow: /robots.txt"
      refute body =~ "Disallow: /.well-known/api-catalog"
      refute body =~ "Disallow: /live/"
      refute body =~ "Disallow: /*/cache-runs"

      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    end

    test "points crawlers at the sitemap", %{conn: conn} do
      conn = get(conn, "/robots.txt")

      assert response(conn, 200) =~ "Sitemap: #{Tuist.Environment.app_url(path: "/sitemap.xml")}"
    end

    test "opts llms.txt into the public content usage", %{conn: conn} do
      conn = get(conn, "/robots.txt")

      assert response(conn, 200) =~ "Content-Usage: /llms.txt$ train-ai=y, search=y, ai-input=y"
    end
  end
end
