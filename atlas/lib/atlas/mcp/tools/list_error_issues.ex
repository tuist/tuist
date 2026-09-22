defmodule Atlas.MCP.Tools.ListErrorIssues do
  @moduledoc "Lists tracked error issues, optionally filtered by project or status."

  use Atlas.MCP.Tool,
    name: "list_error_issues",
    schema: %{
      "type" => "object",
      "properties" => %{
        "project_id" => %{"type" => "string"},
        "status" => %{"type" => "string", "enum" => ["unresolved", "resolved", "ignored"]},
        "search" => %{"type" => "string"},
        "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "issues" => %{"type" => "array", "items" => %{"type" => "object"}}
      },
      "required" => ["issues"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Errors

  @impl EMCP.Tool
  def description, do: "List Engineering error issues."

  def execute(_conn, args) do
    opts =
      []
      |> maybe_put(:project_id, args["project_id"])
      |> maybe_put(:status, cast_status(args["status"]))
      |> maybe_put(:search, args["search"])
      |> maybe_put(:limit, args["limit"])

    issues = Errors.list_issues(opts) |> Enum.map(&Errors.serialize_issue/1)
    {:ok, %{"issues" => issues}}
  end

  defp maybe_put(list, _key, nil), do: list
  defp maybe_put(list, key, value), do: Keyword.put(list, key, value)

  defp cast_status(nil), do: nil
  defp cast_status(str) when is_binary(str), do: String.to_existing_atom(str)
end
