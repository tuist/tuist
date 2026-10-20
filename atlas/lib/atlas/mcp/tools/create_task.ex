defmodule Atlas.MCP.Tools.CreateTask do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "create_task",
    schema: %{
      "type" => "object",
      "required" => ["title"],
      "properties" => %{
        "title" => %{"type" => "string"},
        "description" => %{"type" => "string"},
        "assignee_id" => %{"type" => "string", "description" => "Atlas user id. Defaults to the caller."},
        "account_id" => %{"type" => "string"},
        "due_on" => %{"type" => "string", "format" => "date", "description" => "Task due date."},
        "remind_at" => %{
          "type" => "string",
          "description" => "ISO 8601 date and time with offset, for a Slack reminder."
        }
      }
    },
    output_schema: Atlas.MCP.Serializers.Tasks.response_schema()

  alias Atlas.MCP.Serializers.Tasks, as: TaskSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Tasks

  @impl EMCP.Tool
  def description,
    do: "Create a task for an Atlas user, optionally linked to an account and scheduled for a Slack reminder."

  def execute(conn, args) do
    with :ok <- Tool.authorize_authenticated(conn, "Task tools"),
         actor = Tool.current_user(conn),
         attrs =
           args
           |> Map.take(["title", "description", "assignee_id", "account_id", "due_on", "remind_at"])
           |> Map.put_new("assignee_id", actor.id),
         {:ok, task} <- Tasks.create_task(attrs, actor, interface: "mcp") do
      {:ok, %{task: TaskSerializer.task(task)}}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Could not create task: #{Tool.format_changeset_errors(changeset)}"}

      {:error, reason} ->
        {:error, "Could not create task: #{inspect(reason)}"}
    end
  end
end
