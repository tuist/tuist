defmodule Atlas.MCP.Tools.GetErrorIssue do
  @moduledoc "Fetches a single error issue by id."

  use Atlas.MCP.Tool,
    name: "get_error_issue",
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
  def description, do: "Fetch an Engineering error issue by id."

  def execute(_conn, %{"id" => id}) do
    case Errors.fetch_issue(id) do
      {:ok, issue} -> {:ok, %{"issue" => Errors.serialize_issue(issue)}}
      {:error, :not_found} -> {:error, "Error issue not found."}
    end
  end
end
