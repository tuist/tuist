defmodule Atlas.MCP.Tools.DeleteMoodboardComment do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "delete_moodboard_comment",
    schema: %{
      "type" => "object",
      "required" => ["comment_id"],
      "properties" => %{"comment_id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"deleted" => %{"type" => "boolean"}},
      "required" => ["deleted"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Serializers.Moodboard, as: Serializer
  alias Atlas.MCP.Tool
  alias Atlas.Moodboard

  @impl EMCP.Tool
  def description, do: "Remove your own comment from a Moodboard discussion."

  def execute(conn, args) do
    with :ok <- Tool.authorize_authenticated(conn, "Moodboard tools"),
         {:ok, _comment} <-
           Moodboard.delete_comment(args["comment_id"], Tool.current_user(conn), interface: Tool.audit_interface(conn)) do
      {:ok, %{deleted: true}}
    else
      {:error, :forbidden} -> {:error, "Only the author can remove this comment."}
      {:error, :not_found} -> {:error, "Comment not found."}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, Serializer.error(reason)}
    end
  end
end
