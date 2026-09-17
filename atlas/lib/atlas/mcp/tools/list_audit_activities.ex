defmodule Atlas.MCP.Tools.ListAuditActivities do
  @moduledoc """
  Lists audit activities for executive users.
  """

  use Atlas.MCP.Tool,
    name: "list_audit_activities",
    schema: %{
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string", "description" => "Search actor, action, target, or metadata."},
        "interface" => %{
          "type" => "string",
          "enum" => Atlas.Audit.interfaces(),
          "description" => "Filter by the interface that originated the activity."
        },
        "action" => %{"type" => "string", "description" => "Filter by exact action name, e.g. account.updated."},
        "actor_email" => %{"type" => "string", "description" => "Filter by exact actor email."},
        "target_type" => %{"type" => "string", "description" => "Filter by target type, e.g. account."},
        "target_id" => %{"type" => "string", "description" => "Filter by exact target id."},
        "occurred_after" => %{"type" => "string", "description" => "Inclusive ISO-8601 date or datetime lower bound."},
        "occurred_before" => %{"type" => "string", "description" => "Inclusive ISO-8601 date or datetime upper bound."},
        "page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "activities" => %{"type" => "array", "items" => Atlas.Audit.serialize_schema()},
        "pagination" => %{
          "type" => "object",
          "properties" => %{
            "current_page" => %{"type" => "integer"},
            "page_size" => %{"type" => "integer"},
            "total_count" => %{"type" => "integer"},
            "total_pages" => %{"type" => "integer"},
            "has_next_page?" => %{"type" => "boolean"},
            "has_previous_page?" => %{"type" => "boolean"}
          },
          "required" => [
            "current_page",
            "page_size",
            "total_count",
            "total_pages",
            "has_next_page?",
            "has_previous_page?"
          ],
          "additionalProperties" => false
        }
      },
      "required" => ["activities", "pagination"],
      "additionalProperties" => false
    }

  alias Atlas.Audit
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "List Atlas audit activities. Only available to admins."

  def execute(conn, args) do
    with :ok <- Tool.authorize_executive(conn, "Audit tools") do
      {activities, meta} =
        args
        |> list_opts()
        |> Audit.list_activities()

      {:ok,
       %{
         activities: Enum.map(activities, &Audit.serialize/1),
         pagination: meta
       }}
    end
  end

  defp list_opts(args) do
    [
      page: page(args),
      page_size: Tool.page_size(args),
      query: present(args, "query"),
      interface: present(args, "interface"),
      action: present(args, "action"),
      actor_email: present(args, "actor_email"),
      target_type: present(args, "target_type"),
      target_id: present(args, "target_id"),
      occurred_after: present(args, "occurred_after"),
      occurred_before: present(args, "occurred_before")
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp page(%{"page" => page}) when is_integer(page) and page > 0, do: page
  defp page(_args), do: 1

  defp present(args, key) do
    case Map.get(args, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _value ->
        nil
    end
  end
end
