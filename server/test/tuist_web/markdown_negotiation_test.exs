defmodule TuistWeb.MarkdownNegotiationTest do
  use ExUnit.Case, async: true
  use TuistWeb, :verified_routes

  import Phoenix.ConnTest
  import Plug.Conn

  alias TuistWeb.DocsMarkdown

  @endpoint TuistWeb.Endpoint

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
    assert body =~ "#"
    refute body =~ "<html"
  end

  test "marketing pages keep HTML as the default representation" do
    conn = get(build_conn(), ~p"/")

    assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    assert Enum.any?(get_resp_header(conn, "vary"), &String.contains?(&1, "Accept"))
    assert get_resp_header(conn, "x-markdown-tokens") == []
    assert html_response(conn, 200) =~ "Tuist"
  end

  test "docs pages negotiate markdown for agent requests" do
    {:ok, expected_markdown} = DocsMarkdown.get("en", ["guides", "install-tuist"])

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
    refute body =~ "<html"
  end

  test "explicit docs markdown route returns markdown content type" do
    conn = get(build_conn(), "/en/docs-markdown/guides/install-tuist")
    body = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["text/markdown; charset=utf-8"]
    assert [token_estimate] = get_resp_header(conn, "x-markdown-tokens")
    assert String.to_integer(token_estimate) > 0
    assert body =~ "# Install Tuist"
  end
end
