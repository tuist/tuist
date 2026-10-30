defmodule Atlas.MCP.Tools.DeleteTask do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "delete_task",
    schema: %{"type" => "object", "required" => ["task_id"], "properties" => %{"task_id" => %{"type" => "string"}}},
    output_schema: %{
      "type" => "object",
      "required" => ["deleted"],
      "properties" => %{"deleted" => %{"type" => "boolean"}},
      "additionalProperties" => false
    }

  alias Atlas.MCP.Tool
  alias Atlas.Native
  alias Atlas.Tasks

  @impl EMCP.Tool
  def description, do: "Delete a shared Atlas task. Pending reminders become harmless."

  def execute(conn, %{"task_id" => id}) do
    with :ok <- Tool.authorize_authenticated(conn, "Task tools"),
         {:ok, task} <- Native.get("tasks", id),
         {:ok, _deleted} <- Tasks.delete_task(task, Tool.current_user(conn), interface: "mcp") do
      {:ok, %{deleted: true}}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, :not_found} -> {:error, "Task not found."}
      _error -> {:error, "Could not delete task."}
    end
  end
end
