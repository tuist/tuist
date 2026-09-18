defmodule Atlas.MCP.Tools.CreatePostmortemActionItem do
  @moduledoc "Creates an action item on a postmortem."

  alias Atlas.Engineering.Postmortems.ActionItem
  alias Atlas.MCP.Tools.PostmortemSerializers

  use Atlas.MCP.Tool,
    name: "create_postmortem_action_item",
    schema: %{
      "type" => "object",
      "required" => ["postmortem_id", "title"],
      "properties" => %{
        "postmortem_id" => %{
          "type" => "string",
          "description" => "Postmortem identifier, public number, or shared postmortem address."
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
          "description" => "Urgency of the follow-up work. Defaults to medium."
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
  def description, do: "Create an action item for a postmortem. Authenticated operators only."

  def execute(conn, %{"postmortem_id" => postmortem_id} = args) do
    user = Tool.current_user(conn)

    case Postmortems.fetch_visible_postmortem_by_reference(postmortem_id, user) do
      {:ok, postmortem} -> create(postmortem, user, args)
      {:error, :not_found} -> {:error, "Postmortem not found."}
    end
  end

  defp create(postmortem, user, args) do
    attrs = Map.take(args, ["title", "description", "resolution_url", "priority"])

    case Postmortems.create_action_item(postmortem, attrs, user) do
      {:ok, action_item} ->
        {:ok, %{"action_item" => PostmortemSerializers.action_item(action_item)}}

      {:error, :unauthorized} ->
        {:error, "Only authenticated operators can create action items."}

      {:error, changeset} ->
        {:error, "Could not create action item: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
