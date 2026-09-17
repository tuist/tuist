defmodule Atlas.MCP.Tools.GetSupportThread do
  use Atlas.MCP.Tool,
    name: "get_support_thread",
    schema: %{
      "type" => "object",
      "required" => ["thread_id"],
      "properties" => %{"thread_id" => %{"type" => "string"}}
    },
    output_schema: Atlas.MCP.Serializers.Support.thread_schema()

  alias Atlas.MCP.Serializers.Support, as: SupportSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Support

  @impl EMCP.Tool
  def description, do: "Get a support conversation with every customer email, team reply, and private note."

  def execute(conn, %{"thread_id" => id}) do
    with :ok <- Tool.authorize_executive(conn, "Support tools") do
      case Support.get_thread(id) do
        nil -> {:error, "Support conversation not found: #{id}"}
        thread -> {:ok, SupportSerializer.thread(thread, include_messages: true)}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "thread_id is required."}
end
