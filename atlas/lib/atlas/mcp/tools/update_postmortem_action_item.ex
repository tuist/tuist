defmodule Atlas.MCP.Tools.UpdatePostmortemActionItem do
  @moduledoc "Updates a postmortem action item's text or completion state."

  alias Atlas.Engineering.Postmortems.ActionItem
  alias Atlas.MCP.Tools.PostmortemSerializers

  use Atlas.MCP.Tool,
    name: "update_postmortem_action_item",
    schema: %{
      "type" => "object",
      "required" => ["action_item_id"],
      "properties" => %{
        "action_item_id" => %{
          "type" => "string",
          "description" => "Action-item identifier returned with a postmortem."
        },
        "title" => %{"type" => "string"},
        "description" => %{"type" => ["string", "null"]},
        "resolution_url" => %{
          "type" => ["string", "null"],
          "description" => "HTTP or HTTPS link to the work that resolved this action item."
        },
        "priority" => %{
          "type" => "string",
          "enum" => Enum.map(ActionItem.priorities(), &Atom.to_string/1),
          "description" => "Urgency of the follow-up work."
        },
        "completed" => %{
          "type" => "boolean",
          "description" => "Whether the follow-up work is complete."
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
  def description do
    "Update an action item's text or completion state. Authenticated operators only."
  end

  def execute(conn, %{"action_item_id" => action_item_id} = args) do
    user = Tool.current_user(conn)

    case Postmortems.fetch_visible_action_item(action_item_id, user) do
      {:ok, postmortem, action_item} -> update(postmortem, action_item, user, args)
      {:error, :not_found} -> {:error, "Action item not found."}
    end
  end

  defp update(postmortem, action_item, user, args) do
    if Postmortems.can_edit?(postmortem, user) do
      with {:ok, action_item} <- update_text(postmortem, action_item, user, args),
           {:ok, action_item} <- update_completion(postmortem, action_item, user, args) do
        {:ok, %{"action_item" => PostmortemSerializers.action_item(action_item)}}
      else
        {:error, changeset} ->
          {:error, "Could not update action item: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      {:error, "Only authenticated operators can update action items."}
    end
  end

  defp update_text(postmortem, action_item, user, args) do
    case Map.take(args, ["title", "description", "resolution_url", "priority"]) do
      attrs when attrs == %{} -> {:ok, action_item}
      attrs -> Postmortems.update_action_item(postmortem, action_item, attrs, user)
    end
  end

  defp update_completion(postmortem, action_item, user, args) do
    case Map.fetch(args, "completed") do
      {:ok, completed} ->
        Postmortems.set_action_item_completed(postmortem, action_item, completed, user)

      :error ->
        {:ok, action_item}
    end
  end
end
