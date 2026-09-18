defmodule Atlas.MCP.Tools.GetPostmortemActionItem do
  @moduledoc "Fetches a single postmortem action item."

  alias Atlas.MCP.Tools.PostmortemSerializers

  use Atlas.MCP.Tool,
    name: "get_postmortem_action_item",
    schema: %{
      "type" => "object",
      "required" => ["action_item_id"],
      "properties" => %{
        "action_item_id" => %{
          "type" => "string",
          "description" => "Action-item identifier returned with a postmortem."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"action_item" => PostmortemSerializers.action_item_schema()},
      "required" => ["action_item"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Postmortems
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Fetch one action item when its postmortem is visible to the caller."

  def execute(conn, %{"action_item_id" => action_item_id}) do
    case Postmortems.fetch_visible_action_item(action_item_id, Tool.current_user(conn)) do
      {:ok, _postmortem, action_item} ->
        {:ok, %{"action_item" => PostmortemSerializers.action_item(action_item)}}

      {:error, :not_found} ->
        {:error, "Action item not found."}
    end
  end
end
