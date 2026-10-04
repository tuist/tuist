defmodule TuistWeb.RobotsTxtControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias TuistWeb.Utilities.RobotsTxt

  describe "GET /robots.txt" do
    test "returns runtime content signals for public marketing and docs routes", %{conn: conn} do
      conn = get(conn, "/robots.txt")
      body = response(conn, 200)

      assert body =~ "Content-Signal: ai-train=yes, search=yes, ai-input=yes"
      assert body =~ "Content-Usage: /$ train-ai=y, search=y, ai-input=y"
      assert body =~ "Content-Usage: /blog train-ai=y, search=y, ai-input=y"
      assert body =~ "Content-Usage: /customers train-ai=y, search=y, ai-input=y"
      assert body =~ "Content-Usage: /en/docs train-ai=y, search=y, ai-input=y"
      assert body =~ "Content-Usage: /en/docs-markdown train-ai=y, search=y, ai-input=y"
      assert body =~ "Disallow: /api/"
      assert body =~ "Disallow: /docs"
      assert body =~ "Disallow: /*/settings"
      refute body =~ "Disallow: /*/module-cache"

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
      assert response(conn, 200) =~ "Sitemap: #{Tuist.Environment.app_url(path: "/sitemap-projects.xml")}"
    end

    test "does not block public project HTML but keeps utility routes disallowed" do
      patterns = RobotsTxt.disallow_patterns()

      for pattern <- ["/*/builds", "/*/tests", "/*/runs", "/*/previews", "/*/once", "/*/invocations"] do
        refute pattern in patterns
      end

      matches? = fn path ->
        Enum.any?(patterns, fn pattern ->
          regex = pattern |> Regex.escape() |> String.replace("\\*", ".*") |> String.replace("\\$", "$")
          Regex.match?(Regex.compile!("^" <> regex), path)
        end)
      end

      for path <- [
            "/tuist/tuist",
            "/tuist/tuist/builds",
            "/tuist/tuist/tests",
            "/tuist/tuist/module-cache",
            "/tuist/tuist/previews/123",
            "/tuist/tuist/runs/123",
            "/tuist/tuist/once/builds",
            "/tuist/tuist/once-cache",
            "/tuist/tuist/invocations/123",
            "/acme/cache-kit",
            "/acme/settings-ui/builds",
            "/acme/connect-sdk/tests"
          ] do
        refute matches?.(path), "robots.txt blocks #{path}"
      end

      for path <- [
            "/tuist/tuist/settings",
            "/tuist/tuist/settings?tab=general",
            "/tuist/tuist/connect?utm_source=search",
            "/tuist/tuist/runs/123/download",
            "/users/log_in"
          ] do
        assert matches?.(path)
      end
    end

    test "opts llms.txt into the public content usage", %{conn: conn} do
      conn = get(conn, "/robots.txt")

      assert response(conn, 200) =~ "Content-Usage: /llms.txt$ train-ai=y, search=y, ai-input=y"
    end
  end
end
