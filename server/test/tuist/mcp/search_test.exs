defmodule Tuist.MCP.SearchTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.MCP.Search

  defp hit(document, text_match), do: %{"document" => document, "text_match" => text_match}

  test "queries all five collections and normalizes and ranks the hits" do
    expect(Req, :post, fn url, opts ->
      assert String.ends_with?(url, "/multi_search")
      searches = opts[:json]["searches"]

      assert Enum.map(searches, & &1["collection"]) == [
               "tuist",
               "github-releases",
               "projectdescription",
               "github-issues",
               "forum-topics"
             ]

      # The docs collection is grouped and locale-filtered.
      docs = Enum.find(searches, &(&1["collection"] == "tuist"))
      assert docs["group_by"] == "url_without_anchor"
      assert docs["filter_by"] == "tags:=en"

      releases = Enum.find(searches, &(&1["collection"] == "github-releases"))
      assert releases["group_by"] == "release_group"
      assert releases["filter_by"] == "prerelease:=false"
      assert releases["sort_by"] == "_text_match:desc,published_at:desc"

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
            "grouped_hits" => [
              %{
                "hits" => [
                  %{
                    "title" => "CLI 4.202.2",
                    "content" => "Bug fixes: reassemble the requested result bundle across test schemes.",
                    "url" => "https://github.com/tuist/tuist/releases/tag/4.202.2",
                    "product" => "CLI",
                    "version" => "4.202.2",
                    "published_at_iso" => "2026-07-13T16:02:02Z",
                    "prerelease" => false
                  }
                  |> hit(95)
                  |> Map.put("highlights", [
                    %{"field" => "content", "snippet" => "reassemble the requested <mark>result bundle</mark>"}
                  ])
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

    # Ranked by text_match across collections: forum (99) > releases (95) > docs (90) > api (50).
    assert Enum.map(results, & &1["source"]) == ["forum", "releases", "docs", "api_reference"]
    assert Enum.map(results, & &1["title"]) == ["Caching help", "CLI 4.202.2", "Selective testing", "Target"]
    assert hd(results)["url"] == "https://community.tuist.dev/t/caching/1"

    release = Enum.find(results, &(&1["source"] == "releases"))
    assert release["snippet"] == "reassemble the requested result bundle"
    assert release["product"] == "CLI"
    assert release["version"] == "4.202.2"
    assert release["published_at"] == "2026-07-13T16:02:02Z"
    assert release["prerelease"] == false
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

  test "fetches up to max_results per collection so a single source can reach the cap" do
    expect(Req, :post, fn _url, opts ->
      [search] = opts[:json]["searches"]
      assert search["collection"] == "github-issues"
      assert search["per_page"] == 20
      {:ok, %Req.Response{status: 200, body: %{"results" => [%{"hits" => []}]}}}
    end)

    assert {:ok, _} = Search.search(%{"query" => "cache", "source" => "issues", "max_results" => 20})
  end

  test "prereleases can be included for release-only searches" do
    expect(Req, :post, fn _url, opts ->
      [search] = opts[:json]["searches"]
      assert search["collection"] == "github-releases"
      refute Map.has_key?(search, "filter_by")
      {:ok, %Req.Response{status: 200, body: %{"results" => [%{"grouped_hits" => []}]}}}
    end)

    assert {:ok, _} =
             Search.search(%{
               "query" => "4.203.0-canary.24",
               "source" => "releases",
               "include_prereleases" => true
             })
  end

  test "an all-source search returns at most two releases" do
    expect(Req, :post, fn _url, _opts ->
      release_groups =
        for version <- ["4.202.2", "4.202.1", "4.202.0"] do
          %{
            "hits" => [
              hit(
                %{
                  "title" => "CLI #{version}",
                  "content" => "Release notes",
                  "url" => "https://github.com/tuist/tuist/releases/tag/#{version}"
                },
                100
              )
            ]
          }
        end

      body = %{
        "results" => [
          %{"grouped_hits" => []},
          %{"grouped_hits" => release_groups},
          %{"hits" => []},
          %{"hits" => []},
          %{"grouped_hits" => []}
        ]
      }

      {:ok, %Req.Response{status: 200, body: body}}
    end)

    assert {:ok, %{"results" => results}} = Search.search(%{"query" => "release notes"})
    assert length(results) == 2
    assert Enum.all?(results, &(&1["source"] == "releases"))
  end

  test "maps a non-200 response to an error" do
    stub(Req, :post, fn _url, _opts -> {:ok, %Req.Response{status: 503, body: ""}} end)

    assert {:error, "Tuist search returned status 503."} = Search.search(%{"query" => "cache"})
  end
end
