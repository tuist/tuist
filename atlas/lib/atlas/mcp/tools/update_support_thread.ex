defmodule Atlas.MCP.Tools.UpdateSupportThread do
  use Atlas.MCP.Tool,
    name: "update_support_thread",
    schema: %{
      "type" => "object",
      "required" => ["thread_id"],
      "properties" => %{
        "thread_id" => %{"type" => "string"},
        "status" => %{"type" => "string", "enum" => ["open", "waiting", "resolved"]},
        "owner_id" => %{"type" => "string"}
      }
    },
    output_schema: Atlas.MCP.Serializers.Support.thread_schema()

  alias Atlas.MCP.Serializers.Support, as: SupportSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Support

  @impl EMCP.Tool
  def description, do: "Assign a support conversation or change its lifecycle state."

  def execute(conn, %{"thread_id" => id} = args) do
    with :ok <- Tool.authorize_scope(conn, "support:write", "Support tools"),
         thread when not is_nil(thread) <- Support.get_thread(id),
         {:ok, thread} <- maybe_assign(thread, args["owner_id"], Tool.current_user(conn)),
         {:ok, thread} <- maybe_set_status(thread, args["status"], Tool.current_user(conn)) do
      {:ok, SupportSerializer.thread(Support.get_thread(thread.id))}
    else
      nil -> {:error, "Support conversation not found: #{id}"}
      {:error, reason} -> {:error, "Could not update support conversation: #{inspect(reason)}"}
    end
  end

  def execute(_conn, _args), do: {:error, "thread_id is required."}

  defp maybe_assign(thread, nil, _actor), do: {:ok, thread}
  defp maybe_assign(thread, owner_id, actor), do: Support.assign(thread, owner_id, actor)
  defp maybe_set_status(thread, nil, _actor), do: {:ok, thread}
  defp maybe_set_status(thread, status, actor), do: Support.set_status(thread, status, actor)
end
