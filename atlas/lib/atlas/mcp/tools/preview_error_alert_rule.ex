defmodule Atlas.MCP.Tools.PreviewErrorAlertRule do
  @moduledoc "Evaluates a windowed rule without enqueuing or delivering notifications."

  use Atlas.MCP.Tool,
    name: "preview_error_alert_rule",
    schema: %{
      "type" => "object",
      "required" => ["id", "at"],
      "properties" => %{
        "id" => %{"type" => "string", "format" => "uuid"},
        "at" => %{"type" => "string", "format" => "date-time"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["at", "matches"],
      "properties" => %{
        "at" => %{"type" => "string"},
        "matches" => %{"type" => "array", "items" => %{"type" => "object"}}
      },
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Alerts
  alias Atlas.Engineering.Alerts.Rule
  alias Atlas.Engineering.Errors
  alias Atlas.MCP.Tools.ErrorAlertRules

  @impl EMCP.Tool
  def description do
    "Read-only preview of an event_spike rule at an ISO8601 time, including disabled rules. " <>
      "Uses the same project/environment/level/window query as live evaluation, never sends alerts. " <>
      "Requires engineering:read. Missing retained history is not proof that a period was healthy."
  end

  def execute(conn, args) do
    with :ok <- ErrorAlertRules.validate(__MODULE__, conn, args, "read"),
         {:ok, %Rule{trigger: :event_spike} = rule} <- ErrorAlertRules.rule(conn, args["id"]),
         {:ok, at, _offset} <- DateTime.from_iso8601(args["at"]),
         true <- Errors.enabled?(),
         {:ok, matches} <- Alerts.spike_matches(rule, at) do
      {:ok, %{"at" => DateTime.to_iso8601(at), "matches" => matches}}
    else
      {:error, :not_found} -> {:error, "Alert rule not found."}
      {:ok, %Rule{}} -> {:error, "Only event_spike rules support historical preview."}
      false -> {:error, "Error event storage is not configured."}
      {:error, :spike_query_failed} -> {:error, "Error event storage could not be queried."}
      {:error, reason} when is_atom(reason) -> {:error, "Invalid preview time."}
      error -> error
    end
  end
end
