defmodule Atlas.MCP.Tools.DeletePOC do
  @moduledoc "Deletes a POC and everything attached to it."

  use Atlas.MCP.Tool,
    name: "delete_poc",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{"id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"deleted" => %{"type" => "boolean"}, "id" => %{"type" => "string"}},
      "required" => ["deleted", "id"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts.POCs
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Delete a POC. Authenticated operators only."

  def execute(conn, %{"id" => id}) do
    user = Tool.current_user(conn)

    case POCs.get_poc(id) do
      nil ->
        {:error, "POC not found."}

      poc ->
        case POCs.delete_poc(poc, user) do
          {:ok, _deleted} -> {:ok, %{"deleted" => true, "id" => id}}
          {:error, :unauthorized} -> {:error, "Only authenticated operators can delete POCs."}
          {:error, changeset} -> {:error, "Could not delete POC: #{Tool.format_changeset_errors(changeset)}"}
        end
    end
  end
end
