defmodule Atlas.MCP.Tools.UnpublishPOC do
  @moduledoc "Revokes the public link for a POC."

  use Atlas.MCP.Tool,
    name: "unpublish_poc",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{"id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"poc" => Atlas.MCP.Tools.POCSerializers.poc_schema()},
      "required" => ["poc"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts.POCs
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.POCSerializers

  @impl EMCP.Tool
  def description, do: "Revoke the public link for a POC. Authenticated operators only."

  def execute(conn, %{"id" => id}) do
    user = Tool.current_user(conn)

    case POCs.get_poc(id) do
      nil ->
        {:error, "POC not found."}

      poc ->
        case POCs.unpublish_poc(poc, user) do
          {:ok, poc} -> {:ok, %{"poc" => POCSerializers.poc(POCs.get_poc!(poc.id))}}
          {:error, :unauthorized} -> {:error, "Only authenticated operators can unpublish POCs."}
          {:error, changeset} -> {:error, "Could not unpublish POC: #{Tool.format_changeset_errors(changeset)}"}
        end
    end
  end
end
