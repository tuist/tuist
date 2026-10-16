defmodule TuistWeb.Plugs.MarkdownNegotiationPlugTest do
  use ExUnit.Case, async: true
  use TuistWeb, :verified_routes
  use Mimic

  import Phoenix.ConnTest
  import Plug.Conn

  alias Tuist.Docs
  alias TuistWeb.Plugs.MarkdownNegotiationPlug
  alias TuistWeb.Utilities.MarketingMarkdown

  @endpoint TuistWeb.Endpoint

  setup do
    # The home page checks its redesign flag; this case runs without a DB
    # sandbox, so keep the lookup away from FunWithFlags' Ecto store.
    stub(FunWithFlags, :enabled?, fn _flag -> false end)
    :ok
  end

  test "marketing pages negotiate markdown for agent requests" do
    conn =
      build_conn()
      |> put_req_header("accept", "text/markdown")
      |> get(~p"/")

    body = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["text/markdown; charset=utf-8"]
    assert Enum.any?(get_resp_header(conn, "vary"), &String.contains?(&1, "Accept"))
    assert [token_estimate] = get_resp_header(conn, "x-markdown-tokens")
    assert String.to_integer(token_estimate) > 0
    assert body == MarketingMarkdown.get("/")
    assert get_resp_header(conn, "content-language") == ["en"]
    assert get_resp_header(conn, "cloudflare-cdn-cache-control") == ["no-store"]
    refute body =~ "<html"
  end

  test "marketing pages keep HTML as the default representation" do
    conn = get(build_conn(), ~p"/")

    assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    assert Enum.any?(get_resp_header(conn, "vary"), &String.contains?(&1, "Accept"))
    assert get_resp_header(conn, "x-markdown-tokens") == []
    body = html_response(conn, 200)
    assert body =~ "Tuist"
    assert body =~ ~s(type="text/markdown")
    assert body =~ ~s(href="#{Tuist.Environment.app_url(path: "/marketing-markdown")}")
    assert get_resp_header(conn, "cloudflare-cdn-cache-control") == []
    assert Enum.any?(get_resp_header(conn, "link"), &String.contains?(&1, ~s(rel="alternate")))
    assert Enum.any?(get_resp_header(conn, "link"), &String.contains?(&1, ~s(rel="api-catalog")))
  end

  test "authored guides override rendered HTML on every covered page" do
    for path <- MarketingMarkdown.paths() do
      conn = negotiated_response(path, "text/markdown", 200, "<html><main>Landing page copy</main></html>")

      assert conn.resp_body == MarketingMarkdown.get(path)
      assert get_resp_header(conn, "content-language") == ["en"]
      assert get_resp_header(conn, "cloudflare-cdn-cache-control") == ["no-store"]
    end
  end

  test "negotiation respects explicit media types and quality preferences" do
    for accept <- [
          "text/html, text/markdown;q=0",
          "text/html;q=1, text/markdown;q=0.5",
          "text/markdown-extra, text/html",
          "text/markdown;q=0.5, */*;q=1",
          "text/markdown;q=0.5, text/*;q=1"
        ] do
      conn = negotiated_response("/cache", accept, 200, "<html>Original HTML</html>")
      assert conn.resp_body == "<html>Original HTML</html>"
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
      assert get_resp_header(conn, "cloudflare-cdn-cache-control") == []
    end

    for accept <- [
          "TEXT/MARKDOWN",
          "text/html;q=0.5, text/markdown;q=0.9",
          "text/markdown; charset=utf-8",
          "text/markdown, */*"
        ] do
      conn = negotiated_response("/cache", accept, 200, "<html>Original HTML</html>")
      assert conn.resp_body == MarketingMarkdown.get("/cache")
    end
  end

  test "redirects and error responses never become a successful-looking product guide" do
    for status <- [301, 302, 403, 404, 500] do
      conn = negotiated_response("/cache", "text/markdown", status, "<html>Not a product page</html>")
      assert conn.status == status
      assert conn.resp_body == "<html>Not a product page</html>"
      assert get_resp_header(conn, "x-markdown-tokens") == []
      assert get_resp_header(conn, "link") == []
      assert get_resp_header(conn, "cloudflare-cdn-cache-control") == []
    end
  end

  test "uncovered marketing pages retain HTML conversion" do
    conn =
      negotiated_response(
        "/blog/example",
        "text/markdown",
        200,
        "<main><h1>Example post</h1><p>Useful content</p></main>"
      )

    assert conn.resp_body =~ "# Example post"
    assert conn.resp_body =~ "Useful content"
    refute conn.resp_body =~ "<main>"
    assert get_resp_header(conn, "cloudflare-cdn-cache-control") == ["no-store"]
  end

  test "localized marketing pages do not get an English override" do
    conn = negotiated_response("/de/cache", "text/markdown", 200, "<main><h1>Localized content</h1></main>")

    assert conn.resp_body =~ "# Localized content"
    assert get_resp_header(conn, "content-language") == []
    assert get_resp_header(conn, "link") == []
    assert get_resp_header(conn, "cloudflare-cdn-cache-control") == ["no-store"]
  end

  test "HTML responses preserve the existing CDN cache policy" do
    conn =
      :get
      |> Plug.Test.conn("/cache")
      |> put_req_header("accept", "text/html")
      |> MarkdownNegotiationPlug.call([])
      |> put_resp_content_type("text/html")
      |> put_resp_header("cloudflare-cdn-cache-control", "public, max-age=60")
      |> send_resp(200, "Original HTML")

    assert conn.resp_body == "Original HTML"
    assert get_resp_header(conn, "cloudflare-cdn-cache-control") == ["public, max-age=60"]
  end

  test "unconverted responses do not receive the Markdown CDN policy" do
    conn =
      :get
      |> Plug.Test.conn("/blog/example")
      |> put_req_header("accept", "text/markdown")
      |> MarkdownNegotiationPlug.call([])
      |> put_resp_content_type("application/json")
      |> send_resp(200, ~s({"ok":true}))

    assert conn.resp_body == ~s({"ok":true})
    assert get_resp_header(conn, "cloudflare-cdn-cache-control") == []
  end

  test "HEAD Markdown responses also bypass the CDN cache" do
    conn =
      :head
      |> Plug.Test.conn("/cache")
      |> put_req_header("accept", "text/markdown")
      |> MarkdownNegotiationPlug.call([])
      |> put_resp_content_type("text/html")
      |> send_resp(200, "Original HTML")

    assert get_resp_header(conn, "content-type") == ["text/markdown; charset=utf-8"]
    assert get_resp_header(conn, "cloudflare-cdn-cache-control") == ["no-store"]
  end

  test "POST responses are not negotiated" do
    conn =
      :post
      |> Plug.Test.conn("/cache")
      |> put_req_header("accept", "text/markdown")
      |> MarkdownNegotiationPlug.call([])
      |> put_resp_content_type("text/html")
      |> send_resp(200, "Unchanged")

    assert conn.resp_body == "Unchanged"
    assert get_resp_header(conn, "vary") == []
  end

  test "docs pages negotiate markdown for agent requests" do
    expected_markdown = Docs.get_page("en", ["guides", "install-tuist"]).markdown

    conn =
      build_conn()
      |> put_req_header("accept", "text/markdown")
      |> get(~p"/en/docs/guides/install-tuist")

    body = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["text/markdown; charset=utf-8"]
    assert Enum.any?(get_resp_header(conn, "vary"), &String.contains?(&1, "Accept"))
    assert [token_estimate] = get_resp_header(conn, "x-markdown-tokens")
    assert String.to_integer(token_estimate) > 0
    assert body == expected_markdown
    assert get_resp_header(conn, "cloudflare-cdn-cache-control") == ["no-store"]
    refute body =~ "<html"
  end

  test "docs HTML responses retain their existing CDN behavior" do
    conn = get(build_conn(), ~p"/en/docs/guides/install-tuist")

    assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    assert get_resp_header(conn, "cloudflare-cdn-cache-control") == []
  end

  test "explicit docs markdown route returns markdown content type" do
    conn = get(build_conn(), "/en/docs-markdown/guides/install-tuist")
    body = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["text/markdown; charset=utf-8"]
    assert [token_estimate] = get_resp_header(conn, "x-markdown-tokens")
    assert String.to_integer(token_estimate) > 0
    assert body =~ "# Install Tuist"
    assert get_resp_header(conn, "cloudflare-cdn-cache-control") == []
  end

  defp negotiated_response(path, accept, status, body) do
    :get
    |> Plug.Test.conn(path)
    |> put_req_header("accept", accept)
    |> MarkdownNegotiationPlug.call([])
    |> put_resp_content_type("text/html")
    |> send_resp(status, body)
  end
end
