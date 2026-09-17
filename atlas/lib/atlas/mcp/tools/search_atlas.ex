defmodule Atlas.MCP.Tools.SearchAtlas do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "search_atlas",
    schema: %{
      "type" => "object",
      "required" => ["query"],
      "properties" => %{
        "query" => %{
          "type" => "string",
          "minLength" => 1,
          "description" => "Natural-language search query across indexed Atlas account and go-to-market records."
        },
        "source_types" => %{
          "type" => "array",
          "items" => %{"type" => "string", "enum" => Atlas.Search.Federated.source_types()},
          "description" => "Optional. Restrict search to specific indexed resource types."
        },
        "domains" => %{
          "type" => "array",
          "items" => %{"type" => "string", "enum" => Atlas.Search.Federated.domains()},
          "description" => "Optional. Restrict search to Atlas domains available to this session."
        },
        "account_id" => %{
          "type" => "string",
          "description" => "Optional. Restrict results to one Atlas account."
        },
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema: %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["results", "count", "domains", "available_domains"],
      "properties" => %{
        # Result entries are heterogeneous: Atlas record hits and document-page hits carry
        # different key sets (document hits add document_id/page_number). Keep the item schema
        # permissive rather than encode a shape that varies per result kind.
        "results" => %{
          "type" => "array",
          "items" => %{"type" => "object", "additionalProperties" => true}
        },
        "count" => %{"type" => "integer"},
        "domains" => %{"type" => "array", "items" => %{"type" => "string"}},
        "available_domains" => %{"type" => "array", "items" => %{"type" => "string"}}
      }
    }

  alias Atlas.MCP.Tool
  alias Atlas.Search.Federated, as: FederatedSearch

  @impl EMCP.Tool
  def description do
    "Search Atlas semantically across available domains, including account events, customer outcomes, overview summaries, go-to-market opportunities, go-to-market signals, blog post ideas, social-channel ideas, and executive documents when this session has document access."
  end

  def execute(conn, %{"query" => query} = args) when is_binary(query) do
    opts =
      [limit: Tool.page_size(args), allowed_domains: allowed_search_domains(conn)]
      |> maybe_put(:domains, Map.get(args, "domains"))
      |> maybe_put(:source_types, Map.get(args, "source_types"))
      |> maybe_put(:account_id, Map.get(args, "account_id"))

    with :ok <- authorize_requested_document_search(conn, args) do
      FederatedSearch.search(query, opts)
    end
  end

  def execute(_conn, _args), do: {:error, "query is required."}

  defp allowed_search_domains(conn) do
    case document_search_authorization(conn) do
      :ok -> FederatedSearch.domains()
      {:error, _reason} -> [FederatedSearch.atlas_domain()]
    end
  end

  defp authorize_requested_document_search(conn, args) do
    if document_search_requested?(args) do
      document_search_authorization(conn)
    else
      :ok
    end
  end

  defp document_search_authorization(conn) do
    with :ok <- authorize_document_group(conn) do
      Tool.authorize_executive(conn, "Document tools")
    end
  end

  defp authorize_document_group(%{assigns: %{mcp_claims: %{"mcp_tool_groups" => groups}}}) when is_list(groups) do
    groups = Enum.map(groups, &to_string/1)

    if FederatedSearch.documents_domain() in groups do
      :ok
    else
      {:error, "Document search is not available for this Model Context Protocol session."}
    end
  end

  defp authorize_document_group(_conn), do: :ok

  defp document_search_requested?(args) do
    domain_requested?(Map.get(args, "domains"), FederatedSearch.documents_domain()) or
      source_type_requested?(Map.get(args, "source_types"), FederatedSearch.document_source_type())
  end

  defp domain_requested?(values, value), do: normalized_values(values) |> Enum.member?(value)
  defp source_type_requested?(values, value), do: normalized_values(values) |> Enum.member?(value)

  defp normalized_values(values) when is_list(values) do
    values
    |> Enum.map(&normalize_value/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalized_values(value) when is_binary(value), do: [normalize_value(value)]
  defp normalized_values(_value), do: []

  defp normalize_value(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp normalize_value(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_value()
  defp normalize_value(_value), do: nil

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, _key, []), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
