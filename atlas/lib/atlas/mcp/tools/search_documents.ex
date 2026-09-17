defmodule Atlas.MCP.Tools.SearchDocuments do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "search_documents",
    schema: %{
      "type" => "object",
      "required" => ["query"],
      "properties" => %{
        "query" => %{"type" => "string", "description" => "Natural-language semantic search query."},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema:
      Atlas.MCP.Serializers.Accounts.list_response_schema(:results, %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "string"},
          "document_id" => %{"type" => ["string", "null"]},
          "page_number" => %{"type" => ["integer", "null"]},
          "excerpt" => %{"type" => "string"},
          "title" => %{"type" => ["string", "null"]},
          "document_type" => %{"type" => ["string", "null"]},
          "correspondent" => %{"type" => ["string", "null"]},
          "account_id" => %{"type" => ["string", "null"]},
          "account_name" => %{"type" => ["string", "null"]},
          "summary" => %{"type" => ["string", "null"]},
          "score" => %{"type" => "number"},
          "match_sources" => %{"type" => "array", "items" => %{"type" => "string"}}
        },
        "required" => [
          "id",
          "document_id",
          "page_number",
          "excerpt",
          "title",
          "document_type",
          "correspondent",
          "account_id",
          "account_name",
          "summary",
          "score",
          "match_sources"
        ],
        "additionalProperties" => false
      })

  alias Atlas.Documents
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Semantically search executive documents by page."

  def execute(conn, %{"query" => query} = args) when is_binary(query) do
    with :ok <- Tool.authorize_executive(conn, "Document tools"),
         {:ok, results} <- Documents.semantic_search(query, limit: Tool.page_size(args)) do
      {:ok, %{results: results, count: length(results)}}
    end
  end

  def execute(_conn, _args), do: {:error, "query is required."}
end
