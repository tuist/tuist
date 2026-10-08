defmodule TuistWeb.LlmsTxtControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Docs
  alias Tuist.Docs.CLI
  alias Tuist.Docs.Paths
  alias Tuist.KeyValueStore
  alias TuistWeb.Utilities.MarketingMarkdown

  setup do
    stub(CLI, :get_pages, fn -> [] end)
    stub(KeyValueStore, :get_or_update, fn _key, _opts, build -> build.() end)
    :ok
  end

  describe "GET /llms.txt" do
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

    test "links to the full documentation export", %{conn: conn} do
      body = conn |> get("/llms.txt") |> response(200)

      assert body =~ "[Full documentation](#{Tuist.Environment.app_url(path: "/llms-full.txt")})"
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

  describe "GET /llms-full.txt" do
    test "serves a public, cached plain-text Markdown document", %{conn: conn} do
      conn = get(conn, "/llms-full.txt")
      body = response(conn, 200)

      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]

      assert String.starts_with?(
               body,
               "# Tuist\n\n> Tuist is build infrastructure for productive teams."
             )
    end

    test "includes the full Markdown source of every English documentation page", %{conn: conn} do
      body = conn |> get("/llms-full.txt") |> response(200)
      pages = Docs.pages()
      assert pages != []

      for page <- pages do
        url = Tuist.Environment.app_url(path: Paths.markdown_path_from_slug(page.slug))
        assert body =~ "# #{page.title}\n\nSource: #{url}\n\n#{page.markdown}"
      end
    end

    test "includes CLI reference pages in slug order and excludes other locales", %{conn: conn} do
      stub(CLI, :get_pages, fn ->
        [
          %{slug: "/en/cli/zzz", title: "Last command", markdown: "Last command source."},
          %{slug: "/es/cli/aaa", title: "Excluded command", markdown: "Excluded source."},
          %{
            slug: "/en/cli/aaa",
            title: "First command",
            markdown: "First command source.\n\nSource: [upstream](https://example.com/source)"
          }
        ]
      end)

      body = conn |> get("/llms-full.txt") |> response(200)
      assert body =~ "First command source."
      assert body =~ "Source: [upstream](https://example.com/source)"
      assert body =~ "Last command source."
      refute body =~ "Excluded source."
      refute body =~ "/es/docs-markdown/"

      source_urls = Regex.scan(~r/^# [^\n]+\n\nSource: (https?:\/\/\S+)\n\n/m, body, capture: :all_but_first)
      assert source_urls == Enum.sort(source_urls)
      assert source_urls == Enum.uniq(source_urls)
      assert body =~ "\n\n---\n\n"
    end

    test "memoizes the full export separately from the index for one hour", %{conn: conn} do
      expect(KeyValueStore, :get_or_update, fn key, opts, _build ->
        assert key == [TuistWeb.Utilities.LlmsTxt, "llms_full_txt"]
        assert opts[:ttl] == to_timeout(hour: 1)
        "Cached documentation"
      end)

      assert conn |> get("/llms-full.txt") |> response(200) == "Cached documentation"
    end
  end
end
