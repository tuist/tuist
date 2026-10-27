defmodule Atlas.MCP.Tools.AddMoodboardComment do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "add_moodboard_comment",
    schema: %{
      "type" => "object",
      "required" => ["resource_id", "body"],
      "properties" => %{
        "resource_id" => %{"type" => "string"},
        "body" => %{"type" => "string", "minLength" => 1, "maxLength" => 4000}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"comment" => Atlas.MCP.Serializers.Moodboard.comment_schema()},
      "required" => ["comment"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Serializers.Moodboard, as: Serializer
  alias Atlas.MCP.Tool
  alias Atlas.Moodboard

  @impl EMCP.Tool
  def description, do: "Add your comment to a Moodboard resource's shared team discussion."

  def execute(conn, args) do
    with :ok <- Tool.authorize_authenticated(conn, "Moodboard tools"),
         {:ok, comment} <-
           Moodboard.add_comment(args["resource_id"], Map.take(args, ["body"]), Tool.current_user(conn),
             interface: Tool.audit_interface(conn)
           ) do
      {:ok, %{comment: Serializer.comment(comment)}}
    else
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, Serializer.error(reason)}
    end
  end
end
