defmodule Atlas.MCP.Tools.ListPostmortemActionItems do
  @moduledoc "Lists the action items on a postmortem."

  use Atlas.MCP.Tool,
    name: "list_postmortem_action_items",
    schema: %{
      "type" => "object",
      "required" => ["postmortem_id"],
      "properties" => %{
        "postmortem_id" => %{
          "type" => "string",
          "description" => "Postmortem identifier, public number, or shared postmortem address."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "action_items" => %{
          "type" => "array",
          "items" => Atlas.MCP.Tools.PostmortemSerializers.action_item_schema()
        }
      },
      "required" => ["action_items"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Postmortems
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.PostmortemSerializers

  @impl EMCP.Tool
  def description, do: "List the action items belonging to one visible postmortem."

  def execute(conn, %{"postmortem_id" => postmortem_id}) do
    case Postmortems.fetch_visible_postmortem_by_reference(
           postmortem_id,
           Tool.current_user(conn)
         ) do
      {:ok, postmortem} ->
        {:ok, %{"action_items" => PostmortemSerializers.action_items(postmortem)}}

      {:error, :not_found} ->
        {:error, "Postmortem not found."}
    end
  end
end
