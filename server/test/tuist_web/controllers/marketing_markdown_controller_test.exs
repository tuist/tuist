defmodule TuistWeb.MarketingMarkdownControllerTest do
  use ExUnit.Case, async: true
  use TuistWeb, :verified_routes

  import Phoenix.ConnTest
  import Plug.Conn

  alias TuistWeb.Utilities.MarketingMarkdown

  @endpoint TuistWeb.Endpoint

  test "every decision guide has a header-free Markdown URL" do
    for path <- MarketingMarkdown.paths() do
      conn = get(build_conn(), MarketingMarkdown.alternate_path(path))

      assert response(conn, 200) == MarketingMarkdown.get(path)
      assert get_resp_header(conn, "content-type") == ["text/markdown; charset=utf-8"]
      assert get_resp_header(conn, "content-language") == ["en"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]
      assert get_resp_header(conn, "x-tuist-public") == ["1"]
      assert get_resp_header(conn, "vary") == []
      assert get_resp_header(conn, "set-cookie") == []
      assert get_resp_header(conn, "cloudflare-cdn-cache-control") == []
      assert [tokens] = get_resp_header(conn, "x-markdown-tokens")
      assert String.to_integer(tokens) > 0
    end
  end

  test "unknown paths do not fall through to a project or expose arbitrary files" do
    for path <- [
          "missing",
          "en/cache",
          "nested/cache",
          "home.md",
          "files/terms",
          "newsletter/verify",
          "compare/index",
          "compare/AGENTS",
          "solutions/AGENTS",
          "solutions/missing"
        ] do
      conn = get(build_conn(), "/marketing-markdown/" <> path)

      assert response(conn, 404) == "Page not found"
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  test "original statements are served separately from their decision guides" do
    for path <- ["community", "openness", "longevity", "security"] do
      conn = get(build_conn(), "/marketing-markdown/source/" <> path)
      assert response(conn, 200) == MarketingMarkdown.source("/" <> path)
      refute conn.resp_body == MarketingMarkdown.get("/" <> path)
      assert get_resp_header(conn, "content-language") == ["en"]
    end

    conn = get(build_conn(), "/marketing-markdown/source/cache")
    assert response(conn, 404) == "Page not found"
  end

  test "English guides ignore language preferences and tracking parameters" do
    conn =
      build_conn()
      |> put_req_header("accept-language", "de")
      |> get("/marketing-markdown/cache?utm_source=agent")

    assert response(conn, 200) == MarketingMarkdown.get("/cache")
    assert get_resp_header(conn, "content-language") == ["en"]
  end

  test "problem and comparison guides remain Markdown regardless of browser or language preferences" do
    for page <- MarketingMarkdown.decision_guides() do
      conn =
        build_conn()
        |> put_req_header("accept", "text/html")
        |> put_req_header("accept-language", "ko")
        |> get(MarketingMarkdown.alternate_path(page.path) <> "?utm_source=agent")

      assert response(conn, 200) == MarketingMarkdown.get(page.path)
      assert get_resp_header(conn, "content-type") == ["text/markdown; charset=utf-8"]
      assert get_resp_header(conn, "content-language") == ["en"]
      assert get_resp_header(conn, "set-cookie") == []
    end
  end

  test "HEAD has the same representation headers without a response body" do
    conn = head(build_conn(), "/marketing-markdown/cache")

    assert response(conn, 200) == ""
    assert get_resp_header(conn, "content-type") == ["text/markdown; charset=utf-8"]
    assert get_resp_header(conn, "x-markdown-tokens") != []
  end
end
