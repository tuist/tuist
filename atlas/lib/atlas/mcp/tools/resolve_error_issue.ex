defmodule Atlas.MCP.Tools.ResolveErrorIssue do
  @moduledoc "Marks an error issue resolved."

  use Atlas.MCP.Tool,
    name: "resolve_error_issue",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{"id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"issue" => %{"type" => "object"}},
      "required" => ["issue"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Errors

  @impl EMCP.Tool
  def description, do: "Mark an Engineering error issue as resolved."

  def execute(_conn, %{"id" => id}) do
    with {:ok, issue} <- Errors.fetch_issue(id),
         {:ok, updated} <- Errors.update_issue_status(issue, :resolved) do
      updated = %{updated | project: issue.project}
      {:ok, %{"issue" => Errors.serialize_issue(updated)}}
    else
      {:error, :not_found} -> {:error, "Error issue not found."}
      other -> other
    end
  end
end
