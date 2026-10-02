defmodule Atlas.MCP.Tools.UpdateTask do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "update_task",
    schema: %{
      "type" => "object",
      "required" => ["task_id"],
      "properties" => %{
        "task_id" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "description" => %{"type" => ["string", "null"]},
        "assignee_id" => %{"type" => "string"},
        "account_id" => %{"type" => ["string", "null"]},
        "due_on" => %{
          "type" => ["string", "null"],
          "format" => "date",
          "description" => "Task due date, or null to remove it."
        },
        "remind_at" => %{
          "type" => ["string", "null"],
          "description" => "ISO 8601 date and time with offset, or null to remove the reminder."
        }
      }
    },
    output_schema: Atlas.MCP.Serializers.Tasks.response_schema()

  alias Atlas.MCP.Serializers.Tasks, as: TaskSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Tasks

  @impl EMCP.Tool
  def description, do: "Edit or reschedule a task."

  def execute(conn, %{"task_id" => id} = args) do
    with :ok <- Tool.authorize_authenticated(conn, "Task tools"),
         %{} = task <- Tasks.get_task(id),
         {:ok, updated} <-
           Tasks.update_task(
             task,
             Map.take(args, ["title", "description", "assignee_id", "account_id", "due_on", "remind_at"]),
             Tool.current_user(conn),
             interface: "mcp"
           ) do
      {:ok, %{task: TaskSerializer.task(updated)}}
    else
      nil ->
        {:error, "Task not found."}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Could not update task: #{Tool.format_changeset_errors(changeset)}"}

      {:error, reason} ->
        {:error, "Could not update task: #{inspect(reason)}"}
    end
  end
end
