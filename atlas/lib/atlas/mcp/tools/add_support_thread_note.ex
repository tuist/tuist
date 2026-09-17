defmodule Atlas.MCP.Tools.AddSupportThreadNote do
  use Atlas.MCP.Tool,
    name: "add_support_thread_note",
    schema: %{
      "type" => "object",
      "required" => ["thread_id", "body"],
      "properties" => %{
        "thread_id" => %{"type" => "string"},
        "body" => %{"type" => "string", "description" => "Private note visible only to the Tuist team."}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "message" => Atlas.MCP.Serializers.Support.message_schema()
      },
      "required" => ["message"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Serializers.Support, as: SupportSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Support

  @impl EMCP.Tool
  def description, do: "Add a private team note to a customer support conversation."

  def execute(conn, %{"thread_id" => id, "body" => body}) do
    with :ok <- Tool.authorize_executive(conn, "Support tools") do
      case Support.add_note(id, %{"body" => body}, Tool.current_user(conn)) do
        {:ok, message} ->
          {:ok, %{message: SupportSerializer.message(message)}}

        {:error, :not_found} ->
          {:error, "Support conversation not found: #{id}"}

        {:error, :body_required} ->
          {:error, "body is required."}

        {:error, reason} ->
          {:error, "Could not add private support note: #{inspect(reason)}"}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "thread_id and body are required."}
end
