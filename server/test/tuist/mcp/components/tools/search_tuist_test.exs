defmodule Tuist.MCP.Components.Tools.SearchTuistTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.MCP.Components.Tools.SearchTuist
  alias Tuist.MCP.Search

  test "description guides agents to start with public Tuist material" do
    description = SearchTuist.description()

    assert description =~ "Call this first whenever the user asks a Tuist question"
    assert description =~ "before inspecting local files or using general web search"
    assert description =~ "links to cite"
    assert description =~ "source tools"
  end

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

  test "returns structured release metadata" do
    arguments = %{"query" => "result bundle", "source" => "releases"}

    expect(Search, :search, fn ^arguments ->
      {:ok,
       %{
         "query" => arguments["query"],
         "results" => [
           %{
             "source" => "releases",
             "title" => "CLI 4.202.2",
             "url" => "https://github.com/tuist/tuist/releases/tag/4.202.2",
             "snippet" => "Reassemble the requested result bundle.",
             "product" => "CLI",
             "version" => "4.202.2",
             "published_at" => "2026-07-13T16:02:02Z",
             "prerelease" => false
           }
         ]
       }}
    end)

    result = SearchTuist.call(%Plug.Conn{}, arguments)

    assert %{
             "structuredContent" => %{
               "results" => [
                 %{
                   "source" => "releases",
                   "product" => "CLI",
                   "version" => "4.202.2",
                   "published_at" => "2026-07-13T16:02:02Z",
                   "prerelease" => false
                 }
               ]
             }
           } = result
  end
end
