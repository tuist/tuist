defmodule Atlas.MCP.Tools.SearchApolloOutreach do
  @moduledoc """
  Searches Apollo for outreach candidates and persists the results in Atlas.
  """

  use Atlas.MCP.Tool,
    name: "search_apollo_outreach",
    schema: %{
      "type" => "object",
      "properties" => %{
        "segments" => %{
          "type" => "array",
          "items" => %{"type" => "string", "enum" => ["mobile_mid_large", "mobile_giants"]},
          "minItems" => 1,
          "uniqueItems" => true
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "required" => ["created", "updated", "excluded", "returned", "total_matches", "segments"],
      "properties" => %{
        "created" => %{"type" => "integer"},
        "updated" => %{"type" => "integer"},
        "excluded" => %{"type" => "integer"},
        "returned" => %{"type" => "integer"},
        "total_matches" => %{"type" => "integer"},
        "segments" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["id", "name", "returned", "total_matches", "excluded"],
            "properties" => %{
              "id" => %{"type" => "string"},
              "name" => %{"type" => "string"},
              "returned" => %{"type" => "integer"},
              "total_matches" => %{"type" => "integer"},
              "excluded" => %{"type" => "integer"}
            },
            "additionalProperties" => false
          }
        }
      },
      "additionalProperties" => false
    }

  alias Atlas.MCP.Tool
  alias Atlas.Outreach

  @impl EMCP.Tool
  def description,
    do: "Run Atlas's versioned mobile-leader searches in Apollo and save the resulting candidates in Atlas for review."

  def execute(conn, args) do
    opts = if is_list(args["segments"]), do: [segments: args["segments"]], else: []

    case Outreach.search_apollo(Tool.current_user(conn), opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, {_segment_id, :apollo_api_key_not_configured}} ->
        {:error, "Apollo is not configured for this environment."}

      {:error, {segment_id, reason}} ->
        {:error, "Apollo search #{segment_id} failed: #{inspect(reason)}"}
    end
  end
end
