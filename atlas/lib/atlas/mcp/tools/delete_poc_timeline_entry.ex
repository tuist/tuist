defmodule Atlas.MCP.Tools.DeletePOCTimelineEntry do
  @moduledoc "Deletes a POC timeline entry."

  use Atlas.MCP.Tool,
    name: "delete_poc_timeline_entry",
    schema: %{
      "type" => "object",
      "required" => ["entry_id"],
      "properties" => %{"entry_id" => %{"type" => "string"}},
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
  def description, do: "Delete a POC timeline entry. Authenticated operators only."

  def execute(conn, %{"entry_id" => entry_id}) do
    user = Tool.current_user(conn)

    with %{} = entry <- POCs.get_timeline_entry(entry_id),
         %{} = poc <- POCs.get_poc(entry.poc_id) do
      case POCs.delete_timeline_entry(poc, entry, user) do
        {:ok, _deleted} -> {:ok, %{"deleted" => true, "id" => entry_id}}
        {:error, :unauthorized} -> {:error, "Only authenticated operators can delete entries."}
        {:error, changeset} -> {:error, "Could not delete entry: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      _ -> {:error, "Timeline entry not found."}
    end
  end
end
