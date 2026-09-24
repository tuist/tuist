defmodule Atlas.MCP.Serializers.Tasks do
  alias Atlas.MCP.Tool

  def task(task) do
    %{
      id: task.id,
      title: task.title,
      description: task.description,
      status: task.status,
      assignee_id: task.assignee_id,
      account_id: task.account_id,
      due_on: task.due_on && Date.to_iso8601(task.due_on),
      remind_at: Tool.iso8601(task.remind_at),
      reminded_at: Tool.iso8601(task.reminded_at),
      completed_at: Tool.iso8601(task.completed_at)
    }
  end

  def task_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "description" => %{"type" => ["string", "null"]},
        "status" => %{"type" => "string"},
        "assignee_id" => %{"type" => ["string", "null"]},
        "account_id" => %{"type" => ["string", "null"]},
        "due_on" => %{"type" => ["string", "null"]},
        "remind_at" => %{"type" => ["string", "null"]},
        "reminded_at" => %{"type" => ["string", "null"]},
        "completed_at" => %{"type" => ["string", "null"]}
      },
      "required" => ~w(id title description status assignee_id account_id due_on remind_at reminded_at completed_at),
      "additionalProperties" => false
    }
  end

  def response_schema do
    %{
      "type" => "object",
      "properties" => %{"task" => task_schema()},
      "required" => ["task"],
      "additionalProperties" => false
    }
  end
end
