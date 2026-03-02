defmodule TuistWeb.DocsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /docs/en/*" do
    test "renders a documentation page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/docs/en/guides/install-tuist")

      assert html =~ "Install Tuist"
    end

    test "renders the three-column layout with sidebar and TOC", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/docs/en/guides/install-tuist")

      assert html =~ ~s(data-part="docs-layout")
      assert html =~ ~s(data-part="docs-sidebar")
      assert html =~ ~s(data-part="docs-toc")
      assert html =~ ~s(data-part="docs-body")
    end

    test "returns not found for excluded pages", %{conn: conn} do
      assert_raise TuistWeb.Errors.NotFoundError, fn ->
        live(conn, "/docs/en/cli/build")
      end
    end
  end

  describe "legacy redirects" do
    test "redirects old docs path to the current path", %{conn: conn} do
      conn = get(conn, "/docs/guides/quick-start/install-tuist")

      assert redirected_to(conn, 301) == "/docs/en/guides/install-tuist"
    end

    test "preserves query strings while redirecting", %{conn: conn} do
      conn = get(conn, "/docs/guides/quick-start/install-tuist?ref=old-url")

      assert redirected_to(conn, 301) == "/docs/en/guides/install-tuist?ref=old-url"
    end
  end
end
