defmodule Tuist.MCP.Search do
  @moduledoc """
  Searches Tuist's documentation, API reference, community forum, and GitHub
  issues through the Typesense search engine that also powers the docs website.

  The collection set and per-collection query weights mirror
  `server/assets/docs/hooks/docs-search-hook.js` so the MCP tool and the website
  surface the same relevance.
  """

  alias Tuist.Environment

  @receive_timeout 6_000
  @max_snippet_characters 320
  @default_max_results 8
  @max_results 20

  @collections [
    %{
      name: "tuist",
      source: "docs",
      query_by:
        "hierarchy.lvl0,hierarchy.lvl1,hierarchy.lvl2,hierarchy.lvl3,hierarchy.lvl4,hierarchy.lvl5,hierarchy.lvl6,content",
      query_by_weights: "127,100,80,60,40,20,10,5",
      group_by: "url_without_anchor",
      filter_by: "tags:=en"
    },
    %{
      name: "projectdescription",
      source: "api_reference",
      query_by: "title,hierarchy.lvl0,hierarchy.lvl1,hierarchy.lvl2,content",
      query_by_weights: "127,100,80,60,5",
      group_by: nil,
      filter_by: nil
    },
    %{
      name: "github-issues",
      source: "issues",
      query_by: "title,hierarchy.lvl0,hierarchy.lvl1,content",
      query_by_weights: "127,100,80,5",
      group_by: nil,
      filter_by: nil
    },
    %{
      name: "forum-topics",
      source: "forum",
      query_by:
        "hierarchy.lvl0,hierarchy.lvl1,hierarchy.lvl2,hierarchy.lvl3,hierarchy.lvl4,hierarchy.lvl5,hierarchy.lvl6,content",
      query_by_weights: "127,100,80,60,40,20,10,5",
      group_by: "url_without_anchor",
      filter_by: nil
    }
  ]

  @sources Enum.map(@collections, & &1.source)

  def sources, do: @sources

  def search(arguments) do
    query = arguments |> Map.get("query", "") |> to_string() |> String.trim()
    max_results = clamp_max_results(arguments["max_results"])
    collections = collections_for(arguments["source"])

    body = %{"searches" => Enum.map(collections, &search_clause(&1, query, max_results))}

    case Req.post(Environment.typesense_host() <> "/multi_search",
           json: body,
           headers: [{"x-typesense-api-key", Environment.typesense_search_api_key()}],
           receive_timeout: @receive_timeout,
           connect_options: [timeout: 2_000]
         ) do
      {:ok, %Req.Response{status: 200, body: %{"results" => results}}} ->
        {:ok,
         %{
           "query" => query,
           "results" => normalize(results, collections, max_results)
         }}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Tuist search returned status #{status}."}

      {:error, error} ->
        {:error, "Tuist search is unavailable: #{Exception.message(error)}"}
    end
  end

  defp collections_for(source) when source in @sources, do: Enum.filter(@collections, &(&1.source == source))

  defp collections_for(_), do: @collections

  defp clamp_max_results(value) when is_integer(value) and value > 0, do: min(value, @max_results)
  defp clamp_max_results(_), do: @default_max_results

  defp search_clause(collection, query, max_results) do
    %{
      "collection" => collection.name,
      "q" => query,
      "query_by" => collection.query_by,
      "query_by_weights" => collection.query_by_weights,
      # Fetch up to max_results per collection (already clamped to the advertised
      # cap) so a single-source search can reach that cap, and multi-source
      # searches have a wider candidate pool to rank across.
      "per_page" => max_results
    }
    |> maybe_put("group_by", collection.group_by)
    |> maybe_group_limit(collection.group_by)
    |> maybe_put("filter_by", collection.filter_by)
  end

  defp maybe_group_limit(clause, nil), do: clause
  defp maybe_group_limit(clause, _group_by), do: Map.put(clause, "group_limit", 1)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Typesense returns one result object per search clause, in request order.
  defp normalize(results, collections, max_results) do
    collections
    |> Enum.zip(List.wrap(results))
    |> Enum.flat_map(fn {collection, result} ->
      result |> hits() |> Enum.map(&to_result(&1, collection))
    end)
    |> Enum.sort_by(& &1["text_match"], :desc)
    |> Enum.take(max_results)
    |> Enum.map(&Map.delete(&1, "text_match"))
  end

  defp hits(%{"grouped_hits" => grouped}) when is_list(grouped),
    do: Enum.flat_map(grouped, fn group -> group |> Map.get("hits", []) |> Enum.take(1) end)

  defp hits(%{"hits" => hits}) when is_list(hits), do: hits
  defp hits(_), do: []

  defp to_result(hit, collection) do
    document = Map.get(hit, "document", %{})

    %{
      "source" => collection.source,
      "title" => title_for(document, collection),
      "url" => document["url"] || document["url_without_anchor"] || "",
      "snippet" => snippet_for(document),
      # Kept only for ranking across collections; dropped before returning.
      "text_match" => Map.get(hit, "text_match", 0)
    }
  end

  defp title_for(document, %{name: name}) when name in ["tuist", "forum-topics"],
    do: deepest_hierarchy(document) || "Untitled"

  defp title_for(document, _collection), do: present(document["title"]) || deepest_hierarchy(document) || "Untitled"

  defp deepest_hierarchy(document) do
    hierarchy = Map.get(document, "hierarchy", %{})
    Enum.find_value(6..0//-1, fn level -> present(hierarchy["lvl#{level}"]) end)
  end

  defp snippet_for(document) do
    document
    |> Map.get("content", "")
    |> to_string()
    |> String.slice(0, @max_snippet_characters)
    |> String.trim()
  end

  defp present(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp present(_), do: nil
end
