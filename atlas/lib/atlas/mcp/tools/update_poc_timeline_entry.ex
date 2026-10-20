defmodule Atlas.MCP.Tools.UpdatePOCTimelineEntry do
  @moduledoc "Updates a POC timeline entry."

  use Atlas.MCP.Tool,
    name: "update_poc_timeline_entry",
    schema: %{
      "type" => "object",
      "required" => ["entry_id"],
      "properties" => %{
        "entry_id" => %{"type" => "string"},
        "occurred_on" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "body" => %{"type" => "string"},
        "kind" => %{"type" => "string", "enum" => Atlas.Accounts.POCs.TimelineEntry.kinds()},
        "author_label" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"entry" => Atlas.MCP.Tools.POCSerializers.timeline_entry_schema()},
      "required" => ["entry"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts.POCs
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.POCSerializers

  @impl EMCP.Tool
  def description, do: "Update a POC timeline entry. Authenticated operators only."

  def execute(conn, %{"entry_id" => entry_id} = args) do
    user = Tool.current_user(conn)

    with %{} = entry <- POCs.get_timeline_entry(entry_id),
         %{} = poc <- POCs.get_poc(entry.poc_id) do
      attrs = Map.take(args, ["occurred_on", "title", "body", "kind", "author_label"])

      case POCs.update_timeline_entry(poc, entry, attrs, user) do
        {:ok, updated} -> {:ok, %{"entry" => POCSerializers.timeline_entry(updated)}}
        {:error, :unauthorized} -> {:error, "Only authenticated operators can update entries."}
        {:error, changeset} -> {:error, "Could not update entry: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      _ -> {:error, "Timeline entry not found."}
    end
  end
end
