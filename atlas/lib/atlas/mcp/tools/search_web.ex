defmodule Atlas.MCP.Tools.SearchWeb do
  @moduledoc """
  Search the public web via the Brave Search API.

  Use this when a question can be answered by current web results: news,
  documentation, product pages, recent announcements, technical references.
  Returns ranked results with title, URL, and a short snippet. Combine with
  `fetch_url_content` (Slack-only) or `Atlas.MCP.Tools.GetDocument` to read
  a specific result in full.
  """

  use Atlas.MCP.Tool,
    name: "search_web",
    schema: %{
      "type" => "object",
      "required" => ["query"],
      "properties" => %{
        "query" => %{
          "type" => "string",
          "minLength" => 1,
          "description" => "Search query, e.g. \"Phoenix LiveView 1.0 release notes\"."
        },
        "count" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 10,
          "description" => "Optional. Number of results to return. Defaults to 5."
        },
        "freshness" => %{
          "type" => "string",
          "enum" => ["pd", "pw", "pm", "py"],
          "description" => "Optional. Restrict to results from the past day (pd), week (pw), month (pm), or year (py)."
        },
        "country" => %{
          "type" => "string",
          "minLength" => 2,
          "maxLength" => 2,
          "description" => ~s(Optional. Two-letter country code, e.g. "us" or "de". Defaults to "us".)
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["query", "count", "results"],
      "properties" => %{
        "query" => %{"type" => "string"},
        "count" => %{"type" => "integer"},
        "results" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["title", "url", "snippet", "age"],
            "properties" => %{
              "title" => %{"type" => "string"},
              "url" => %{"type" => "string"},
              "snippet" => %{"type" => ["string", "null"]},
              "age" => %{"type" => ["string", "null"]}
            }
          }
        }
      }
    }

  @endpoint "https://api.search.brave.com/res/v1/web/search"
  @default_count 5
  @max_count 10
  @request_timeout 10_000

  @impl EMCP.Tool
  def description, do: @moduledoc

  def execute(_conn, %{"query" => query} = args) when is_binary(query) do
    with {:ok, query} <- parse_query(query),
         {:ok, api_key} <- __MODULE__.api_key() do
      count = clamp(Map.get(args, "count", @default_count), @max_count)

      params =
        [q: query, count: count, country: country(args)]
        |> maybe_put(:freshness, Map.get(args, "freshness"))

      case Req.get(
             url: @endpoint,
             headers: [{"X-Subscription-Token", api_key}, {"Accept", "application/json"}],
             params: params,
             receive_timeout: @request_timeout
           ) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, %{query: query, count: count, results: parse_results(body)}}

        {:ok, %{status: status, body: body}} ->
          {:error, "Brave Search returned HTTP #{status}: #{inspect(body)}"}

        {:error, reason} ->
          {:error, "Brave Search request failed: #{inspect(reason)}"}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "query is required."}

  defp parse_query(value) do
    case String.trim(value) do
      "" -> {:error, "query is required."}
      trimmed -> {:ok, trimmed}
    end
  end

  @doc false
  def api_key do
    case Application.get_env(:atlas, :brave_search, [])[:api_key] do
      key when is_binary(key) and key != "" -> {:ok, key}
      _missing -> {:error, "Brave Search is not configured."}
    end
  end

  defp parse_results(body) do
    body
    |> get_in(["web", "results"])
    |> List.wrap()
    |> Enum.map(&parse_result/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_result(%{"url" => url} = result) when is_binary(url) do
    %{
      title: result["title"] || url,
      url: url,
      snippet: result["description"],
      age: result["age"]
    }
  end

  defp parse_result(_result), do: nil

  defp country(args) do
    case Map.get(args, "country") do
      code when is_binary(code) and byte_size(code) == 2 -> String.downcase(code)
      _other -> "us"
    end
  end

  defp clamp(value, ceiling) when is_integer(value), do: value |> Kernel.max(1) |> Kernel.min(ceiling)
  defp clamp(_value, _ceiling), do: @default_count

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, _key, ""), do: params
  defp maybe_put(params, key, value), do: Keyword.put(params, key, value)
end
