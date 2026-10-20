defmodule Atlas.MCP.Tools.DeletePostmortemActionItem do
  @moduledoc "Deletes a postmortem action item."

  use Atlas.MCP.Tool,
    name: "delete_postmortem_action_item",
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
      "properties" => %{"deleted_action_item" => Atlas.MCP.Tools.PostmortemSerializers.action_item_schema()},
      "required" => ["deleted_action_item"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Postmortems
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.PostmortemSerializers

  @impl EMCP.Tool
  def description, do: "Delete a postmortem action item. Authenticated operators only."

  def execute(conn, %{"action_item_id" => action_item_id}) do
    user = Tool.current_user(conn)

    if Postmortems.can_publish?(user) do
      delete(user, action_item_id)
    else
      {:error, "Only authenticated operators can delete action items."}
    end
  end

  defp delete(user, action_item_id) do
    case Postmortems.fetch_visible_action_item(action_item_id, user) do
      {:ok, postmortem, action_item} ->
        deleted = PostmortemSerializers.action_item(action_item)

        case Postmortems.delete_action_item(postmortem, action_item, user) do
          {:ok, _action_item} ->
            {:ok, %{"deleted_action_item" => deleted}}

          {:error, :unauthorized} ->
            {:error, "Only authenticated operators can delete action items."}
        end

      {:error, :not_found} ->
        {:error, "Action item not found."}
    end
  end
end
