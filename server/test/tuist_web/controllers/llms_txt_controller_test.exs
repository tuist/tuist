defmodule TuistWeb.LlmsTxtControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

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

      for path <- ["/cache", "/build-insights", "/selective-testing", "/flaky-tests", "/test-insights", "/previews"] do
        assert body =~ "(#{Tuist.Environment.app_url(path: path)})"
      end
    end
  end
end
