defmodule Atlas.MCP.Tools.ListTasks do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "list_tasks",
    schema: %{
      "type" => "object",
      "properties" => %{
        "scope" => %{"type" => "string", "enum" => ["mine", "all"], "description" => "Defaults to mine."},
        "status" => %{"type" => "string", "enum" => ["open", "completed"]},
        "account_id" => %{"type" => "string"},
        "query" => %{"type" => "string", "description" => "Search task titles, details, and account names."},
        "page_size" => %{"type" => "integer", "description" => "Maximum number of tasks to return (up to 100)."}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"tasks" => %{"type" => "array", "items" => Atlas.MCP.Serializers.Tasks.task_schema()}},
      "required" => ["tasks"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Serializers.Tasks, as: TaskSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Tasks

  @impl EMCP.Tool
  def description, do: "List open or completed Atlas tasks assigned to the caller or the team."

  def execute(conn, args) do
    with :ok <- Tool.authorize_authenticated(conn, "Task tools") do
      opts = [
        status: args["status"] || "open",
        account_id: args["account_id"],
        query: args["query"],
        limit: Tool.page_size(args)
      ]

      opts = if args["scope"] == "all", do: opts, else: Keyword.put(opts, :assignee_id, Tool.current_user(conn).id)
      {:ok, %{tasks: Tasks.list_tasks(opts) |> Enum.map(&TaskSerializer.task/1)}}
    end
  end
end
