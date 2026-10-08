defmodule Atlas.MCP.Tools.CompleteTask do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "complete_task",
    schema: %{"type" => "object", "required" => ["task_id"], "properties" => %{"task_id" => %{"type" => "string"}}},
    output_schema: Atlas.MCP.Serializers.Tasks.response_schema()

  alias Atlas.MCP.Serializers.Tasks, as: TaskSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Tasks

  @impl EMCP.Tool
  def description, do: "Mark an Atlas task as completed and cancel its pending reminder."

  def execute(conn, %{"task_id" => id}) do
    with :ok <- Tool.authorize_authenticated(conn, "Task tools"),
         %{} = task <- Tasks.get_task(id),
         {:ok, completed} <- Tasks.complete_task(task, Tool.current_user(conn), interface: "mcp") do
      {:ok, %{task: TaskSerializer.task(completed)}}
    else
      nil -> {:error, "Task not found."}
      {:error, :already_completed} -> {:error, "Task is already completed."}
      {:error, reason} -> {:error, "Could not complete task: #{inspect(reason)}"}
    end
  end
end
