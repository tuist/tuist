defmodule Tuist.MCP.Components.Tools.SearchTuistTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.MCP.Components.Tools.SearchTuist
  alias Tuist.MCP.Search

  test "search_tuist forwards searches to the Typesense-backed search" do
    arguments = %{"query" => "how does selective testing work?", "source" => "docs", "max_results" => 4}

    expect(Search, :search, fn ^arguments ->
      {:ok,
       %{
         "query" => arguments["query"],
         "results" => [
           %{
             "source" => "docs",
             "title" => "Selective testing",
             "url" => "https://tuist.dev/en/docs/guides/features/selective-testing",
             "snippet" => "Selective testing skips unchanged test targets."
           }
         ]
       }}
    end)

    result = SearchTuist.call(%Plug.Conn{}, arguments)

    assert %{
             "content" => [%{"type" => "text", "text" => text}],
             "structuredContent" => %{
               "results" => [%{"title" => "Selective testing", "source" => "docs"}]
             }
           } = result

    assert %{"results" => [%{"url" => "https://tuist.dev/en/docs/guides/features/selective-testing"}]} =
             JSON.decode!(text)
  end

  test "returns search errors as tool errors" do
    stub(Search, :search, fn _arguments -> {:error, "Tuist search is unavailable: timeout"} end)

    result = SearchTuist.call(%Plug.Conn{}, %{"query" => "cache"})

    assert %{
             "content" => [%{"type" => "text", "text" => "Tuist search is unavailable: timeout"}],
             "isError" => true
           } = result
  end
end
