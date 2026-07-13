defmodule Tuist.MCP.SearchTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.MCP.Search

  defp hit(document, text_match), do: %{"document" => document, "text_match" => text_match}

  test "queries all four collections and normalizes and ranks the hits" do
    expect(Req, :post, fn url, opts ->
      assert String.ends_with?(url, "/multi_search")
      searches = opts[:json]["searches"]
      assert Enum.map(searches, & &1["collection"]) == ["tuist", "projectdescription", "github-issues", "forum-topics"]
      # The docs collection is grouped and locale-filtered.
      docs = Enum.find(searches, &(&1["collection"] == "tuist"))
      assert docs["group_by"] == "url_without_anchor"
      assert docs["filter_by"] == "tags:=en"

      body = %{
        "results" => [
          %{
            "grouped_hits" => [
              %{
                "hits" => [
                  hit(
                    %{
                      "hierarchy" => %{"lvl0" => "Guides", "lvl1" => "Selective testing"},
                      "content" => "Selective testing skips unchanged targets.",
                      "url" => "https://tuist.dev/en/docs/selective-testing"
                    },
                    90
                  )
                ]
              }
            ]
          },
          %{
            "hits" => [
              hit(%{"title" => "Target", "content" => "A build target.", "url" => "https://pd.tuist.dev/target"}, 50)
            ]
          },
          %{"hits" => []},
          %{
            "grouped_hits" => [
              %{
                "hits" => [
                  hit(
                    %{
                      "hierarchy" => %{"lvl0" => "Community", "lvl1" => "Caching help"},
                      "content" => "How to warm the cache.",
                      "url" => "https://community.tuist.dev/t/caching/1"
                    },
                    99
                  )
                ]
              }
            ]
          }
        ]
      }

      {:ok, %Req.Response{status: 200, body: body}}
    end)

    assert {:ok, %{"query" => "caching", "results" => results}} = Search.search(%{"query" => "caching"})

    # Ranked by text_match across collections: forum (99) > docs (90) > api (50).
    assert Enum.map(results, & &1["source"]) == ["forum", "docs", "api_reference"]
    assert Enum.map(results, & &1["title"]) == ["Caching help", "Selective testing", "Target"]
    assert hd(results)["url"] == "https://community.tuist.dev/t/caching/1"
    refute Enum.any?(results, &Map.has_key?(&1, "text_match"))
  end

  test "a single source restricts the collections queried" do
    expect(Req, :post, fn _url, opts ->
      searches = opts[:json]["searches"]
      assert Enum.map(searches, & &1["collection"]) == ["forum-topics"]
      {:ok, %Req.Response{status: 200, body: %{"results" => [%{"hits" => []}]}}}
    end)

    assert {:ok, %{"results" => []}} = Search.search(%{"query" => "cache", "source" => "forum"})
  end

  test "maps a non-200 response to an error" do
    stub(Req, :post, fn _url, _opts -> {:ok, %Req.Response{status: 503, body: ""}} end)

    assert {:error, "Tuist search returned status 503."} = Search.search(%{"query" => "cache"})
  end
end
