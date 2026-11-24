defmodule TuistWeb.RobotsTxtControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.Docs
  alias TuistWeb.Utilities.MarketingMarkdown
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
      assert body =~ "Content-Usage: /marketing-markdown train-ai=y, search=y, ai-input=y"
      assert body =~ "Disallow: /api/"
      assert body =~ "Disallow: /docs"
      assert body =~ "Disallow: /*/settings"
      refute body =~ "Disallow: /*/module-cache"

      refute body =~ "Content-Usage: /docs/login"
      refute body =~ "Content-Usage: /marketing "
      refute body =~ "Content-Usage: /marketing$ "
      refute body =~ "Disallow: /robots.txt"
      refute body =~ "Disallow: /.well-known/api-catalog"
      refute body =~ "Disallow: /live/"
      refute body =~ "Disallow: /*/cache-runs"

      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    end

    test "opts decision guides and their Markdown into marketing content usage", %{conn: conn} do
      body = conn |> get("/robots.txt") |> response(200)

      public_patterns =
        Regex.scan(~r/^Content-Usage: (\S+) train-ai=y, search=y, ai-input=y$/m, body, capture: :all_but_first)

      landing_pages = ["/runners", MarketingMarkdown.alternate_path("/runners")]

      for page <- MarketingMarkdown.decision_guides(),
          path <- [page.path, MarketingMarkdown.alternate_path(page.path)] do
        assert Enum.any?(public_patterns, fn [pattern] ->
                 if String.ends_with?(pattern, "$") do
                   path == String.trim_trailing(pattern, "$")
                 else
                   String.starts_with?(path, pattern)
                 end
               end)
      end

      for page <- MarketingMarkdown.decision_guides(),
          path <- [page.path, MarketingMarkdown.alternate_path(page.path)] ++ landing_pages do
        assert crawlable?(body, path), "robots.txt blocks #{path}"
      end

      refute crawlable?(body, "/tuist/runners")
      refute crawlable?(body, "/tuist/runners/jobs")
    end

    test "keeps docs pages crawlable when they share a name with a dashboard route", %{conn: conn} do
      body = conn |> get("/robots.txt") |> response(200)

      blocked =
        for slug <- Docs.compiled_slugs(),
            path <- [Docs.Paths.public_path_from_slug(slug), Docs.Paths.markdown_path_from_slug(slug)],
            not crawlable?(body, path),
            do: path

      assert blocked == []
      refute crawlable?(body, "/tuist/projects")
    end

    test "advertises the marketing sitemap but not the challenged project sitemap", %{conn: conn} do
      conn = get(conn, "/robots.txt")

      assert response(conn, 200) =~ "Sitemap: #{Tuist.Environment.app_url(path: "/sitemap.xml")}"
      refute response(conn, 200) =~ "Sitemap: #{Tuist.Environment.app_url(path: "/sitemap-projects.xml")}"
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

    test "lets crawlers follow public legacy redirects and reach the pages behind them" do
      patterns = RobotsTxt.disallow_patterns()

      matches? = fn path ->
        Enum.any?(patterns, fn pattern ->
          regex = pattern |> Regex.escape() |> String.replace("\\*", ".*") |> String.replace("\\$", "$")
          Regex.match?(Regex.compile!("^" <> regex), path)
        end)
      end

      for path <- [
            "/blog/2025/11/27/teaching-ai-to-read-xcode-builds",
            "/blog/2025/11/27/teaching-ai-to-r",
            "/case-studies/acme",
            "/flaky-tests",
            "/rss.xml",
            "/docs/en/guides/quick-start",
            "/pt/docs/guides/features/projects/dependencies"
          ] do
        refute matches?.(path), "robots.txt blocks #{path}"
      end

      assert matches?.("/docs/login")
    end

    test "opts llms.txt and llms-full.txt into the public content usage", %{conn: conn} do
      conn = get(conn, "/robots.txt")

      body = response(conn, 200)

      assert body =~ "Content-Usage: /llms.txt$ train-ai=y, search=y, ai-input=y"
      assert body =~ "Content-Usage: /llms-full.txt$ train-ai=y, search=y, ai-input=y"
      refute body =~ "Disallow: /llms-full.txt"
    end
  end

  # RFC 9309: the longest matching rule wins, and Allow wins a tie.
  defp crawlable?(body, path) do
    rules =
      ~r/^(Allow|Disallow): (\S+)$/m
      |> Regex.scan(body, capture: :all_but_first)
      |> Enum.filter(fn [_, pattern] ->
        regex = pattern |> Regex.escape() |> String.replace("\\*", ".*") |> String.replace("\\$", "$")
        Regex.match?(Regex.compile!("^" <> regex), path)
      end)

    case Enum.max_by(rules, fn [kind, pattern] -> {String.length(pattern), kind == "Allow"} end, fn -> nil end) do
      nil -> true
      [kind, _] -> kind == "Allow"
    end
  end
end
