defmodule Atlas.MCP.Tools.DeleteErrorAlertRule do
  @moduledoc "Deletes an error alert rule."

  use Atlas.MCP.Tool,
    name: "delete_error_alert_rule",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{"id" => %{"type" => "string", "format" => "uuid"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["deleted"],
      "properties" => %{"deleted" => %{"type" => "boolean"}},
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Alerts
  alias Atlas.MCP.Tools.ErrorAlertRules

  @impl EMCP.Tool
  def description,
    do: "Delete an error alert rule. Requires engineering:write. Queued deliveries recheck rule existence."

  def execute(conn, args) do
    with :ok <- ErrorAlertRules.validate(__MODULE__, conn, args, "write"),
         {:ok, rule} <- ErrorAlertRules.rule(conn, args["id"]),
         {:ok, _} <- Alerts.delete_rule(rule) do
      {:ok, %{"deleted" => true}}
    else
      {:error, :not_found} -> {:error, "Alert rule not found."}
      error -> error
    end
  end
end
