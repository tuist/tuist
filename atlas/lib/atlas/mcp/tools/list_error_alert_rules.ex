defmodule Atlas.MCP.Tools.ListErrorAlertRules do
  @moduledoc "Lists a project's error alert rules without disclosing webhook credentials."

  use Atlas.MCP.Tool,
    name: "list_error_alert_rules",
    schema: %{
      "type" => "object",
      "required" => ["project_id"],
      "properties" => %{"project_id" => %{"type" => "string", "format" => "uuid"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["rules"],
      "properties" => %{"rules" => %{"type" => "array", "items" => %{"type" => "object"}}},
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Alerts
  alias Atlas.MCP.Tools.ErrorAlertRules

  @impl EMCP.Tool
  def description,
    do:
      "List error alert rules for an Engineering project. Requires engineering:read. Webhook URLs and signing secrets are never returned."

  def execute(conn, args) do
    with :ok <- ErrorAlertRules.validate(__MODULE__, conn, args, "read"),
         {:ok, project} <- ErrorAlertRules.project(conn, args["project_id"]) do
      {:ok, %{"rules" => Enum.map(Alerts.list_rules_for_project(project), &ErrorAlertRules.serialize/1)}}
    else
      {:error, :not_found} -> {:error, "Project not found."}
      error -> error
    end
  end
end
