defmodule TuistWeb.LlmsTxtControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Docs.CLI
  alias TuistWeb.Utilities.MarketingMarkdown

  describe "GET /llms.txt" do
    # The index walks every documentation page, and the command-line pages are
    # fetched from the latest GitHub release. Stub them so the test does not
    # depend on the network.
    setup do
      stub(CLI, :get_pages, fn -> [] end)
      :ok
    end

    test "serves the index as plain text instead of redirecting to the login page", %{conn: conn} do
      conn = get(conn, "/llms.txt")

      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    end

    test "opens with the title and summary the llms.txt format expects", %{conn: conn} do
      body = conn |> get("/llms.txt") |> response(200)

      assert String.starts_with?(body, "# Tuist\n")
      assert body =~ "\n> Tuist is build infrastructure for productive teams."
    end

    test "qualifies selective testing and optional runner availability", %{conn: conn} do
      body = conn |> get("/llms.txt") |> response(200)

      assert body =~ "Selective testing skips unchanged test targets in Tuist-generated Xcode projects"
      assert body =~ "Managed runners are optional and currently invite-only"
      refute body =~ "run only the tests a change can affect"
    end

    test "indexes problem and comparison guides with their explicit Markdown URLs", %{conn: conn} do
      body = conn |> get("/llms.txt") |> response(200)
      assert body =~ "## Solve a problem"
      assert body =~ "## Comparisons"

      for page <- MarketingMarkdown.public_pages() do
        url = Tuist.Environment.app_url(path: MarketingMarkdown.alternate_path(page.path))
        assert body =~ "[#{page.title}](#{url})"
        refute body =~ "(#{Tuist.Environment.app_url(path: page.path)})"
      end

      refute body =~ "/compare/index"
      refute body =~ "/solutions/AGENTS"
      refute body =~ "/compare/AGENTS"
    end

    test "links documentation pages to their markdown twin", %{conn: conn} do
      body = conn |> get("/llms.txt") |> response(200)

      assert body =~ "## Documentation"
      assert body =~ Tuist.Environment.app_url(path: "/en/docs-markdown/guides/features/cache")
      refute body =~ Tuist.Environment.app_url(path: "/en/docs/guides/features/cache") <> ")"
    end

    test "delimits every link list with an H2, as the llms.txt format requires", %{conn: conn} do
      body = conn |> get("/llms.txt") |> response(200)

      headings = body |> String.split("\n") |> Enum.filter(&String.starts_with?(&1, "#"))

      refute Enum.any?(headings, &String.starts_with?(&1, "###"))

      # Every H2 section must contain the list of links directly beneath it.
      body
      |> String.split("\n## ")
      |> Enum.drop(1)
      |> Enum.each(fn section ->
        assert Enum.any?(String.split(section, "\n"), &String.starts_with?(&1, "- "))
      end)
    end

    test "lists the product pages that carry the marketing content", %{conn: conn} do
      body = conn |> get("/llms.txt") |> response(200)

      assert body =~ "## Product"

      for path <- ["", "/cache", "/compute", "/tests", "/previews", "/pricing"] do
        assert body =~ "(#{Tuist.Environment.app_url(path: "/marketing-markdown" <> path)})"
      end

      assert body =~ "Accept: text/markdown"
      refute body =~ "(#{Tuist.Environment.app_url(path: "/flaky-tests")})"
      refute body =~ "(#{Tuist.Environment.app_url(path: "/test-insights")})"
    end
  end
end
