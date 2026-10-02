defmodule AtlasWeb.DocsControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias AtlasWeb.DocsHTML

  test "documentation is public and marked for the shared crawler rate limits", %{conn: conn} do
    for page <- DocsHTML.pages() do
      response = get(conn, "/docs/#{page.slug}")
      document = response |> html_response(200) |> LazyHTML.from_document()
      assert LazyHTML.query(document, "#docs-content") |> Enum.count() == 1
      assert LazyHTML.query(document, "#docs-sidebar [aria-current=page]") |> Enum.count() == 1
      assert get_resp_header(response, "x-tuist-public") == ["1"]
      assert get_resp_header(response, "x-robots-tag") == ["index, follow"]
      assert get_resp_header(response, "set-cookie") == []
    end
  end

  test "unfinished documentation is unavailable in both formats", %{conn: conn} do
    for slug <- ~w(self-hosting installation first-administrator development configuration integrations workspace) do
      assert response(get(conn, "/docs/#{slug}"), 404)
      assert response(get(conn, "/docs-markdown/#{slug}"), 404)
    end
  end

  test "unknown documentation paths do not fall through to the application", %{conn: conn} do
    conn = get(conn, "/docs/missing/page")
    assert response(conn, 404)
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
  end

  test "anonymous root visits reach documentation while application routes stay protected", %{conn: conn} do
    assert redirected_to(get(conn, "/")) == "/docs"
    assert redirected_to(get(conn, "/admin/users")) == "/login"
    assert get_resp_header(get(conn, "/admin/users"), "x-tuist-public") == []
  end

  test "every table of contents target exists in the rendered document", %{conn: conn} do
    for page <- DocsHTML.pages() do
      document = conn |> get("/docs/#{page.slug}") |> html_response(200) |> LazyHTML.from_document()

      for heading <- page.headings do
        assert LazyHTML.query(document, "h2##{heading.id}") |> Enum.count() == 1
      end
    end
  end

  test "documentation negotiates Markdown and varies cached responses by Accept", %{conn: conn} do
    for accept <- [
          "text/markdown",
          "text/markdown; charset=utf-8",
          "text/html;q=0.4, text/markdown;q=0.9",
          "text/html;q=0, */*;q=0.5, text/markdown;q=0.4"
        ] do
      response = conn |> put_req_header("accept", accept) |> get("/docs")
      assert response(response, 200) == DocsHTML.page("").markdown
      assert get_resp_header(response, "content-type") == ["text/markdown; charset=utf-8"]
      assert get_resp_header(response, "vary") == ["Accept"]
    end

    for accept <- ["text/html", "*/*", "text/html, text/markdown;q=0", "text/html;q=1, text/markdown;q=0.2"] do
      response = conn |> put_req_header("accept", accept) |> get("/docs")
      assert html_response(response, 200)
      assert get_resp_header(response, "vary") == ["Accept"]
    end
  end

  test "the plain-text page is the same source used by the copy action", %{conn: conn} do
    response = get(conn, "/docs-markdown")
    assert response(response, 200) == DocsHTML.page("").markdown
    assert get_resp_header(response, "content-type") == ["text/plain; charset=utf-8"]
    assert response(get(conn, "/docs-markdown/missing"), 404)
  end

  test "overview keeps page-copy controls without premature deployment navigation", %{conn: conn} do
    document = conn |> get("/docs") |> html_response(200) |> LazyHTML.from_document()
    assert Enum.empty?(LazyHTML.query(document, "#docs-nav-tabs, [data-part=hero-cards]"))
    assert Enum.count(LazyHTML.query(document, "#docs-sidebar a")) == 1
    assert Enum.count(LazyHTML.query(document, "[data-part=admonition][data-status=information]")) == 1
    assert Enum.count(LazyHTML.query(document, "#docs-copy-dropdown")) == 1
    assert Enum.count(LazyHTML.query(document, "#docs-mobile-copy-dropdown")) == 1
  end

  test "trailing slashes share the overview canonical address", %{conn: conn} do
    document = conn |> get("/docs/") |> html_response(200) |> LazyHTML.from_document()
    assert Enum.count(LazyHTML.query(document, "link[rel=canonical][href$='/docs']")) == 1
    assert Enum.count(LazyHTML.query(document, "meta[property='og:url'][content$='/docs']")) == 1
  end

  test "every page advertises a page-specific social preview", %{conn: conn} do
    for page <- DocsHTML.pages() do
      document = conn |> get("/docs/#{page.slug}") |> html_response(200) |> LazyHTML.from_document()
      name = if(page.slug == "", do: "overview", else: page.slug)
      assert Enum.count(LazyHTML.query(document, "meta[property='og:image'][content$='/#{name}.png']")) == 1
      assert Enum.count(LazyHTML.query(document, "meta[name='twitter:card'][content='summary_large_image']")) == 1
    end
  end
end
