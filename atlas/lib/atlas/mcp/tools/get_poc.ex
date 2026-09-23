defmodule Atlas.MCP.Tools.GetPOC do
  @moduledoc "Fetches a POC by id."

  use Atlas.MCP.Tool,
    name: "get_poc",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string", "description" => "POC identifier."}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"poc" => Atlas.MCP.Tools.POCSerializers.poc_schema()},
      "required" => ["poc"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts.POCs
  alias Atlas.MCP.Tools.POCSerializers

  @impl EMCP.Tool
  def description, do: "Fetch a POC with its context, scope, and timeline."

  def execute(_conn, %{"id" => id}) do
    case POCs.get_poc(id) do
      nil -> {:error, "POC not found."}
      poc -> {:ok, %{"poc" => POCSerializers.poc(poc)}}
    end
  end
end
