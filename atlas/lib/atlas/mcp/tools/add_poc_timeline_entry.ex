defmodule Atlas.MCP.Tools.AddPOCTimelineEntry do
  @moduledoc "Adds a timeline entry (event, decision, or milestone) to a POC."

  use Atlas.MCP.Tool,
    name: "add_poc_timeline_entry",
    schema: %{
      "type" => "object",
      "required" => ["poc_id", "title", "occurred_on"],
      "properties" => %{
        "poc_id" => %{"type" => "string"},
        "occurred_on" => %{"type" => "string", "description" => "ISO 8601 date."},
        "title" => %{"type" => "string"},
        "body" => %{"type" => "string"},
        "kind" => %{
          "type" => "string",
          "enum" => Atlas.Accounts.POCs.TimelineEntry.kinds(),
          "description" => "Defaults to event."
        },
        "author_label" => %{
          "type" => "string",
          "description" => "Overrides the caller's name in the audit trail."
        }
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
  def description, do: "Add a timeline entry to a POC. Authenticated operators only."

  def execute(conn, %{"poc_id" => poc_id} = args) do
    user = Tool.current_user(conn)

    case POCs.get_poc(poc_id) do
      nil ->
        {:error, "POC not found."}

      poc ->
        attrs =
          args
          |> Map.take(["occurred_on", "title", "body", "kind", "author_label"])
          |> Map.put_new("kind", "event")

        case POCs.add_timeline_entry(poc, attrs, user) do
          {:ok, entry} ->
            {:ok, %{"entry" => POCSerializers.timeline_entry(entry)}}

          {:error, :unauthorized} ->
            {:error, "Only authenticated operators can add timeline entries."}

          {:error, changeset} ->
            {:error, "Could not add entry: #{Tool.format_changeset_errors(changeset)}"}
        end
    end
  end
end
